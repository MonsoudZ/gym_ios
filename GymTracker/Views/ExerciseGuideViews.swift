import SwiftUI
import SwiftData

// MARK: - Detail

/// What an exercise is, how to do it, and what it trains: the guide text and movement diagram
/// for library exercises, the muscle map and targets for every exercise, and a History tab of
/// records and recent sessions. Reached from a program day, the picker, the workout screen, the
/// Today plan and a lift's progress screen.
struct ExerciseDetailView: View {
    enum Tab: String, CaseIterable, Identifiable {
        case guide, history
        var id: Self { self }
        var title: String { self == .guide ? "Guide" : "History" }
    }

    var exercise: Exercise
    var initialTab: Tab = .guide

    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }) private var completedSessions: [WorkoutSession]
    @Environment(\.switchTab) private var switchTab
    @State private var tab: Tab?

    private var metric: Bool { settingsList.first?.usesMetric ?? false }
    /// By the library name the exercise was created from, so a renamed lift keeps its guide.
    private var guide: ExerciseGuide? { ExerciseGuides.guide(for: exercise.librarySpecName ?? exercise.name) }

    var body: some View {
        let selected = tab ?? initialTab
        List {
            Section {
                Picker("Section", selection: Binding(get: { selected }, set: { tab = $0 })) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
            if selected == .history {
                historySections
            } else {
                guideSections
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

    // MARK: Guide

    @ViewBuilder private var guideSections: some View {
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

            if let notes = exercise.notes, !notes.isEmpty {
                Section("Your notes") { Text(notes) }
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

    // MARK: History

    /// Personal records and the last five sessions, newest first. Each row opens its session
    /// for correction, as the Progress tab's rows do; the trend chart stays on the Progress tab.
    @ViewBuilder private var historySections: some View {
        let history = exercise.sessionResults()
        if history.isEmpty {
            Section {
                EmptyState("Not logged yet", systemImage: "clock.arrow.circlepath",
                           description: "Records and past sessions appear here once \(exercise.name) has been logged in a workout.") {
                    Button("Go to Today") { switchTab(.today) }
                }
            }
        } else {
            let records = PersonalRecords.compute(from: history, repRangeLow: exercise.repRangeLow, repRangeHigh: exercise.repRangeHigh)
            let latest = history.last
            let latestE1RM = latest.flatMap { OneRepMax.best(from: $0.sets) }
            let latestTop = latest.flatMap { ProgressionEngine.topWorkingWeight($0.sets) }
            Section {
                if let record = records.bestE1RM {
                    recordRow("Best e1RM", value: Units.weight(record.e1RM ?? 0, metric: metric), record: record,
                              comparison: latestE1RM.map { "Latest session \(Units.weight($0, metric: metric))" }
                                  ?? "Latest session had no set of \(OneRepMax.maxTrustedReps) reps or fewer")
                }
                if let record = records.bestInRepRange {
                    recordRow("Heaviest at \(exercise.repRangeLow)–\(exercise.repRangeHigh) reps", value: Units.weight(record.weight, metric: metric), record: record,
                              comparison: latestTop.map { "Latest top set \(Units.weight($0, metric: metric))" })
                }
                if let record = records.mostRepsAtTopWeight {
                    recordRow("Most reps at \(Units.weight(record.weight, metric: metric))", value: "\(record.reps) reps", record: record,
                              comparison: latest.flatMap { session in
                                  session.sets.filter { !$0.isWarmup && $0.weight == record.weight }.map(\.reps).max().map { "Latest session \($0) reps" }
                              })
                }
            } header: {
                Text("Personal records")
            } footer: {
                Text("Working sets only. e1RM is the Epley estimate from sets of 10 reps or fewer. Correct a mistyped set from its session below and the records update.")
            }

            let recent = PersonalRecords.recent(history)
            let annotations = Dictionary(ProgressionEngine.annotate(history: history, config: exercise.config).map { ($0.date, $0) },
                                         uniquingKeysWith: { first, _ in first })
            Section {
                ForEach(recent, id: \.date) { result in
                    sessionLink(for: result.sessionID) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(result.date, format: .dateTime.day().month().year())
                                Spacer()
                                if let note = annotations[result.date] {
                                    VerdictBadge(verdict: note.verdict)
                                }
                            }
                            Text(result.sets.filter { !$0.isWarmup }
                                .map { "\(Units.weight($0.weight, metric: metric)) × \($0.reps)\($0.rpe.map { " @\(Units.number($0))" } ?? "")" }
                                .joined(separator: "  ·  "))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if let note = annotations[result.date] { MissReasonLabel(annotation: note) }
                        }
                    }
                }
            } header: {
                Text(history.count > recent.count ? "Last \(recent.count) of \(history.count) sessions" : "Sessions")
            } footer: {
                Text("Tap a session to correct a mistyped set or delete it. The full trend is on the Progress tab.")
            }
        }
    }

    private func recordRow(_ title: String, value: String, record: PersonalRecords.Record, comparison: String?) -> some View {
        sessionLink(for: record.sessionID) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                    Spacer()
                    Text(value).bold().monospacedDigit()
                }
                Text("\(record.setLabel(metric: metric)) · \(record.date.formatted(.dateTime.day().month().year()))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                if let comparison {
                    Text(comparison).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// A row opens its session for editing when the session still exists.
    @ViewBuilder private func sessionLink<Content: View>(for sessionID: UUID?, @ViewBuilder content: () -> Content) -> some View {
        if let session = completedSessions.first(where: { $0.id == sessionID }) {
            NavigationLink { SessionEditorView(session: session, insideSheet: true) } label: { content() }
        } else {
            content()
        }
    }
}

/// The detail view in a sheet of its own, for places that are not inside a navigation stack
/// that can push it (the picker, the workout, a lift's progress screen).
struct ExerciseGuideSheet: View {
    var exercise: Exercise
    var initialTab: ExerciseDetailView.Tab = .guide
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise, initialTab: initialTab)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}
