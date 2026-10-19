import SwiftUI
import SwiftData
import Charts

struct NutritionView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyweightEntry.date) private var weights: [BodyweightEntry]
    @Query(sort: \IntakeEntry.date, order: .reverse) private var intake: [IntakeEntry]
    @Query private var settingsList: [UserSettings]

    @State private var showAddFood = false
    @State private var weightText = ""

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        NavigationStack {
            List {
                if let settings {
                    let snap = NutritionService.snapshot(settings: settings, weights: weights, intake: intake)
                    targetSection(snap, settings: settings)
                    expenditureSection(snap, settings: settings)
                    bodyweightSection(snap, settings: settings)
                    todaySection
                }
            }
            .navigationTitle("Nutrition")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add food", systemImage: "plus") { showAddFood = true }
                }
            }
            .sheet(isPresented: $showAddFood) { FoodSearchView() }
        }
    }

    private func targetSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Units.number(snap.targetKcal, maxFraction: 0)) kcal")
                    .font(.title.bold().monospacedDigit())
                Text(snap.isProvisional
                     ? "Provisional, from Mifflin–St Jeor. Becomes adaptive after ~2 weeks of logging."
                     : "Adaptive: measured expenditure \(Units.number(snap.baseKcal, maxFraction: 0)) kcal, \(settings.goal.label.lowercased()) at \(Units.percent(settings.goalRatePercentPerWeek))/week.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            MacroProgressRow(label: "Calories", eaten: snap.eatenToday.kcal, target: snap.targetKcal, unit: "kcal")
            MacroProgressRow(label: "Protein", eaten: snap.eatenToday.protein, target: snap.macros.protein, unit: "g")
            MacroProgressRow(label: "Fat", eaten: snap.eatenToday.fat, target: snap.macros.fat, unit: "g")
            MacroProgressRow(label: "Carbs", eaten: snap.eatenToday.carbs, target: snap.macros.carbs, unit: "g")
            MacroProgressRow(label: "Fibre", eaten: snap.eatenToday.fibre, target: snap.macros.fibre, unit: "g")
        } header: {
            Text("Today's target")
        }
    }

    @ViewBuilder private func expenditureSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section("Expenditure") {
            if let est = snap.estimate {
                LabeledContent("Measured TDEE", value: "\(Units.number(est.tdee, maxFraction: 0)) kcal")
                LabeledContent("Confidence", value: "\(est.confidence.label) · \(est.loggedDays) days")
                LabeledContent("Trend change", value: "\(Units.weight(est.weightChangeKg, metric: settings.usesMetric)) over \(est.spanDays) days")
            } else {
                Text("Log intake and weight for at least 4 days to measure expenditure.")
                    .foregroundStyle(.secondary)
            }
            if let rate = snap.trendRatePercentPerWeek {
                LabeledContent("Trend rate", value: "\(Units.percent(rate))/week vs goal \(Units.percent(settings.goalRatePercentPerWeek))")
            }
            if let adj = snap.suggestedAdjustment {
                VStack(alignment: .leading, spacing: 6) {
                    Text(adj.kcal == 0 ? "Weekly check: hold calories." : "Weekly check: \(adj.kcal > 0 ? "+" : "")\(adj.kcal) kcal/day.")
                        .font(.headline)
                    if let note = adj.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    Button("Apply and start next week") {
                        settings.cumulativeAdjustmentKcal += Double(adj.kcal)
                        settings.lastAdjustmentDate = .now
                        try? context.save()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func bodyweightSection(_ snap: NutritionSnapshot, settings: UserSettings) -> some View {
        Section("Bodyweight") {
            HStack {
                TextField(settings.usesMetric ? "kg" : "lb", text: $weightText)
                    .keyboardType(.decimalPad)
                Button("Log today") { logWeight(metric: settings.usesMetric) }
                    .disabled(Double(weightText.replacingOccurrences(of: ",", with: ".")) == nil)
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
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 200)
                LabeledContent("Trend weight", value: Units.weight(snap.latestWeightKg, metric: settings.usesMetric))
            } else {
                Text("Weigh in each morning. The line is the trend; dots are the scale.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var todaySection: some View {
        Section("Logged today") {
            let today = intake.filter { Calendar.current.isDateInToday($0.date) }
            if today.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            ForEach(today, id: \.persistentModelID) { entry in
                HStack {
                    VStack(alignment: .leading) {
                        Text(entry.name)
                        Text("\(entry.grams.map { "\(Units.number($0, maxFraction: 0)) g · " } ?? "")P \(Units.number(entry.protein, maxFraction: 0)) · C \(Units.number(entry.carbs, maxFraction: 0)) · F \(Units.number(entry.fat, maxFraction: 0))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(Units.number(entry.kcal, maxFraction: 0)) kcal").monospacedDigit()
                }
            }
            .onDelete { offsets in
                for index in offsets { context.delete(today[index]) }
            }
        }
    }

    private func display(_ kg: Double, _ settings: UserSettings) -> Double {
        settings.usesMetric ? kg : kg * Units.lbPerKg
    }

    private func logWeight(metric: Bool) {
        guard let value = Double(weightText.replacingOccurrences(of: ",", with: ".")) else { return }
        let kg = metric ? value : value / Units.lbPerKg
        let today = Calendar.current.startOfDay(for: .now)
        if let existing = weights.first(where: { $0.date == today }) {
            existing.kg = kg
        } else {
            context.insert(BodyweightEntry(date: today, kg: kg))
        }
        try? context.save()
        weightText = ""
    }
}

struct AddIntakeView: View {
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
        context.insert(IntakeEntry(name: name.isEmpty ? "Food" : name, kcal: energy, protein: p, carbs: c, fat: f, fibre: fibre ?? 0))
        try? context.save()
        dismiss()
    }
}
