import SwiftUI
import SwiftData
import Charts

struct ProgressTabView: View {
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
    @Query private var settingsList: [UserSettings]

    private var completed: [WorkoutSession] { sessions.filter(\.isCompleted) }
    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VolumeChart(volume: PlanService.weeklyVolume(completedSessions: completed))
                } header: {
                    Text("Hard sets per muscle, last 7 days")
                } footer: {
                    Text("Dashed lines mark the evidence-based bands: 10 sets minimum, 20 where returns flatten.")
                }
                Section("Lifts") {
                    let trained = exercises.filter { $0.sets.contains { $0.session?.isCompleted == true } }
                    if trained.isEmpty {
                        Text("Finish a workout to see your lifts here.").foregroundStyle(.secondary)
                    }
                    ForEach(trained, id: \.persistentModelID) { exercise in
                        NavigationLink(value: exercise) { LiftRow(exercise: exercise, metric: metric) }
                    }
                }
            }
            .navigationTitle("Progress")
            .navigationDestination(for: Exercise.self) { ExerciseProgressView(exercise: $0) }
        }
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
                            Text(Units.number(row.sets)).font(.caption2).foregroundStyle(.secondary)
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

    private var metric: Bool { settingsList.first?.usesMetric ?? true }

    static func points(for exercise: Exercise) -> [DatedValue] {
        exercise.sessionResults().compactMap { result in
            OneRepMax.best(from: result.sets).map { DatedValue(date: result.date, value: $0) }
        }
    }

    var body: some View {
        let points = Self.points(for: exercise)
        List {
            Section {
                if points.count >= 2 {
                    Chart(points, id: \.date) { p in
                        LineMark(x: .value("Date", p.date), y: .value("e1RM", display(p.value)))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Date", p.date), y: .value("e1RM", display(p.value)))
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                } else {
                    Text("Two or more sessions with sets of 10 reps or fewer are needed for a trend.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Estimated 1RM")
            } footer: {
                Text("Epley formula from your best set of 10 reps or fewer each session.")
            }

            Section("Change") {
                changeRow("4 weeks", points: points, days: 28)
                changeRow("12 weeks", points: points, days: 84)
            }

            Section("Sessions") {
                ForEach(exercise.sessionResults().reversed(), id: \.date) { result in
                    let verdict = ProgressionEngine.verdict(for: result.sets, config: exercise.config)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(result.date, format: .dateTime.day().month())
                            Spacer()
                            Text(verdict.label).font(.caption)
                                .foregroundStyle(verdict == .progressed ? .green : verdict == .failed ? .red : .secondary)
                        }
                        Text(result.sets.filter { !$0.isWarmup }
                            .map { "\(Units.weight($0.weight, metric: metric)) × \($0.reps)\($0.rpe.map { " @\(Units.number($0))" } ?? "")" }
                            .joined(separator: "  ·  "))
                        .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func display(_ kg: Double) -> Double { metric ? kg : kg * Units.lbPerKg }

    @ViewBuilder private func changeRow(_ label: String, points: [DatedValue], days: Int) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let latest = points.last,
               let earlier = NutritionEngine.value(in: points, atOrBefore: Calendar.current.date(byAdding: .day, value: -days, to: latest.date)!) {
                let delta = latest.value - earlier.value
                Text("\(delta >= 0 ? "+" : "")\(Units.weight(delta, metric: metric))")
                    .bold().foregroundStyle(delta >= 0 ? .green : .red)
            } else {
                Text("Not enough history").foregroundStyle(.secondary)
            }
        }
    }
}
