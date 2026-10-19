import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]
    @Query private var intake: [IntakeEntry]
    @Query(sort: \BodyweightEntry.date) private var weights: [BodyweightEntry]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query private var readinessEntries: [ReadinessEntry]

    @State private var activeSession: WorkoutSession?
    /// Keeps the readiness inputs open while the lifter is typing; reset whenever the tab is shown.
    @State private var editingReadiness = false

    private var settings: UserSettings? { settingsList.first }
    private var completed: [WorkoutSession] { sessions.filter(\.isCompleted) }
    private var inProgress: WorkoutSession? { sessions.first { !$0.isCompleted } }

    private var activeProgram: Program? { settings?.activeProgram(in: programs) }

    /// Today's check-in, persisted so it survives leaving the tab.
    private var todayEntry: ReadinessEntry? { ReadinessEntry.entry(for: .now, in: readinessEntries) }

    private var readiness: Readiness? {
        guard let todayEntry, todayEntry.isLogged else { return nil }
        return todayEntry.readiness
    }

    /// The entry to write into, created on first input.
    private func entryForEditing() -> ReadinessEntry {
        if let todayEntry { return todayEntry }
        let entry = ReadinessEntry(date: .now)
        context.insert(entry)
        return entry
    }

    private var sleepHours: Binding<Double?> {
        Binding(get: { todayEntry?.sleepHours },
                set: { editingReadiness = true; entryForEditing().sleepHours = $0; context.saveOrLog() })
    }

    private func isSore(_ muscle: Muscle) -> Binding<Bool> {
        Binding(get: { todayEntry?.soreMuscles.contains(muscle) ?? false },
                set: { on in
                    editingReadiness = true
                    let entry = entryForEditing()
                    var sore = entry.soreMuscles
                    if on { sore.insert(muscle) } else { sore.remove(muscle) }
                    entry.soreMuscles = sore
                    context.saveOrLog()
                })
    }

    /// Today's day and its plan, computed once per render and handed to every section.
    private struct Today {
        var day: ProgramDay
        var plan: [PlannedExercise]
        var headline: PlannedExercise? {
            plan.first { $0.prescription.stallAction != nil } ?? plan.first { $0.prescription.isNotable } ?? plan.first
        }
    }

    private func makeToday() -> Today? {
        guard let activeProgram, let settings,
              let day = PlanService.nextDay(in: activeProgram, completedSessions: completed) else { return nil }
        let plan = PlanService.plan(day: day, exercises: exercises, completedSessions: completed,
                                    readiness: readiness, metric: settings.usesMetric)
        return Today(day: day, plan: plan)
    }

    var body: some View {
        let today = makeToday()
        NavigationStack {
            List {
                if let inProgress {
                    Section {
                        NavigationLink(value: inProgress) {
                            Label("Continue \(inProgress.templateDayName)", systemImage: "play.fill")
                        }
                    }
                } else if let today {
                    headlineSection(today)
                    readinessSection(today)
                    sessionSection(today)
                } else {
                    Section {
                        EmptyState("No days yet", systemImage: "calendar.badge.plus",
                                   description: "Add a day and some exercises, and today's plan will appear here.") {
                            if let activeProgram {
                                NavigationLink("Add a day", value: activeProgram)
                            }
                        }
                    }
                }
                nutritionSection
            }
            .navigationTitle("Today")
            .toolbar {
                if let activeProgram {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(value: activeProgram) {
                            Image(systemName: "list.bullet.rectangle")
                        }
                        .accessibilityLabel("Edit program: \(activeProgram.name)")
                    }
                }
            }
            .navigationDestination(for: Program.self) { ProgramEditorView(program: $0) }
            .navigationDestination(for: WorkoutSession.self) { WorkoutView(session: $0) }
            .navigationDestination(item: $activeSession) { WorkoutView(session: $0) }
            .onAppear { editingReadiness = false }
        }
    }

    @ViewBuilder private func headlineSection(_ today: Today) -> some View {
        if let headline = today.headline, let settings {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(today.day.name).font(.title2.bold())
                    Text(headlineText(headline, metric: settings.usesMetric))
                        .font(.headline.monospacedDigit())
                    if let action = headline.prescription.stallAction {
                        StallBadge(action: action, streak: headline.prescription.stallStreak)
                    }
                    Text(headline.prescription.reason)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                NavigationLink {
                    ExerciseProgressView(exercise: headline.exercise)
                } label: {
                    Label(headline.prescription.stallAction == nil
                          ? "\(headline.exercise.name) history"
                          : "Why: see \(headline.exercise.name) history",
                          systemImage: "chart.line.uptrend.xyaxis")
                }
                Button {
                    startWorkout(today)
                } label: {
                    Label("Start workout", systemImage: "figure.strengthtraining.traditional")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
    }

    private func readinessSection(_ today: Today) -> some View {
        let logged = todayEntry?.isLogged == true
        return Section {
            if logged, !editingReadiness, let todayEntry {
                HStack {
                    Label(readinessSummary(todayEntry), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .symbolRenderingMode(.multicolor)
                    Spacer()
                    Button("Edit") { editingReadiness = true }
                        .font(.subheadline)
                }
                .accessibilityElement(children: .combine)
            } else {
                HStack {
                    Text("Sleep last night")
                    Spacer()
                    TextField("e.g. 7.5", value: sleepHours, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .font(.body.monospacedDigit())
                        .frame(width: 80)
                        .accessibilityLabel("Sleep last night in hours")
                    Text("h").foregroundStyle(.secondary)
                }
                let muscles = Set(today.plan.flatMap { $0.exercise.muscles.filter { $0.weight >= 0.5 }.map(\.muscle) })
                    .sorted { $0.displayName < $1.displayName }
                let soreCount = todayEntry?.soreMuscles.count ?? 0
                DisclosureGroup("Very sore in\(soreCount == 0 ? "" : " (\(soreCount))")") {
                    ForEach(muscles) { muscle in
                        Toggle(muscle.displayName, isOn: isSore(muscle))
                            .accessibilityHint("Marks \(muscle.displayName.lowercased()) as very sore today, which makes lifts that use it 5% lighter")
                    }
                }
                if logged {
                    Button("Done") { editingReadiness = false }
                        .font(.subheadline)
                }
            }
        } header: {
            Text(logged ? "Readiness · logged for today" : "Readiness (optional)")
        } footer: {
            if !logged {
                Text("Under 6 h of sleep, or a very sore working muscle, makes today 5% lighter.")
            }
        }
    }

    private func readinessSummary(_ entry: ReadinessEntry) -> String {
        var parts: [String] = []
        if let sleep = entry.sleepHours { parts.append("Slept \(Units.number(sleep)) h") }
        let sore = entry.soreMuscles.map(\.displayName).sorted()
        if !sore.isEmpty { parts.append("Sore: \(sore.joined(separator: ", "))") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func sessionSection(_ today: Today) -> some View {
        if let settings {
            Section("Plan") {
                ForEach(today.plan) { item in
                    NavigationLink {
                        ExerciseProgressView(exercise: item.exercise)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(item.exercise.name).font(.body.weight(.medium))
                                Spacer()
                                if let action = item.prescription.stallAction {
                                    StallBadge(action: action, streak: item.prescription.stallStreak)
                                } else if item.prescription.lastVerdict == .progressed {
                                    VerdictBadge(verdict: .progressed)
                                        .accessibilityLabel("Progressed last session")
                                }
                            }
                            Text(prescriptionLine(item.prescription, metric: settings.usesMetric))
                                .font(.subheadline.monospacedDigit())
                            Text(item.prescription.reason)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section("Nutrition") {
            if let settings {
                let snap = NutritionService.snapshot(settings: settings, weights: weights, intake: intake)
                MacroProgressRow(label: "Calories", eaten: snap.eatenToday.kcal, target: snap.targetKcal, unit: "kcal")
                MacroProgressRow(label: "Protein", eaten: snap.eatenToday.protein, target: snap.macros.protein, unit: "g")
                if snap.isProvisional {
                    Text(NutritionSnapshot.provisionalNote)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func headlineText(_ item: PlannedExercise, metric: Bool) -> String {
        let p = item.prescription
        let sets = "\(p.setCount) × \(p.repRangeLow)–\(p.repRangeHigh)"
        if p.needsStartingWeight { return "\(item.exercise.name): choose a starting weight" }
        return "\(item.exercise.name): \(Units.weight(p.weight, metric: metric)), \(sets)"
    }

    private func prescriptionLine(_ p: Prescription, metric: Bool) -> String {
        if p.needsStartingWeight { return "\(p.setCount) × \(p.repRangeLow)–\(p.repRangeHigh), weight to be chosen" }
        return "\(Units.weight(p.weight, metric: metric)) · \(p.setCount) × \(p.repRangeLow)–\(p.repRangeHigh) · RPE ≤ \(Units.number(9))"
    }

    private func startWorkout(_ today: Today) {
        let session = WorkoutSession(templateDayName: today.day.name, readiness: todayEntry)
        session.programDayID = today.day.id
        context.insert(session)
        for (order, item) in today.plan.enumerated() {
            for number in 0..<item.prescription.setCount {
                let set = SetEntry(exerciseOrder: order, setNumber: number, weight: item.prescription.weight)
                set.exercise = item.exercise
                set.session = session
                context.insert(set)
            }
        }
        context.saveOrLog()
        activeSession = session
    }
}

/// "Deload · stalled 3 sessions": what the engine decided and how long the lift has been stuck.
struct StallBadge: View {
    var action: StallAction
    var streak: Int

    private var text: String {
        streak > 0 ? "\(action.label) · stalled \(streak) session\(streak == 1 ? "" : "s")" : action.label
    }

    var body: some View {
        Label(text, systemImage: action.systemImage)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
            .accessibilityLabel(text)
    }
}

struct MacroProgressRow: View {
    var label: String
    var eaten: Double
    var target: Double
    var unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(Units.number(eaten, maxFraction: 0)) / \(Units.number(target, maxFraction: 0)) \(unit)")
                    .monospacedDigit().foregroundStyle(.secondary)
            }
            ProgressView(value: min(eaten, target), total: max(target, 1))
        }
    }
}
