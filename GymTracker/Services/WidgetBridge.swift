import Foundation
import SwiftData
import WidgetKit

/// Keeps the widgets' snapshot in step with the database. Every save on the main context
/// schedules a refresh, coalesced so a burst of saves (starting a workout inserts a set per
/// row) writes the file once.
enum WidgetBridge {
    private static var pending: Task<Void, Never>?

    /// Refreshes after each save of the container's main context.
    static func observe(_ container: ModelContainer) {
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: container.mainContext, queue: .main) { _ in
            MainActor.assumeIsolated { scheduleRefresh(context: container.mainContext) }
        }
    }

    static func scheduleRefresh(context: ModelContext) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            refresh(context: context)
        }
    }

    /// Recomputes the plan and today's intake the way the Today tab does and hands them to
    /// the widgets. Safe to call often.
    static func refresh(context: ModelContext, now: Date = .now) {
        let snapshot = WidgetSnapshot(lift: liftSnapshot(context: context, now: now),
                                      nutrition: nutritionSnapshot(context: context, now: now),
                                      updatedAt: now)
        guard snapshot.lift != WidgetStore.load()?.lift || snapshot.nutrition != WidgetStore.load()?.nutrition else { return }
        do {
            try WidgetStore.save(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Without the app group the widgets simply show their placeholder.
        }
    }

    static func liftSnapshot(context: ModelContext, now: Date) -> LiftSnapshot? {
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first,
              let programs = try? context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt)])),
              let program = settings.activeProgram(in: programs),
              let exercises = try? context.fetch(FetchDescriptor<Exercise>(sortBy: [SortDescriptor(\.name)])),
              let sessions = try? context.fetch(FetchDescriptor<WorkoutSession>()) else { return nil }
        let metric = settings.usesMetric

        if let inProgress = sessions.first(where: { !$0.isCompleted }) {
            let lines = inProgress.orderedExercises.map { exercise in
                let sets = inProgress.sets(for: exercise).filter { !$0.isWarmup }
                let done = sets.filter { $0.completedAt != nil }.count
                let weight = sets.first.map { Units.weight($0.weight, metric: metric) } ?? ""
                return LiftSnapshot.Line(name: exercise.name,
                                         detail: "\(weight) · \(done)/\(sets.count) sets",
                                         badge: done == sets.count && !sets.isEmpty ? "Done" : nil)
            }
            let next = lines.first { $0.badge == nil }
            return LiftSnapshot(dayName: inProgress.templateDayName, lines: lines, headline: next,
                                headlineReason: next.map { _ in "Workout in progress. Tap to continue." } ?? "Every set logged. Tap Finish.",
                                inProgress: true)
        }

        let completed = sessions.filter(\.isCompleted)
        guard let day = PlanService.nextDay(in: program, completedSessions: completed) else { return nil }
        let readinessEntries = (try? context.fetch(FetchDescriptor<ReadinessEntry>())) ?? []
        let todayEntry = ReadinessEntry.entry(for: now, in: readinessEntries)
        let readiness = todayEntry.map(\.readiness).flatMap { $0.hasAnyInput ? $0 : nil }
        let plan = PlanService.plan(day: day, exercises: exercises, completedSessions: completed, readiness: readiness, metric: metric)
        let lines = plan.map { line(for: $0, metric: metric) }
        let headline = plan.first { $0.prescription.stallAction != nil } ?? plan.first { $0.prescription.isNotable } ?? plan.first
        return LiftSnapshot(dayName: day.name, lines: lines,
                            headline: headline.map { line(for: $0, metric: metric) },
                            headlineReason: headline?.prescription.reason,
                            inProgress: false)
    }

    private static func line(for item: PlannedExercise, metric: Bool) -> LiftSnapshot.Line {
        let p = item.prescription
        let sets = "\(p.setCount) × \(p.repRangeLow)–\(p.repRangeHigh)"
        let detail = p.needsStartingWeight ? "\(sets) · choose a weight" : "\(Units.weight(p.weight, metric: metric)) · \(sets)"
        let badge: String? = if let action = p.stallAction { action.label }
            else if p.lastVerdict == .progressed { "Progressed" }
            else if p.readinessAdjusted { "Lighter" }
            else { nil }
        return LiftSnapshot.Line(name: item.exercise.name, detail: detail, badge: badge)
    }

    static func nutritionSnapshot(context: ModelContext, now: Date) -> NutritionWidgetSnapshot? {
        guard let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first,
              let weights = try? context.fetch(FetchDescriptor<BodyweightEntry>(sortBy: [SortDescriptor(\.date)])),
              let intake = try? context.fetch(FetchDescriptor<IntakeEntry>()) else { return nil }
        let snap = NutritionService.snapshot(settings: settings, weights: weights, intake: intake, asOf: now)
        return NutritionWidgetSnapshot(dayStart: Calendar.current.startOfDay(for: now),
                                       eatenKcal: snap.eatenToday.kcal, targetKcal: snap.targetKcal,
                                       eatenProtein: snap.eatenToday.protein, targetProtein: snap.macros.protein,
                                       isProvisional: snap.isProvisional)
    }
}
