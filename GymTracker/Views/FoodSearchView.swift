import SwiftUI
import SwiftData

struct FoodSearchView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \FoodItem.lastUsed, order: .reverse) private var savedFoods: [FoodItem]

    @State private var query = ""
    @State private var results: [FoodDraft] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selected: FoodDraft?
    @State private var showScanner = false
    @State private var showManual = false
    @State private var barcodeMessage: String?

    private var savedMatches: [FoodItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty { return Array(savedFoods.prefix(15)) }
        return savedFoods.filter { $0.name.lowercased().contains(q) || $0.brand.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !savedMatches.isEmpty {
                    Section("Your foods") {
                        ForEach(savedMatches, id: \.persistentModelID) { item in
                            Button { selected = item.draft } label: { FoodRow(draft: item.draft) }
                                .foregroundStyle(.primary)
                        }
                    }
                }
                Section {
                    if isSearching {
                        HStack { ProgressView(); Text("Searching…").foregroundStyle(.secondary) }
                    } else if let searchError {
                        Text(searchError).foregroundStyle(.secondary)
                    } else if query.count < 2 {
                        Text("Type a food name, or scan a barcode.").foregroundStyle(.secondary)
                    } else if results.isEmpty {
                        Text("No results. Try fewer words, or add it manually.").foregroundStyle(.secondary)
                    }
                    ForEach(results) { draft in
                        Button { selected = draft } label: { FoodRow(draft: draft) }
                            .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Open Food Facts")
                } footer: {
                    if let barcodeMessage { Text(barcodeMessage) }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .task(id: query) { await runSearch() }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Scan barcode", systemImage: "barcode.viewfinder") { showScanner = true }
                    Button("Manual entry", systemImage: "square.and.pencil") { showManual = true }
                }
            }
            .sheet(item: $selected) { draft in
                LogFoodView(draft: draft) { dismiss() }
            }
            .sheet(isPresented: $showScanner) {
                BarcodeScannerView { code in
                    showScanner = false
                    Task { await lookup(barcode: code) }
                }
            }
            .sheet(isPresented: $showManual) { AddIntakeView() }
        }
    }

    private func runSearch() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(400))   // debounce typing
        guard !Task.isCancelled else { return }
        isSearching = true
        searchError = nil
        do {
            let found = try await OpenFoodFactsClient.shared.search(q)
            guard !Task.isCancelled else { return }
            results = found
        } catch is CancellationError {
            return
        } catch {
            searchError = "Search failed. Check your connection."
        }
        isSearching = false
    }

    private func lookup(barcode: String) async {
        barcodeMessage = "Looking up \(barcode)…"
        do {
            if let draft = try await OpenFoodFactsClient.shared.product(barcode: barcode) {
                barcodeMessage = nil
                selected = draft
            } else {
                barcodeMessage = "Barcode \(barcode) is not in Open Food Facts yet. Add it manually."
            }
        } catch {
            barcodeMessage = "Lookup failed for \(barcode). Check your connection."
        }
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
            .font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// Pick an amount and log it. Upserts the food into "Your foods".
struct LogFoodView: View {
    var draft: FoodDraft
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var savedFoods: [FoodItem]
    @State private var grams: Double = 100

    private var macros: Macros { draft.macros(forGrams: grams) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(draft.displayName).font(.headline)
                    HStack {
                        Text("Amount")
                        Spacer()
                        TextField("g", value: $grams, format: .number.precision(.fractionLength(0...1)))
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        Text("g").foregroundStyle(.secondary)
                    }
                    HStack {
                        if let serving = draft.servingGrams, serving > 0 {
                            Button("1 serving\(draft.servingDescription.map { " (\($0))" } ?? "")") { grams = serving }
                            Button("2 servings") { grams = serving * 2 }
                        }
                        Button("100 g") { grams = 100 }
                        Button("1 oz") { grams = 28.35 }
                    }
                    .buttonStyle(.bordered).font(.caption)
                }
                Section("This amount") {
                    LabeledContent("Calories", value: "\(Units.number(macros.kcal, maxFraction: 0)) kcal")
                    LabeledContent("Protein", value: "\(Units.number(macros.protein, maxFraction: 0)) g")
                    LabeledContent("Carbs", value: "\(Units.number(macros.carbs, maxFraction: 0)) g")
                    LabeledContent("Fat", value: "\(Units.number(macros.fat, maxFraction: 0)) g")
                    LabeledContent("Fibre", value: "\(Units.number(macros.fibre, maxFraction: 0)) g")
                }
            }
            .navigationTitle("Log food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log") { log() }.disabled(grams <= 0) }
            }
            .onAppear { if let serving = draft.servingGrams, serving > 0 { grams = serving } }
        }
    }

    private func log() {
        let m = macros
        context.insert(IntakeEntry(name: draft.displayName, kcal: m.kcal, protein: m.protein, carbs: m.carbs,
                                   fat: m.fat, fibre: m.fibre, grams: grams))
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
        try? context.save()
        dismiss()
        onLogged()
    }
}
