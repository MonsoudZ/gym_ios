import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyweightEntry.date) private var weights: [BodyweightEntry]
    @Query(sort: \IntakeEntry.date, order: .reverse) private var intake: [IntakeEntry]
    @Query private var settingsList: [UserSettings]
    @Query(sort: \AdjustmentEntry.date, order: .reverse) private var adjustments: [AdjustmentEntry]

    @State private var showAddFood = false
    @State private var showSaveMeal = false
    @State private var weightText = ""
    @FocusState private var weightFieldFocused: Bool
    /// The day the food list and the weigh-in field refer to. Today by default; the arrows
    /// step back so a forgotten dinner or weigh-in can be put on the day it belongs to.
    @State private var shownDay = Calendar.current.startOfDay(for: .now)

    private var settings: UserSettings? { settingsList.first }
    private var calendar: Calendar { Calendar.current }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var showingToday: Bool { shownDay == today }
    private var shownDayLabel: String {
        if showingToday { return "Today" }
        if calendar.isDateInYesterday(shownDay) { return "Yesterday" }
        return shownDay.formatted(.dateTime.weekday(.wide).day().month())
    }
    private var shownWeight: BodyweightEntry? { weights.first { $0.date == shownDay } }

    var body: some View {
        NavigationStack {
            List {
                if let settings {
                    let snap = NutritionService.snapshot(settings: settings, weights: weights, intake: intake)
                    targetSection(snap, settings: settings)
                    expenditureSection(snap, settings: settings)
                    bodyweightSection(snap, settings: settings)
                    daySection
                }
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add food", systemImage: "plus") { showAddFood = true }
                        .accessibilityLabel("Add food for \(shownDayLabel)")
                }
            }
            .sheet(isPresented: $showAddFood) { FoodSearchView(logDate: shownDay) }
            .sheet(isPresented: $showSaveMeal) { SaveMealView() }
            .navigationDestination(for: WeighInList.Destination.self) { _ in
                WeighInList(shownDay: $shownDay, weightText: $weightText)
            }
            // After midnight the remembered day would be "yesterday"; the tab reopens on today.
            .onAppear { if shownDay != today { shownDay = today; weightText = "" } }
        }
    }

    /// Yesterday / today / a date, with arrows. Shared by the food list and the weigh-in field.
    private var dayPicker: some View {
        HStack {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous day")
            Spacer()
            VStack(spacing: 2) {
                Text(shownDayLabel).font(.headline)
                if !showingToday {
                    Button("Back to today") { shownDay = today }.font(.caption)
                }
            }
            Spacer()
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .disabled(showingToday)
                .accessibilityLabel("Next day")
        }
        .buttonStyle(.borderless)
    }

    private func step(_ days: Int) {
        guard let day = calendar.date(byAdding: .day, value: days, to: shownDay), day <= today else { return }
        shownDay = day
        weightText = ""
    }

    private func targetSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section("Today's target") {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Units.number(snap.targetKcal, maxFraction: 0)) kcal")
                    .font(.title.bold().monospacedDigit())
                Text(snap.isProvisional
                     ? NutritionSnapshot.provisionalNote
                     : "Adaptive: measured expenditure \(Units.number(snap.baseKcal, maxFraction: 0)) kcal, \(settings.goal.label.lowercased()) at \(Units.percent(settings.goalRatePercentPerWeek))/week.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MacroProgressRow(label: "Calories", eaten: snap.eatenToday.kcal, target: snap.targetKcal, unit: "kcal")
            MacroProgressRow(label: "Protein", eaten: snap.eatenToday.protein, target: snap.macros.protein, unit: "g")
            MacroProgressRow(label: "Fat", eaten: snap.eatenToday.fat, target: snap.macros.fat, unit: "g")
            MacroProgressRow(label: "Carbs", eaten: snap.eatenToday.carbs, target: snap.macros.carbs, unit: "g")
            MacroProgressRow(label: "Fibre", eaten: snap.eatenToday.fibre, target: snap.macros.fibre, unit: "g")
        }
    }

    @ViewBuilder private func expenditureSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section("Expenditure") {
            if let est = snap.estimate {
                LabeledContent("Measured TDEE") { Text("\(Units.number(est.tdee, maxFraction: 0)) kcal").monospacedDigit() }
                LabeledContent("Confidence") { Text("\(est.confidence.label) · \(est.loggedDays) days").monospacedDigit() }
                LabeledContent("Trend change") { Text("\(Units.weight(est.weightChangeKg, metric: settings.usesMetric)) over \(est.spanDays) days").monospacedDigit() }
            } else {
                Text("Log intake and weight for at least 4 days to measure expenditure.")
                    .foregroundStyle(.secondary)
            }
            if let rate = snap.trendRatePercentPerWeek {
                LabeledContent("Trend rate") { Text("\(Units.percent(rate))/week vs goal \(Units.percent(settings.goalRatePercentPerWeek))").monospacedDigit() }
            }
            if let adj = snap.suggestedAdjustment {
                VStack(alignment: .leading, spacing: 6) {
                    Text(adj.kcal == 0 ? "Weekly check: hold calories." : "Weekly check: \(adj.kcal > 0 ? "+" : "")\(adj.kcal) kcal/day.")
                        .font(.headline)
                    if let note = adj.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    Button("Apply and start next week") {
                        settings.applyAdjustment(adj, trendRatePercentPerWeek: snap.trendRatePercentPerWeek ?? 0, in: context)
                        context.saveOrLog()
                    }
                    .buttonStyle(.bordered)
                }
            }
            if !adjustments.isEmpty {
                adjustmentHistory(settings: settings)
            }
        }
    }

    /// The last few weekly checks, newest first, so the direction of the adjustments can be read.
    @ViewBuilder private func adjustmentHistory(settings: UserSettings) -> some View {
        let recent = Array(adjustments.prefix(6))
        DisclosureGroup {
            ForEach(recent, id: \.persistentModelID) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.date, format: .dateTime.day().month())
                        Spacer()
                        Text(entry.kcal == 0 ? "Held" : "\(entry.kcal > 0 ? "+" : "")\(entry.kcal) kcal")
                            .monospacedDigit()
                            .foregroundStyle(entry.kcal == 0 ? .secondary : .primary)
                    }
                    Text("Trend \(Units.percent(entry.trendRatePercentPerWeek))/week vs goal \(Units.percent(entry.goalRatePercentPerWeek)) · total \(entry.cumulativeKcalAfter >= 0 ? "+" : "")\(Units.number(entry.cumulativeKcalAfter, maxFraction: 0)) kcal")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        } label: {
            LabeledContent("Past checks") {
                Text("\(adjustments.count) · total \(settings.cumulativeAdjustmentKcal >= 0 ? "+" : "")\(Units.number(settings.cumulativeAdjustmentKcal, maxFraction: 0)) kcal")
                    .monospacedDigit()
            }
        }
    }

    private func bodyweightSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section {
            HStack {
                TextField(showingToday ? "This morning's weight" : "Weight on \(shownDayLabel.lowercased())", text: $weightText)
                    .keyboardType(.decimalPad)
                    .font(.body.monospacedDigit())
                    .focused($weightFieldFocused)
                    .accessibilityLabel("Weight for \(shownDayLabel)")
                Text(settings.usesMetric ? "kg" : "lb").foregroundStyle(.secondary)
                Button(showingToday ? "Log today" : "Log") { logWeight(metric: settings.usesMetric) }
                    .disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
            }
            if let shownWeight {
                LabeledContent(showingToday ? "Logged today" : "Logged \(shownDayLabel.lowercased())") {
                    Text("\(Units.weight(shownWeight.kg, metric: settings.usesMetric))\(shownWeight.fromHealth ? " · Health" : "")")
                        .monospacedDigit()
                }
                .font(.subheadline)
            }
            if snap.raw.count >= 2 {
                Chart {
                    ForEach(snap.raw, id: \.date) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Scale", display(p.value, settings)))
                            .foregroundStyle(.secondary.opacity(0.5)).symbolSize(16)
                    }
                    ForEach(snap.trend, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Trend", display(p.value, settings)))
                            .foregroundStyle(Color.accentColor).lineStyle(StrokeStyle(lineWidth: 2))
                    }
                    // The goal rate as a dashed reference through the latest trend point.
                    if settings.goalRatePercentPerWeek != 0, let first = snap.trend.first, let last = snap.trend.last, first.date < last.date {
                        let weeks = last.date.timeIntervalSince(first.date) / (7 * 86_400)
                        let startValue = last.value / (1 + settings.goalRatePercentPerWeek / 100 * weeks)
                        LineMark(x: .value("Date", first.date), y: .value("Goal", display(startValue, settings)), series: .value("Series", "Goal"))
                            .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        LineMark(x: .value("Date", last.date), y: .value("Goal", display(last.value, settings)), series: .value("Series", "Goal"))
                            .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                .accessibilityLabel("Bodyweight chart: trend \(Units.weight(snap.latestWeightKg, metric: settings.usesMetric)) over \(snap.raw.count) weigh-ins")
                LabeledContent("Trend weight") { Text(Units.weight(snap.latestWeightKg, metric: settings.usesMetric)).monospacedDigit() }
                NavigationLink(value: WeighInList.Destination.list) {
                    Label("All weigh-ins (\(weights.count))", systemImage: "list.bullet")
                }
            } else {
                EmptyState("No trend yet", systemImage: "scalemass",
                           description: "Weigh in each morning. After two days the line shows your trend and the dots show the scale.") {
                    Button("Log weight") { weightFieldFocused = true }
                }
            }
        } header: {
            Text("Bodyweight")
        } footer: {
            if !showingToday {
                Text("Use the arrows under Food to pick the day a weigh-in belongs to.")
            }
        }
    }

    private var daySection: some View {
        Section {
            dayPicker
            let entries = intake.filter { calendar.isDate($0.date, inSameDayAs: shownDay) }
            if entries.isEmpty {
                EmptyState(showingToday ? "Nothing logged today" : "Nothing logged", systemImage: "fork.knife",
                           description: showingToday ? "Log what you eat and the target above fills in." : "Add what you ate on \(shownDayLabel.lowercased()) and the expenditure estimate uses it.") {
                    Button("Add food") { showAddFood = true }
                }
            } else if !showingToday {
                let kcal = entries.reduce(0) { $0 + $1.kcal }
                let protein = entries.reduce(0) { $0 + $1.protein }
                LabeledContent("Day total") {
                    Text("\(Units.number(kcal, maxFraction: 0)) kcal · P \(Units.number(protein, maxFraction: 0))").monospacedDigit()
                }
                .font(.subheadline)
            }
            ForEach(entries, id: \.persistentModelID) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        Text("\(entry.grams.map { "\(Units.number($0, maxFraction: 0)) g · " } ?? "")P \(Units.number(entry.protein, maxFraction: 0)) · C \(Units.number(entry.carbs, maxFraction: 0)) · F \(Units.number(entry.fat, maxFraction: 0))")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Units.number(entry.kcal, maxFraction: 0)) kcal").monospacedDigit()
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(entries[index]) }
                context.saveOrLog()
                LogReminders.refresh(context: context)
            }
            if !intake.isEmpty {
                Button("Save foods as a meal", systemImage: "square.stack") { showSaveMeal = true }
            }
        } header: {
            Text("Food")
        }
    }

    private func display(_ kg: Double, _ settings: UserSettings) -> Double {
        settings.usesMetric ? kg : kg * Units.lbPerKg
    }

    private func logWeight(metric: Bool) {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return }
        let kg = metric ? value : value / Units.lbPerKg
        if let existing = shownWeight {
            existing.kg = kg
            existing.fromHealth = false   // typed over: Health no longer updates this day
        } else {
            context.insert(BodyweightEntry(date: shownDay, kg: kg))
        }
        context.saveOrLog()
        LogReminders.refresh(context: context)
        weightText = ""
    }
}

