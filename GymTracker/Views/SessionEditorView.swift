import SwiftUI
import SwiftData

/// Corrects a finished workout: a mistyped weight or rep count, a wrong date, or a session
/// that should not exist. Verdicts, prescriptions and volume are recomputed from the sets,
/// so fixing a set here fixes everything downstream (DESIGN.md §5).
struct SessionEditorView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    @State private var confirmDelete = false
    /// Set before the session is deleted so the body stops reading it.
    @State private var deleted = false

    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    var body: some View {
        Group {
            if deleted {
                Color.clear
            } else {
                form
            }
        }
        .onDisappear(perform: tidy)
    }

    private var form: some View {
        List {
            Section {
                DatePicker("Date", selection: $session.date, in: ...Date.now,
                           displayedComponents: [.date, .hourAndMinute])
            } footer: {
                Text("Today's program day follows the most recent session by date.")
            }
            ForEach(session.orderedExercises, id: \.persistentModelID) { exercise in
                let exerciseSets = session.sets(for: exercise)
                Section {
                    ForEach(Array(exerciseSets.enumerated()), id: \.element.persistentModelID) { index, set in
                        let workingNumber = exerciseSets.prefix(index + 1).filter { !$0.isWarmup }.count
                        SetRow(set: set, displayNumber: workingNumber, unit: metric ? "kg" : "lb",
                               metric: metric, showsDoneButton: false)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button(set.isWarmup ? "Working" : "Warm-up", systemImage: set.isWarmup ? "flame.fill" : "flame") {
                                    set.isWarmup.toggle()
                                }
                                .tint(.orange)
                            }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(exerciseSets[index]) }
                        context.saveOrLog()
                    }
                    Button("Add set", systemImage: "plus") {
                        session.addSet(for: exercise, in: context)
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                } header: {
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        VerdictBadge(verdict: verdict(for: exerciseSets, exercise: exercise))
                            .textCase(nil)
                    }
                } footer: {
                    Text("Swipe a set to delete it, or right to mark it a warm-up.")
                }
            }
            Section("Notes") {
                TextField("How did it go?", text: Binding(
                    get: { session.notes ?? "" },
                    set: { session.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }),
                    axis: .vertical)
                    .lineLimit(1...4)
                    .accessibilityLabel("Session notes")
            }
            Section {
                Button("Delete workout", systemImage: "trash", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(session.templateDayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete workout", role: .destructive, action: deleteSession)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sets leave every lift's history, trend and volume. This can't be undone.")
        }
    }

    private func verdict(for sets: [SetEntry], exercise: Exercise) -> Verdict {
        ProgressionEngine.verdict(for: sets.map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, isWarmup: $0.isWarmup) },
                                  config: exercise.config)
    }

    private func deleteSession() {
        deleted = true
        removeFromHealth()
        context.delete(session)
        context.saveOrLog()
        dismiss()
    }

    /// Leaving drops sets whose reps were cleared, as finishing a workout does, and removes a
    /// session left with no sets, so an empty entry never counts as a missed workout.
    private func tidy() {
        guard !deleted else { return }
        for set in session.sets where set.reps <= 0 { context.delete(set) }
        if session.sets.allSatisfy({ $0.reps <= 0 }) {
            removeFromHealth()
            context.delete(session)
        }
        context.saveOrLog()
    }

    /// A session that was saved to Health takes its workout with it.
    private func removeFromHealth() {
        guard let id = session.healthWorkoutID else { return }
        Task { await HealthService.deleteWorkout(id: id) }
    }
}
