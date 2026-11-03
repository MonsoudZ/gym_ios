import SwiftUI
import SwiftData

struct FoodSearchView: View {
    /// The day the food is logged to. Today unless the Nutrition tab is showing another day.
    var logDate: Date = .now
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var savedFoods: [FoodItem]
    @Query(sort: \SavedMeal.lastUsed, order: .reverse) private var savedMeals: [SavedMeal]

    @State private var query = ""
    @State private var selectedMeal: SavedMeal?
    @State private var results: [FoodDraft] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selected: FoodDraft?
    @State private var showScanner = false
    @State private var showManual = false
    @State private var creating = false
    @State private var editingFood: FoodItem?
    @State private var barcode: BarcodeLookup?
    @State private var searchAttempt = 0

    private enum BarcodeLookup: Equatable {
        case looking(String), notFound(String), failed(String)
    }

    private struct SearchKey: Hashable {
        var query: String
        var attempt: Int
    }

    private var savedMatches: [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(savedFoods.prefix(15)) }
        return savedFoods.filter { $0.name.lowercased().contains(q) || $0.brand.lowercased().contains(q) }
    }

    private var genericMatches: [FoodDraft] { GenericFoods.search(query.trimmingCharacters(in: .whitespaces)) }

    private var mealMatches: [SavedMeal] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(savedMeals.prefix(10)) }
        return savedMeals.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !mealMatches.isEmpty {
                    Section {
                        ForEach(mealMatches, id: \.persistentModelID) { meal in
                            Button { selectedMeal = meal } label: { MealRow(meal: meal) }
                                .foregroundStyle(.primary)
                        }
                        .onDelete { offsets in
                            let doomed = offsets.map { mealMatches[$0] }
                            doomed.forEach(context.delete)
                            context.saveOrLog()
                        }
                    } header: {
                        Text("Your meals")
                    } footer: {
                        Text("Swipe a meal to delete it. Save a new one from Nutrition, under Logged today.")
                    }
                }
                Section {
                    Button("Scan barcode", systemImage: "barcode.viewfinder") { showScanner = true }
                    barcodeRow
                }
                if !savedMatches.isEmpty {
                    Section {
                        ForEach(savedMatches, id: \.persistentModelID) { item in
                            Button { selected = item.draft } label: { FoodRow(draft: item.draft) }
                                .foregroundStyle(.primary)
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        context.delete(item)
                                        context.saveOrLog()
                                    }
                                    Button("Edit", systemImage: "pencil") { editingFood = item }.tint(.blue)
                                }
                        }
                    } header: {
                        Text("Your foods")
                    } footer: {
                        Text("Swipe a food to edit its nutrition and measures, or delete it. Foods already logged keep their numbers.")
                    }
                }
                if !genericMatches.isEmpty {
                    Section {
                        ForEach(genericMatches) { draft in
                            Button { selected = draft } label: { FoodRow(draft: draft) }
                                .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Common foods")
                    } footer: {
                        Text("Typical values per 100 g (USDA), with cups and pieces for measuring. A scanned label wins for a specific product.")
                    }
                }
                Section("Open Food Facts") {
                    if isSearching {
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    } else if let searchError {
                        StatusRow(text: searchError, systemImage: "wifi.exclamationmark", action: "Retry") { searchAttempt += 1 }
                    } else if query.count < 2 {
                        EmptyState("Search by name", systemImage: "magnifyingglass",
                                   description: "Type a food name above to search the Open Food Facts database.")
                    } else if results.isEmpty {
                        StatusRow(text: "No products for “\(query)”. Try fewer words.", systemImage: "magnifyingglass",
                                  action: "Create it") { creating = true }
                    }
                    ForEach(results) { draft in
                        Button { selected = draft } label: { FoodRow(draft: draft) }
                            .foregroundStyle(.primary)
                    }
                }
                Section {
                    Button("Create a food", systemImage: "plus.circle") { creating = true }
                    Button("Quick entry, just the totals", systemImage: "square.and.pencil") { showManual = true }
                } footer: {
                    Text("Create a food from its label, with a serving, cup or piece weight, and it stays under Your foods. Quick entry logs one amount and keeps nothing.")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .task(id: SearchKey(query: query, attempt: searchAttempt)) { await runSearch() }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .sheet(item: $selected) { draft in
                LogFoodView(draft: draft, logDate: logDate) { dismiss() }
            }
            .sheet(item: $selectedMeal) { meal in
                LogMealView(meal: meal, logDate: logDate) { dismiss() }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    showScanner = false
                    Task { await lookup(barcode: code) }
                }
            }
            .sheet(isPresented: $showManual) { AddIntakeView(logDate: logDate) }
            .sheet(isPresented: $creating) {
                NewFoodView(editing: nil) { draft in selected = draft }
            }
            .sheet(item: $editingFood) { item in
                NewFoodView(editing: item) { _ in }
            }
        }
    }

    @ViewBuilder private var barcodeRow: some View {
        switch barcode {
        case .looking(let code):
            HStack { ProgressView(); Text("Looking up \(code)…").foregroundStyle(.secondary) }
        case .notFound(let code):
            StatusRow(text: "\(code) is not in Open Food Facts yet.", systemImage: "questionmark.circle",
                      action: "Create it") { creating = true }
        case .failed(let code):
            StatusRow(text: "Lookup failed for \(code). Check your connection.", systemImage: "wifi.exclamationmark",
                      action: "Retry") { Task { await lookup(barcode: code) } }
        case nil:
            EmptyView()
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; isSearching = false; return }
        try? await Task.sleep(for: .milliseconds(400))   // debounce typing
        guard !Task.isCancelled else { return }
        isSearching = true
        searchError = nil
        defer { isSearching = false }   // every exit, cancellation included, clears the spinner
        do {
            let found = try await OpenFoodFactsClient.shared.search(q)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            searchError = "Search failed. Check your connection."
        }
    }

    private func lookup(barcode code: String) async {
        barcode = .looking(code)
        do {
            if let draft = try await OpenFoodFactsClient.shared.product(barcode: code) {
                barcode = nil
                selected = draft
            } else {
                barcode = .notFound(code)
            }
        } catch {
            barcode = .failed(code)
        }
    }
}

