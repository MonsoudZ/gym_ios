import SwiftUI
import SwiftData

// MARK: - Detail

/// What an exercise is, how to do it, and what it trains: the guide text and movement diagram
/// for library exercises, the muscle map and targets for every exercise. Reached from a program
/// day, the picker, the workout menu and a lift's progress screen.
struct ExerciseDetailView: View {
    var exercise: Exercise

    @Query private var settingsList: [UserSettings]
    private var metric: Bool { settingsList.first?.usesMetric ?? false }
    private var guide: ExerciseGuide? { ExerciseGuides.guide(for: exercise.name) }

    var body: some View {
        List {
            if let guide {
                Section {
                    Text(guide.summary)
                    LabeledContent("Equipment", value: guide.equipment)
                        .font(.subheadline)
                    MovementGuideView(pattern: guide.pattern, implement: guide.implement, cues: guide.cues)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                } header: {
                    Text("How to do it")
                } footer: {
                    Text("The figure loops through the lift and back; the dashed line is \(guide.pattern.pathDescription). It is schematic, not to scale.")
                }
            } else {
                Section {
                    Text("A custom exercise. The muscle map and targets below are what you set for it; there is no guide text or diagram.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                MuscleMap(muscles: exercise.muscles)
                    .frame(height: 320)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel(exercise.muscles.involvementSummary)
                if exercise.muscles.isEmpty {
                    Text("No muscles set. Edit the exercise to add them, so its sets count toward weekly volume.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let tiers = exercise.muscles.byInvolvement
                    ForEach(MuscleInvolvement.allCases) { tier in
                        if let muscles = tiers[tier], !muscles.isEmpty {
                            HStack(spacing: 8) {
                                MuscleSwatch(tier: tier)
                                LabeledContent(tier.pluralName, value: muscles.map(\.displayName).joined(separator: ", "))
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text("Each set counts as a full hard set for a primary mover, half for a secondary, a quarter for a stabiliser.")
            }

            Section {
                LabeledContent("Sets", value: "\(exercise.setCount)")
                LabeledContent("Reps", value: "\(exercise.repRangeLow)–\(exercise.repRangeHigh)")
                LabeledContent("RPE cap", value: Units.number(exercise.rpeCap))
                LabeledContent("Add when progressing", value: Units.weight(exercise.increment, metric: metric))
                LabeledContent("Rest between sets", value: RestRule.label(exercise.restSeconds))
            } header: {
                Text("Targets")
            } footer: {
                Text("Progress when every set hits the top of the rep range at or under the RPE cap.")
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Edit") { ExerciseEditorView(exercise: exercise) }
            }
        }
    }

}

/// The detail view in a sheet of its own, for places that are not inside a navigation stack
/// that can push it (the picker, the workout, a lift's progress screen).
struct ExerciseGuideSheet: View {
    var exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
