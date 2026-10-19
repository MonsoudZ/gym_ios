import SwiftUI
import SwiftData

struct MealRow: View {
    var meal: SavedMeal

    var body: some View {
        let totals = meal.totals()
        VStack(alignment: .leading, spacing: 2) {
            Text(meal.name).lineLimit(1)
            Text("\(meal.components.count) food\(meal.components.count == 1 ? "" : "s") · \(Units.number(totals.kcal, maxFraction: 0)) kcal · P \(Units.number(totals.protein, maxFraction: 0)) · C \(Units.number(totals.carbs, maxFraction: 0)) · F \(Units.number(totals.fat, maxFraction: 0))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Logs every food in a saved meal at once, optionally at a different portion.
struct LogMealView: View {
    var meal: SavedMeal
    var onLogged: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 1.0

    private static let portions: [(label: String, value: Double)] = [("½", 0.5), ("1", 1), ("1½", 1.5), ("2", 2)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Portion", selection: $scale) {
                        ForEach(Self.portions, id: \.value) { Text("\($0.label)×").tag($0.value) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Foods") {
                    ForEach(Array(meal.components.enumerated()), id: \.offset) { _, component in
                        let c = component.scaled(by: scale)
                        HStack {
                            VStack(alignment: .leading) {
                                Text(c.name)
                                if let grams = c.grams {
                                    Text("\(Units.number(grams, maxFraction: 0)) g").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text("\(Units.number(c.kcal, maxFraction: 0)) kcal").monospacedDigit()
                        }
                    }
                }
                Section("Total") {
                    let t = meal.totals(scale: scale)
                    LabeledContent("Calories") { Text("\(Units.number(t.kcal, maxFraction: 0)) kcal").monospacedDigit() }
                    LabeledContent("Protein") { Text("\(Units.number(t.protein, maxFraction: 0)) g").monospacedDigit() }
                    LabeledContent("Carbs") { Text("\(Units.number(t.carbs, maxFraction: 0)) g").monospacedDigit() }
                    LabeledContent("Fat") { Text("\(Units.number(t.fat, maxFraction: 0)) g").monospacedDigit() }
                }
            }
            .navigationTitle(meal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Log meal") { log() } }
            }
        }
    }

    private func log() {
        meal.log(scale: scale, in: context)
        context.saveOrLog()
        LogReminders.refresh(context: context)
        dismiss()
        onLogged()
    }
}

/// Builds a meal from foods already logged in the last few days: tick the ones that belong
/// together and name it. Saving under an existing name replaces that meal.
struct SaveMealView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \IntakeEntry.date, order: .reverse) private var intake: [IntakeEntry]
    @Query private var meals: [SavedMeal]

    @State private var name = ""
    @State private var picked: Set<PersistentIdentifier> = []
    @State private var seeded = false

    private static let lookbackDays = 3

    private var recent: [IntakeEntry] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -(Self.lookbackDays - 1), to: Calendar.current.startOfDay(for: .now))!
        return intake.filter { $0.date >= cutoff }
    }

    private var days: [(day: Date, entries: [IntakeEntry])] {
        let grouped = Dictionary(grouping: recent) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.date < $1.date }) }
    }

    private var chosen: [IntakeEntry] { recent.filter { picked.contains($0.persistentModelID) }.sorted { $0.date < $1.date } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Meal name, e.g. Usual breakfast", text: $name)
                }
                if recent.isEmpty {
                    Section {
                        EmptyState("Nothing to save yet", systemImage: "fork.knife",
                                   description: "Log the foods of a meal once, then save them here as one meal.")
                    }
                }
                ForEach(days, id: \.day) { group in
                    Section(Self.dayLabel(group.day)) {
                        ForEach(group.entries, id: \.persistentModelID) { entry in
                            Toggle(isOn: binding(for: entry)) {
                                HStack {
                                    Text(entry.name).lineLimit(1)
                                    Spacer()
                                    Text("\(Units.number(entry.kcal, maxFraction: 0)) kcal")
                                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Save as meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(chosen.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                // Today's foods are the likely meal, so they start ticked.
                guard !seeded else { return }
                seeded = true
                picked = Set(recent.filter { Calendar.current.isDateInToday($0.date) }.map(\.persistentModelID))
            }
        }
    }

    private static func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }

    private func binding(for entry: IntakeEntry) -> Binding<Bool> {
        Binding(get: { picked.contains(entry.persistentModelID) },
                set: { on in
                    if on { picked.insert(entry.persistentModelID) } else { picked.remove(entry.persistentModelID) }
                })
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let meal = SavedMeal(name: trimmed, from: chosen)
        if let existing = meals.first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            existing.components = meal.components
        } else {
            context.insert(meal)
        }
        context.saveOrLog()
        dismiss()
    }
}
