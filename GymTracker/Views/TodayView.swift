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

    @State private var sleepText = ""
    @State private var soreMuscles: Set<Muscle> = []
    @State private var activeSession: WorkoutSession?

    private var settings: UserSettings? { settingsList.first }
    private var completed: [WorkoutSession] { sessions.filter(\.isCompleted) }
    private var inProgress: WorkoutSession? { sessions.first { !$0.isCompleted } }

    private var activeProgram: Program? { settings?.activeProgram(in: programs) }

    private var day: TemplateDay? {
        guard let activeProgram else { return nil }
        return PlanService.nextDay(template: activeProgram.asTemplate, completedSessions: completed)
    }

    private var readiness: Readiness? {
        let sleep = Double(sleepText.replacingOccurrences(of: ",", with: "."))
        let soreness = Dictionary(uniqueKeysWithValues: soreMuscles.map { ($0, Readiness.sorenessThreshold) })
        let value = Readiness(sleepHours: sleep, soreness: soreness)
        return value.hasAnyInput ? value : nil
    }

    private var plan: [PlannedExercise] {
        guard let day, let settings else { return [] }
        return PlanService.plan(day: day, exercises: exercises, completedSessions: completed, readiness: readiness, metric: settings.usesMetric)
    }

    private var headline: PlannedExercise? {
        plan.first { $0.prescription.stallAction != nil } ?? plan.first { $0.prescription.isNotable } ?? plan.first
    }

    var body: some View {
        NavigationStack {
            List {
                if let inProgress {
                    Section {
                        NavigationLink(value: inProgress) {
                            Label("Continue \(inProgress.templateDayName)", systemImage: "play.fill")
                        }
                    }
                } else if day == nil {
                    Section {
                        Text("Your program has no days yet.").font(.headline)
                        Text("Add a day and some exercises, and today's plan will appear here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                } else {
                    headlineSection
                    readinessSection
                    sessionSection
                }
                nutritionSection
            }
            .navigationTitle("Today")
            .toolbar {
                if let activeProgram {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink(value: activeProgram) {
                            Label(activeProgram.name, systemImage: "list.bullet.rectangle")
                        }
                    }
                }
            }
            .navigationDestination(for: Program.self) { ProgramEditorView(program: $0) }
            .navigationDestination(for: WorkoutSession.self) { WorkoutView(session: $0) }
            .navigationDestination(item: $activeSession) { WorkoutView(session: $0) }
        }
    }

    @ViewBuilder private var headlineSection: some View {
        if let day, let headline, let settings {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.name).font(.title2.bold())
                    Text(headlineText(headline, metric: settings.usesMetric))
                        .font(.headline)
                    Text(headline.prescription.reason)
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                Button {
                    startWorkout()
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

    private var readinessSection: some View {
        Section("Readiness (optional)") {
            HStack {
                Text("Sleep last night")
                Spacer()
                TextField("hours", text: $sleepText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("h").foregroundStyle(.secondary)
            }
            if day != nil {
                let muscles = Set(plan.flatMap { $0.exercise.muscles.filter { $0.weight >= 0.5 }.map(\.muscle) })
                    .sorted { $0.displayName < $1.displayName }
                DisclosureGroup("Very sore in\(soreMuscles.isEmpty ? "" : " (\(soreMuscles.count))")") {
                    ForEach(muscles) { muscle in
                        Toggle(muscle.displayName, isOn: Binding(
                            get: { soreMuscles.contains(muscle) },
                            set: { on in if on { soreMuscles.insert(muscle) } else { soreMuscles.remove(muscle) } }
                        ))
                    }
                }
            }
        }
    }

    @ViewBuilder private var sessionSection: some View {
        if let settings {
            Section("Plan") {
                ForEach(plan) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.exercise.name).font(.body.weight(.medium))
                            Spacer()
                            if let action = item.prescription.stallAction {
                                Text(action.label).font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(.orange.opacity(0.2), in: Capsule())
                            } else if item.prescription.lastVerdict == .progressed {
                                Image(systemName: "arrow.up.circle.fill").foregroundStyle(.green)
                            }
                        }
                        Text(prescriptionLine(item.prescription, metric: settings.usesMetric))
                            .font(.subheadline)
                        Text(item.prescription.reason)
                            .font(.caption).foregroundStyle(.secondary)
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
                    Text("Target is provisional until two weeks of weight and intake are logged.")
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

    private func startWorkout() {
        guard let day else { return }
        let soreness = Dictionary(uniqueKeysWithValues: soreMuscles.map { ($0, Readiness.sorenessThreshold) })
        let session = WorkoutSession(templateDayName: day.name, sleepHours: Double(sleepText), soreness: soreness)
        context.insert(session)
        for (order, item) in plan.enumerated() {
            for number in 0..<item.prescription.setCount {
                let set = SetEntry(exerciseOrder: order, setNumber: number, weight: item.prescription.weight)
                set.exercise = item.exercise
                set.session = session
                context.insert(set)
            }
        }
        try? context.save()
        activeSession = session
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
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(eaten, target), total: max(target, 1))
        }
    }
}