/// Every weigh-in, newest first. Swipe to delete; tap one to bring its day up on the Nutrition
/// tab with the value in the field, ready to retype.
struct WeighInList: View {
    enum Destination: Hashable { case list }

    @Binding var shownDay: Date
    @Binding var weightText: String

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \BodyweightEntry.date, order: .reverse) private var weights: [BodyweightEntry]
    @Query private var settingsList: [UserSettings]
    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    var body: some View {
        List {
            Section {
                ForEach(weights, id: \.persistentModelID) { entry in
                    Button {
                        shownDay = entry.date
                        weightText = Units.number(Units.display(entry.kg, metric: metric))
                        dismiss()
                    } label: {
                        HStack {
                            Text(entry.date, format: .dateTime.weekday(.abbreviated).day().month().year())
                            Spacer()
                            if entry.fromHealth {
                                Image(systemName: "heart").foregroundStyle(.secondary).accessibilityLabel("From Health")
                            }
                            Text(Units.weight(entry.kg, metric: metric)).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    for index in offsets { context.delete(weights[index]) }
                    context.saveOrLog()
                    LogReminders.refresh(context: context)
                }
            } footer: {
                Text("Tap a weigh-in to correct it, swipe to delete it. The trend and expenditure estimate update.")
            }
        }
        .navigationTitle("Weigh-ins")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AddIntakeView: View {
    var logDate: Date = .now
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fibre: Double?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                numberField("Calories", $kcal, unit: "kcal")
                numberField("Protein", $protein, unit: "g")
                numberField("Carbs", $carbs, unit: "g")
                numberField("Fat", $fat, unit: "g")
                numberField("Fibre", $fibre, unit: "g")
            }
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(kcal == nil && protein == nil && carbs == nil && fat == nil)
                }
            }
        }
    }

    private func numberField(_ label: String, _ value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    private func save() {
        let p = protein ?? 0, c = carbs ?? 0, f = fat ?? 0
        let energy = kcal ?? (4 * p + 4 * c + 9 * f)
        context.insert(IntakeEntry(date: IntakeEntry.timestamp(for: logDate), name: name.isEmpty ? "Food" : name,
                                   kcal: energy, protein: p, carbs: c, fat: f, fibre: fibre ?? 0))
        context.saveOrLog()
        LogReminders.refresh(context: context)
        dismiss()
    }
}
