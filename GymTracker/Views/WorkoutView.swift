import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Bindable var session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]

    /// The rest that is running, started when a set is ticked done. Shared with the Live
    /// Activity, whose buttons act on it from outside this screen.
    private let timer = RestTimer.shared
    @State private var restsFinished = 0
    @State private var confirmPartialFinish = false
    @State private var confirmDiscard = false
    @State private var showAddExercise = false
    @State private var swapping: Exercise?
    @State private var showingGuide: Exercise?

    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    var body: some View {
        List {
            ForEach(session.orderedExercises, id: \.persistentModelID) { exercise in
                let exerciseSets = session.sets(for: exercise)
                Section {
                    lastTimeRow(exercise)
                    ForEach(Array(exerciseSets.enumerated()), id: \.element.persistentModelID) { index, set in
                        // Working sets are numbered among themselves, so warm-ups do not shift "set 1".
                        let workingNumber = exerciseSets.prefix(index + 1).filter { !$0.isWarmup }.count
                        SetRow(set: set, displayNumber: workingNumber, unit: metric ? "kg" : "lb", metric: metric) {
                            if !set.isWarmup { startRest(after: exercise) }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(set.isWarmup ? "Working" : "Warm-up", systemImage: set.isWarmup ? "flame.fill" : "flame") {
                                set.isWarmup.toggle()
                                context.saveOrLog()
                            }
                            .tint(.orange)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(exerciseSets[index]) }
                        context.saveOrLog()
                    }
                    HStack {
                        if !exerciseSets.contains(where: \.isWarmup),
                           let working = exerciseSets.first(where: { !$0.isWarmup }),
                           !WarmupRule.ramp(workingWeight: working.weight, increment: exercise.increment).isEmpty {
                            Button("Warm-up sets", systemImage: "flame") {
                                session.addWarmups(for: exercise, in: context)
                                context.saveOrLog()
                            }
                        }
                        Spacer()
                        Button("Add set", systemImage: "plus") {
                            session.addSet(for: exercise, in: context)
                            context.saveOrLog()
                        }
                    }
                    .font(.subheadline)
                    .buttonStyle(.borderless)
                } header: {
                    // The name opens the guide as a sheet; the rest keeps running underneath,
                    // since the timer is shared and not owned by this screen.
                    HStack(spacing: 6) {
                        Button { showingGuide = exercise } label: {
                            HStack(spacing: 5) {
                                Text(exercise.name)
                                Image(systemName: "info.circle").imageScale(.small)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(exercise.name), how to do it")
                        Spacer()
                        exerciseMenu(exercise, hasLoggedSets: exerciseSets.contains { $0.reps > 0 })
                    }
                } footer: {
                    Text("Target \(exercise.repRangeLow)–\(exercise.repRangeHigh) reps, RPE \(Units.number(exercise.rpeCap)) or below. Rest \(RestRule.label(exercise.restSeconds)). Swipe a set right to mark it a warm-up; warm-ups never count as volume.")
                }
            }
            Section {
                Button("Add exercise", systemImage: "plus.circle") { showAddExercise = true }
            }
        }
        .navigationTitle(session.templateDayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Finish") { requestFinish() }
            }
        }
        .confirmationDialog("Finish with \(session.loggedSetCount) of \(session.sets.count) sets logged?",
                            isPresented: $confirmPartialFinish, titleVisibility: .visible) {
            Button("Finish workout") { finish() }
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("Sets without reps will be removed from this workout.")
        }
        .confirmationDialog("No sets logged. Discard this workout?",
                            isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard workout", role: .destructive) { finish() }
            Button("Keep logging", role: .cancel) {}
        }
        .safeAreaInset(edge: .bottom) {
            if let rest = timer.rest {
                RestTimerBar(rest: rest.endsAt, total: rest.seconds, exerciseName: rest.exerciseName,
                             onAddTime: { timer.addTime() },
                             onSkip: { timer.skip() },
                             onFinished: { restsFinished += 1 })
            }
        }
        .sensoryFeedback(.success, trigger: restsFinished)
        .animation(.snappy, value: timer.rest)
        .sheet(isPresented: $showAddExercise) {
            SessionExercisePicker(session: session, replacing: nil, metric: metric)
        }
        .sheet(item: $showingGuide) { ExerciseGuideSheet(exercise: $0) }
        .sheet(item: $swapping) { old in
            SessionExercisePicker(session: session, replacing: old, metric: metric)
        }
    }

    /// Swap or skip for today only: the program is not edited, and a skipped lift leaves no
    /// sets behind, so it gets no verdict and cannot count as a miss.
    private func exerciseMenu(_ exercise: Exercise, hasLoggedSets: Bool) -> some View {
        Menu {
            Button("How to do it", systemImage: "info.circle") { showingGuide = exercise }
            Button("Swap exercise", systemImage: "arrow.left.arrow.right") { swapping = exercise }
            Button(hasLoggedSets ? "Skip remaining sets" : "Skip exercise", systemImage: "forward.end", role: .destructive) {
                session.skip(exercise, in: context)
                context.saveOrLog()
            }
        } label: {
            Image(systemName: "ellipsis.circle").font(.body)
        }
        .textCase(nil)
        .accessibilityLabel("\(exercise.name) options")
    }

    @ViewBuilder private func lastTimeRow(_ exercise: Exercise) -> some View {
        if let last = exercise.sessionResults().last, let weight = ProgressionEngine.topWorkingWeight(last.sets) {
            let reps = last.sets.filter { !$0.isWarmup }.map { "\($0.reps)" }.joined(separator: ", ")
            let rpe = last.sets.compactMap(\.rpe).max().map { " @ \(Units.rpeLabel($0))" } ?? ""
            Text("Last: \(Units.weight(weight, metric: metric)) × \(reps)\(rpe)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private func startRest(after exercise: Exercise) {
        timer.start(seconds: RestRule.clamp(exercise.restSeconds), exerciseName: exercise.name, dayName: session.templateDayName)
    }

    /// Finishes at once when every set has reps; otherwise asks, since finishing drops the rest.
    private func requestFinish() {
        let logged = session.loggedSetCount
        if logged == 0 {
            confirmDiscard = true
        } else if logged < session.sets.count {
            confirmPartialFinish = true
        } else {
            finish()
        }
    }

    private func finish() {
        timer.finishWorkout()
        // Counted before the deletes: until the save, `session.sets` still lists the deleted sets,
        // so checking it afterwards kept a discarded workout as an empty completed session.
        let hasLoggedSets = session.loggedSetCount > 0
        for set in session.sets where set.reps <= 0 {
            context.delete(set)
        }
        session.isCompleted = hasLoggedSets
        if !hasLoggedSets { context.delete(session) }
        context.saveOrLog()
        if hasLoggedSets, settingsList.first?.saveWorkoutsToHealthEnabled == true {
            let session = session
            Task {
                guard let id = await HealthService.saveWorkout(session) else { return }
                session.healthWorkoutID = id
                context.saveOrLog()
            }
        }
        dismiss()
    }
}

/// Adds an exercise that was not planned, or with `replacing` set, swaps it in for that
/// exercise. Either way it gets the weight the engine would have prescribed.
private struct SessionExercisePicker: View {
    var session: WorkoutSession
    var replacing: Exercise?
    var metric: Bool

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var query = ""

    private var candidates: [Exercise] {
        let inSession = Set(session.orderedExercises.map(\.id))
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter { !inSession.contains($0.id) && (q.isEmpty || $0.name.lowercased().contains(q)
            || $0.muscles.contains { $0.muscle.displayName.lowercased().contains(q) }) }
    }

    /// When swapping, exercises that train the same main muscle come first.
    private var similar: [Exercise] {
        guard let muscle = replacing?.primaryMuscle else { return [] }
        return candidates.filter { $0.primaryMuscle == muscle }
    }

    var body: some View {
        NavigationStack {
            List {
                if !similar.isEmpty, let muscle = replacing?.primaryMuscle {
                    Section("Same muscle: \(muscle.displayName)") { rows(similar) }
                    Section("Everything else") { rows(candidates.filter { !similar.contains($0) }) }
                } else {
                    rows(candidates)
                }
            }
            .searchable(text: $query, prompt: "Search by name or muscle")
            .navigationTitle(replacing.map { "Swap \($0.name)" } ?? "Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func rows(_ list: [Exercise]) -> some View {
        ForEach(list, id: \.persistentModelID) { exercise in
            Button { choose(exercise) } label: { ExerciseSummaryRow(exercise: exercise, metric: metric) }
                .foregroundStyle(.primary)
        }
    }

    private func choose(_ exercise: Exercise) {
        let prescription = PlanService.prescription(for: exercise, readiness: nil, weeklyVolume: [:], metric: metric)
        if let replacing {
            session.swap(replacing, for: exercise, weight: prescription.weight, in: context)
        } else {
            session.addExercise(exercise, weight: prescription.weight, in: context)
        }
        context.saveOrLog()
        dismiss()
    }
}

/// Counts down the rest, then says so once and offers to carry on.
private struct RestTimerBar: View {
    var rest: Date
    var total: Int
    var exerciseName: String
    var onAddTime: () -> Void
    var onSkip: () -> Void
    var onFinished: () -> Void

    @State private var reportedFinished = false

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = Int(rest.timeIntervalSince(timeline.date).rounded(.up))
            let done = remaining <= 0
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(done ? "Rest done" : "Rest \(RestRule.label(remaining))")
                        .font(.title3.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                    Text(done ? "Next set of \(exerciseName)." : "After \(exerciseName)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if !done {
                    Button("+30 s", action: onAddTime)
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add thirty seconds of rest")
                }
                Button(done ? "Go" : "Skip", action: onSkip)
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel(done ? "Dismiss rest timer" : "Skip the rest of the timer")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) {
                ProgressView(value: Double(max(0, min(total, remaining))), total: Double(max(total, 1)))
                    .progressViewStyle(.linear)
                    .tint(done ? .green : .accentColor)
            }
            .onChange(of: done) { _, isDone in
                if isDone, !reportedFinished {
                    reportedFinished = true
                    onFinished()
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(done ? "Rest done" : "Rest, \(RestRule.label(remaining)) left")
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

struct SetRow: View {
    @Bindable var set: SetEntry
    /// Position among the exercise's working sets, 1-based.
    var displayNumber: Int
    var unit: String
    var metric: Bool
    /// Hidden when correcting a finished session, where ticking a set done means nothing.
    var showsDoneButton = true
    /// Called when the set is ticked done, not when it is un-ticked.
    var onComplete: () -> Void = {}

    private static let rpeValues: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    // `self.` is needed: a bare `set` inside a computed property reads as a setter keyword.
    private var isDone: Bool { self.set.completedAt != nil }
    private var canComplete: Bool { self.set.reps > 0 }

    /// Zero means "no weight chosen yet" (an exercise with no history), shown as an empty field.
    private var displayWeight: Binding<Double?> {
        Binding(get: { set.weight > 0 ? (metric ? set.weight : set.weight * Units.lbPerKg) : nil },
                set: { set.weight = max(0, $0.map { metric ? $0 : $0 / Units.lbPerKg } ?? 0) })
    }

    /// Zero means "not logged yet", shown as an empty field so typing does not append to a 0.
    private var displayReps: Binding<Int?> {
        Binding(get: { set.reps > 0 ? set.reps : nil },
                set: { set.reps = max(0, $0 ?? 0) })
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // One line cannot hold two fields, a picker and a button at these sizes.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        setNumber
                        weightField
                        repsField
                    }
                    HStack(spacing: 8) {
                        rpePicker
                        Spacer(minLength: 0)
                        if showsDoneButton { doneButton }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    setNumber
                    weightField
                    repsField
                    Spacer(minLength: 0)
                    rpePicker
                    if showsDoneButton { doneButton }
                }
            }
        }
        .opacity(showsDoneButton && isDone ? 0.55 : 1)
        .listRowBackground(showsDoneButton && isDone ? Color.green.opacity(0.08) : nil)
        .animation(.snappy, value: isDone)
    }

    private var setNumber: some View {
        Group {
            if set.isWarmup {
                Image(systemName: "flame").foregroundStyle(.orange)
                    .accessibilityLabel("Warm-up set")
            } else {
                Text("\(displayNumber)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Set \(displayNumber)")
            }
        }
        .frame(minWidth: 16)
    }

    /// At accessibility sizes the trailing unit words no longer fit beside the fields; the
    /// placeholders and accessibility labels already say what each field is.
    private var showsUnitLabels: Bool { !dynamicTypeSize.isAccessibilitySize }

    private var weightField: some View {
        HStack(spacing: 8) {
            TextField(showsUnitLabels ? "weight" : unit, value: displayWeight, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(minWidth: 64)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .accessibilityLabel("Weight in \(unit)")
            if showsUnitLabels { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var repsField: some View {
        HStack(spacing: 8) {
            TextField("reps", value: displayReps, format: .number)
                .keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(minWidth: 48)
                .textFieldStyle(.roundedBorder)
                .font(.body.monospacedDigit())
                .accessibilityLabel("Reps")
            if showsUnitLabels { Text("reps").font(.caption).foregroundStyle(.secondary) }
        }
    }

    private var rpePicker: some View {
        Picker("RPE", selection: $set.rpe) {
            Text("RPE").tag(Double?.none)
            ForEach(Self.rpeValues, id: \.self) { value in
                Text(Units.number(value)).tag(Double?.some(value))
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("RPE, rate of perceived exertion")
        .accessibilityHint("How hard the set felt, 6 to 10")
    }

    private var doneButton: some View {
        Button {
            toggleDone()
        } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(isDone ? Color.green : canComplete ? Color.accentColor : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .disabled(!isDone && !canComplete)
        .accessibilityLabel(isDone ? "Set \(displayNumber) done" : "Mark set \(displayNumber) done")
        .accessibilityHint(isDone ? "Double tap to un-mark" : !canComplete ? "Enter reps first" : set.isWarmup ? "Warm-up, no rest timer" : "Starts the rest timer")
    }

    private func toggleDone() {
        if isDone {
            set.completedAt = nil
        } else {
            set.completedAt = .now
            onComplete()
        }
    }
}
