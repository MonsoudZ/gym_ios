import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var settingsList: [UserSettings]
    @Environment(\.switchTab) private var switchTab

    private var completed: [WorkoutSession] { sessions.filter(\.isCompleted) }
    private var metric: Bool { settingsList.first?.usesMetric ?? true }
    /// `sessions` is sorted newest first, so this is the most recent completed one.
    private var lastSession: WorkoutSession? { sessions.first(where: \.isCompleted) }

    var body: some View {
        NavigationStack {
            List {
                if let lastSession {
                    Section {
                        NavigationLink { SessionEditorView(session: lastSession) } label: {
                            LastSessionSummary(session: lastSession, metric: metric)
                        }
                    } header: {
                        Text("Last session")
                    } footer: {
                        Text("Tap to correct a set or delete the workout.")
                    }
                    Section {
                        VolumeChart(volume: PlanService.weeklyVolume(completedSessions: completed))
                    } header: {
                        Text("Hard sets per muscle, last 7 days")
                    } footer: {
                        Text("Dashed lines mark the evidence-based bands: 10 sets minimum, 20 where returns flatten.")
                    }
                    Section("Lifts") {
                        let trained = exercises.filter { $0.sets.contains { $0.session?.isCompleted == true } }
                        ForEach(trained, id: \.persistentModelID) { exercise in
                            NavigationLink(value: exercise) { LiftRow(exercise: exercise, metric: metric) }
                        }
                    }
                } else {
                    EmptyState("No workouts yet", systemImage: "figure.strengthtraining.traditional",
                               description: "Finish a workout and it will show here, with your lifts and weekly volume.") {
                        Button("Start workout") { switchTab(.today) }
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: Exercise.self) { ExerciseProgressView(exercise: $0) }
        }
    }
}

/// The most recent workout at a glance: when, which day, and each lift's top set with its verdict.
struct LastSessionSummary: View {
    var session: WorkoutSession
    var metric: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text(session.templateDayName).font(.headline)
                Text(session.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text(session.templateDayName).font(.headline)
                    Spacer()
                    Text(session.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            ForEach(session.orderedExercises, id: \.persistentModelID) { exercise in
                let sets = session.sets(for: exercise).map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, isWarmup: $0.isWarmup) }
                let verdict = ProgressionEngine.verdict(for: sets, config: exercise.config)
                let topSet = ProgressionEngine.topWorkingWeight(sets).map {
                    "\(Units.weight($0, metric: metric)) × \(sets.filter { !$0.isWarmup }.map { "\($0.reps)" }.joined(separator: ", "))"
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        // Three columns do not fit at these sizes; stack them.
                        VStack(alignment: .leading, spacing: 2) {
                            Text(exercise.name)
                            if let topSet { Text(topSet).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                            VerdictBadge(verdict: verdict, font: .subheadline)
                        }
                        .padding(.vertical, 4)
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            Text(exercise.name)
                            Spacer()
                            if let topSet { Text(topSet).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
                            VerdictBadge(verdict: verdict)
                                .frame(width: 112, alignment: .trailing)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LiftRow: View {
    var exercise: Exercise
    var metric: Bool

    var body: some View {
        let points = ExerciseProgressView.points(for: exercise)
        HStack {
            Text(exercise.name)
            Spacer()
            if let latest = points.last {
                VStack(alignment: .trailing) {
                    Text(Units.weight(latest.value, metric: metric)).font(.body.monospacedDigit())
                    Text("est. 1RM").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct VolumeChart: View {
    var volume: [Muscle: Double]

    private var rows: [(muscle: Muscle, sets: Double)] {
        Muscle.allCases.compactMap { m in
            guard let v = volume[m], v > 0 else { return nil }
            return (m, v)
        }
    }

    var body: some View {
        if rows.isEmpty {
            Text("No completed sessions in the last 7 days.").foregroundStyle(.secondary)
        } else {
            Chart {
                ForEach(rows, id: \.muscle) { row in
                    BarMark(x: .value("Sets", row.sets), y: .value("Muscle", row.muscle.displayName))
                        .foregroundStyle(color(for: VolumeTracker.band(row.sets)))
                        .annotation(position: .trailing) {
                            let band = VolumeTracker.band(row.sets)
                            Text(band.shortLabel.isEmpty ? Units.number(row.sets) : "\(Units.number(row.sets)) · \(band.shortLabel)")
                                .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                }
                RuleMark(x: .value("Minimum", VolumeTracker.minimumWeeklySets))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(x: .value("High", VolumeTracker.highWeeklySets))
                    .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
            }
            .chartXScale(domain: 0...max(24, (rows.map(\.sets).max() ?? 0) + 4))
            .frame(height: CGFloat(rows.count) * 26 + 30)
        }
    }

    private func color(for band: VolumeBand) -> Color {
        switch band {
        case .low: .orange
        case .ok: .accentColor
        case .high: .yellow
        }
    }
}

struct ExerciseProgressView: View {
    var exercise: Exercise
    @Query private var settingsList: [UserSettings]
    @Query(filter: #Predicate<WorkoutSession> { $0.isCompleted }) private var completedSessions: [WorkoutSession]
    @Query(sort: \BodyweightEntry.date) private var weights: [BodyweightEntry]
    @State private var chartMode: ChartMode = .absolute
    @State private var showingGuide = false

    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    enum ChartMode: String, CaseIterable, Identifiable {
        case absolute, relative
        var id: Self { self }
    }

    static func points(for exercise: Exercise) -> [DatedValue] {
        exercise.sessionResults().compactMap { result in
            OneRepMax.best(from: result.sets).map { DatedValue(date: result.date, value: $0) }
        }
    }

    var body: some View {
        let history = exercise.sessionResults()
        let points = Self.points(for: exercise)
        let annotations = ProgressionEngine.annotate(history: history, config: exercise.config)
        let deloadDates = Set(annotations.filter { $0.deload != nil }.map(\.date))
        // e1RM ÷ trend bodyweight on each session's date; empty until a weight has been logged.
        let trend = NutritionEngine.trend(weights.map { DatedValue(date: $0.date, value: $0.kg) })
        let relative = RelativeStrength.series(e1RM: points, trend: trend)
        let showRelative = chartMode == .relative && relative.count >= 2
        let plotted = showRelative ? relative : points
        List {
            Section {
                if let latest = points.last {
                    latestRow(e1RM: latest, relative: relative.last(where: { $0.date == latest.date }))
                }
                if relative.count >= 2 {
                    Picker("Chart", selection: $chartMode) {
                        Text(metric ? "kg" : "lb").tag(ChartMode.absolute)
                        Text("× bodyweight").tag(ChartMode.relative)
                    }
                    .pickerStyle(.segmented)
                    .listRowSeparator(.hidden)
                }
                if plotted.count >= 2 {
                    Chart {
                        ForEach(plotted, id: \.date) { p in
                            LineMark(x: .value("Date", p.date), y: .value(yLabel, plot(p.value, relative: showRelative)))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", p.date), y: .value(yLabel, plot(p.value, relative: showRelative)))
                        }
                        // Deloads get a marker so a dip reads as a decision, not a bad day.
                        ForEach(plotted.filter { deloadDates.contains($0.date) }, id: \.date) { p in
                            PointMark(x: .value("Date", p.date), y: .value(yLabel, plot(p.value, relative: showRelative)))
                                .symbol(.diamond).symbolSize(120).foregroundStyle(.orange)
                                .annotation(position: .bottom, spacing: 4) {
                                    Text("Deload").font(.caption2.weight(.medium)).foregroundStyle(.orange)
                                }
                        }
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .accessibilityLabel(showRelative ? "Estimated 1RM as a multiple of bodyweight" : "Estimated 1RM")
                } else {
                    Text("Two or more sessions with sets of 10 reps or fewer are needed for a trend.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Estimated 1RM")
            } footer: {
                Text(showRelative
                     ? "Epley e1RM divided by your trend bodyweight on the day. Rising while you cut means strength is being kept."
                     : "Epley formula from your best set of 10 reps or fewer each session.")
            }

            Section("Change") {
                changeRow("4 weeks", points: points, relative: relative, days: 28)
                changeRow("12 weeks", points: points, relative: relative, days: 84)
            }

            Section {
                ForEach(Array(zip(history, annotations)).reversed(), id: \.0.date) { result, note in
                    sessionLink(for: result) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(result.date, format: .dateTime.day().month())
                                Spacer()
                                VerdictBadge(verdict: note.verdict)
                            }
                            Text(result.sets.filter { !$0.isWarmup }
                                .map { "\(Units.weight($0.weight, metric: metric)) × \($0.reps)\($0.rpe.map { " @\(Units.number($0))" } ?? "")" }
                                .joined(separator: "  ·  "))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if let deload = note.deload {
                                Label(deloadText(deload), systemImage: StallAction.deload.systemImage)
                                    .font(.caption.weight(.medium)).foregroundStyle(.orange)
                            } else if note.stallStreak >= ProgressionEngine.stallThreshold {
                                Label("Stalled \(note.stallStreak) sessions", systemImage: "exclamationmark.triangle")
                                    .font(.caption.weight(.medium)).foregroundStyle(.orange)
                            }
                        }
                    }
                }
            } header: {
                Text("Sessions")
            } footer: {
                Text("Tap a session to correct a mistyped set or delete it. The verdicts and the next prescription update.")
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Guide", systemImage: "info.circle") { showingGuide = true }
            }
        }
        .sheet(isPresented: $showingGuide) { ExerciseGuideSheet(exercise: exercise) }
    }

    private func display(_ kg: Double) -> Double { metric ? kg : kg * Units.lbPerKg }

    private var yLabel: String { chartMode == .relative ? "× bodyweight" : "e1RM" }

    /// The ratio is unitless; only the raw e1RM needs converting for lb users.
    private func plot(_ value: Double, relative: Bool) -> Double { relative ? value : display(value) }

    /// Latest e1RM with its bodyweight multiple beside it, or a hint when no weight is logged yet.
    private func latestRow(e1RM: DatedValue, relative: DatedValue?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Latest")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(Units.weight(e1RM.value, metric: metric)).bold().monospacedDigit()
                if let relative {
                    Text(RelativeStrength.label(relative.value))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                } else {
                    Text("Log a bodyweight to see this per kg")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// A history row opens its session for editing. The editor is a direct destination, not a
    /// value, because Today also shows this screen and routes `WorkoutSession` values to the live workout.
    @ViewBuilder private func sessionLink<Content: View>(for result: SessionResult, @ViewBuilder content: () -> Content) -> some View {
        if let session = completedSessions.first(where: { $0.id == result.sessionID }) {
            NavigationLink { SessionEditorView(session: session) } label: { content() }
        } else {
            content()
        }
    }

    private func deloadText(_ deload: DeloadMark) -> String {
        let drop = "Deloaded \(Units.number(deload.percentDrop, maxFraction: 0))%: \(Units.weight(deload.fromWeight, metric: metric)) → \(Units.weight(deload.toWeight, metric: metric))"
        return deload.stalledSessionsBefore > 0
            ? "\(drop), after stalling \(deload.stalledSessionsBefore) session\(deload.stalledSessionsBefore == 1 ? "" : "s")"
            : drop
    }

    @ViewBuilder private func changeRow(_ label: String, points: [DatedValue], relative: [DatedValue], days: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
            Spacer()
            if let latest = points.last,
               let earlier = NutritionEngine.value(in: points, atOrBefore: Calendar.current.date(byAdding: .day, value: -days, to: latest.date)!) {
                let delta = latest.value - earlier.value
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(delta >= 0 ? "+" : "")\(Units.weight(delta, metric: metric))")
                        .bold().monospacedDigit().foregroundStyle(delta >= 0 ? .green : .red)
                    // Same window on the ratio, so a flat lift on a falling bodyweight shows as a gain.
                    if let latestRel = relative.last,
                       let earlierRel = NutritionEngine.value(in: relative, atOrBefore: Calendar.current.date(byAdding: .day, value: -days, to: latestRel.date)!) {
                        let relDelta = latestRel.value - earlierRel.value
                        Text("\(relDelta >= 0 ? "+" : "")\(Units.number(relDelta, maxFraction: 2))× bodyweight")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(relDelta >= 0 ? .green : .red)
                    }
                }
            } else {
                Text("Not enough history yet").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