/// A problem or empty result as a list row with the one thing to do about it.
struct StatusRow: View {
    var text: String
    var systemImage: String
    var action: String
    var onAction: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Label(text, systemImage: systemImage).foregroundStyle(.secondary)
            Spacer()
            Button(action, action: onAction).font(.subheadline.weight(.medium))
        }
        .accessibilityElement(children: .combine)
    }
}

struct FoodRow: View {
    var draft: FoodDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(draft.name).lineLimit(1)
            HStack(spacing: 4) {
                if !draft.brand.isEmpty { Text(draft.brand).lineLimit(1) }
                Text("\(Units.number(draft.kcalPer100g, maxFraction: 0)) kcal · P \(Units.number(draft.proteinPer100g, maxFraction: 0)) · C \(Units.number(draft.carbsPer100g, maxFraction: 0)) · F \(Units.number(draft.fatPer100g, maxFraction: 0)) per 100 g")
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

/// Pick an amount and log it. Upserts the food into "Your foods".
///
/// The amount is a quantity of a unit: grams or ounces always; cups, tablespoons, teaspoons,
/// millilitres and fluid ounces when the food says what a cup weighs; pieces ("2 large eggs")
/// and label servings when it carries those. The quantity takes fractions as typed: ½, 1/2,
/// 3/4, 1 1/2.
struct LogFoodView: View {
    var draft: FoodDraft
    var logDate: Date = .now
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [FoodItem]
    @State private var quantityText = "1"
    @State private var unit: PortionUnit = .gram
    @FocusState private var quantityFocused: Bool

    private var units: [PortionUnit] { Portion.units(for: draft) }
    private var quantity: Double { Portion.parse(quantityText) ?? 0 }
    private var portion: Portion { Portion(quantity: quantity, unit: unit) }
    private var grams: Double { portion.grams(for: draft) ?? 0 }
    private var macros: Macros { draft.macros(forGrams: grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(draft.displayName).font(.headline)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("1", text: $quantityText)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                            .font(.body.monospacedDigit())
                            .focused($quantityFocused)
                            .accessibilityLabel("Quantity")
                        Picker("Unit", selection: $unit) {
                            ForEach(units) { unit in Text(unitName(unit)).tag(unit) }
                        }
                        .labelsHidden()
                        .accessibilityLabel("Unit")
                    }
                    if unit != .gram {
                        LabeledContent("Weight") {
                            Text(grams > 0 ? "\(Units.number(grams, maxFraction: 0)) g" : "—").monospacedDigit().foregroundStyle(.secondary)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(quickPortions, id: \.self) { quick in
                                Button(quick.label(for: draft)) { set(quick) }
                            }
                        }
                        .buttonStyle(.bordered).font(.caption)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 0))
                } footer: {
                    if draft.gramsPerCup == nil, draft.pieceGrams == nil, draft.servingGrams == nil {
                        Text("This product gives no serving or cup weight, so it is logged by weight.")
                    }
                }
                Section("This amount") {
                    LabeledContent("Calories") { Text("\(Units.number(macros.kcal, maxFraction: 0)) kcal").monospacedDigit() }
                    LabeledContent("Protein") { Text("\(Units.number(macros.protein, maxFraction: 0)) g").monospacedDigit() }
                    LabeledContent("Carbs") { Text("\(Units.number(macros.carbs, maxFraction: 0)) g").monospacedDigit() }
                    LabeledContent("Fat") { Text("\(Units.number(macros.fat, maxFraction: 0)) g").monospacedDigit() }
                    LabeledContent("Fibre") { Text("\(Units.number(macros.fibre, maxFraction: 0)) g").monospacedDigit() }
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { log() }.disabled(grams <= 0) }
                ToolbarItemGroup(placement: .keyboard) {
                    if quantityFocused {
                        Spacer()
                        Button("Done") { quantityFocused = false }
                    }
                }
            }
            .onAppear(perform: startingPortion)
        }
    }

    /// "cup", "large egg", "serving (30 g)".
    private func unitName(_ unit: PortionUnit) -> String {
        switch unit {
        case .piece: draft.pieceName ?? "piece"
        case .serving: "serving" + (draft.servingDescription.map { " (\($0))" } ?? "")
        default: unit.label
        }
    }

    /// The first unit the food is usually measured in, at one of it.
    private func startingPortion() {
        if draft.servingGrams ?? 0 > 0 { set(Portion(quantity: 1, unit: .serving)) }
        else if draft.pieceGrams ?? 0 > 0 { set(Portion(quantity: 1, unit: .piece)) }
        else if draft.gramsPerCup ?? 0 > 0 { set(Portion(quantity: 1, unit: .cup)) }
        else { set(Portion(quantity: 100, unit: .gram)) }
    }

    private var quickPortions: [Portion] {
        var quick: [Portion] = []
        if draft.servingGrams ?? 0 > 0 { quick += [Portion(quantity: 1, unit: .serving), Portion(quantity: 2, unit: .serving)] }
        if draft.pieceGrams ?? 0 > 0 { quick += [Portion(quantity: 1, unit: .piece), Portion(quantity: 2, unit: .piece)] }
        if draft.gramsPerCup ?? 0 > 0 {
            quick += [Portion(quantity: 0.25, unit: .cup), Portion(quantity: 0.5, unit: .cup), Portion(quantity: 0.75, unit: .cup),
                      Portion(quantity: 1, unit: .cup), Portion(quantity: 1, unit: .tablespoon)]
        }
        quick += [Portion(quantity: 100, unit: .gram), Portion(quantity: 1, unit: .ounce)]
        return quick
    }

    private func set(_ portion: Portion) {
        unit = portion.unit
        quantityText = Portion.format(portion.quantity)
    }

    private func log() {
        let m = macros
        context.insert(IntakeEntry(date: IntakeEntry.timestamp(for: logDate), name: draft.displayName, kcal: m.kcal,
                                   protein: m.protein, carbs: m.carbs, fat: m.fat, fibre: m.fibre, grams: grams,
                                   portionLabel: unit == .gram ? nil : portion.label(for: draft)))
        let existing = savedFoods.first { item in
            if let code = draft.barcode, item.barcode == code { return true }
            return item.name == draft.name && item.brand == draft.brand
        }
        if let existing {
            existing.update(from: draft)
            existing.lastUsed = .now
            existing.useCount += 1
        } else {
            let item = FoodItem(draft: draft)
            item.useCount = 1
            context.insert(item)
        }
        context.saveOrLog()
        LogReminders.refresh(context: context)
        dismiss()
        onLogged()
    }
}
