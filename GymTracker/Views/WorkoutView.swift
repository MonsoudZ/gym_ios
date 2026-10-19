import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    var body: some View {
        List {
            ForEach(session.orderedExercises, id: \.persistentModelID) { exercise in
                Section {
                    lastTimeRow(exercise)
                    ForEach(session.sets(for: exercise), id: \.persistentModelID) { set in
                        SetRow(set: set, unit: metric ? "kg" : "lb", metric: metric)
                    }
                } header: {
                    Text(exercise.name)
                } footer: {
                    Text("Target \(exercise.repRangeLow)–\(exercise.repRangeHigh) reps, RPE \(Units.number(exercise.rpeCap)) or below.")
                }
            }
        }
        .navigationTitle(session.templateDayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") { finish() }
            }
        }
    }

    @ViewBuilder private func lastTimeRow(_ exercise: Exercise) -> some View {
        if let last = exercise.sessionResults().last, let weight = ProgressionEngine.topWorkingWeight(last.sets) {
            let reps = last.sets.filter { !$0.isWarmup }.map { "\($0.reps)" }.joined(separator: ", ")
            let rpe = last.sets.compactMap(\.rpe).max().map { " @ \(Units.rpeLabel($0))" } ?? ""
            Text("Last: \(Units.weight(weight, metric: metric)) × \(reps)\(rpe)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func finish() {
        for set in session.sets where set.reps <= 0 {
            context.delete(set)
        }
        session.isCompleted = !session.sets.isEmpty
        if session.sets.isEmpty { context.delete(session) }
        try? context.save()
        dismiss()
    }
}

struct SetRow: View {
    @Bindable var set: SetEntry
    var unit: String
    var metric: Bool

    private static let rpeValues: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    private var displayWeight: Binding<Double> {
        Binding(get: { metric ? set.weight : set.weight * Units.lbPerKg },
                set: { set.weight = metric ? $0 : $0 / Units.lbPerKg })
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(set.setNumber + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16)
            TextField(unit, value: displayWeight, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 64)
                .textFieldStyle(.roundedBorder)
            Text(unit).font(.caption).foregroundStyle(.secondary)
            TextField("reps", value: $set.reps, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 48)
                .textFieldStyle(.roundedBorder)
            Text("reps").font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Picker("RPE", selection: $set.rpe) {
                Text("RPE").tag(Double?.none)
                ForEach(Self.rpeValues, id: \.self) { value in
                    Text(Units.number(value)).tag(Double?.some(value))
                }
            }
            .labelsHidden()
            Button {
                set.completedAt = set.completedAt == nil ? .now : nil
            } label: {
                Image(systemName: set.completedAt == nil ? "circle" : "checkmark.circle.fill")
                    .foregroundStyle(set.completedAt == nil ? Color.secondary : Color.green)
            }
            .buttonStyle(.plain)
        }
    }
}
