import Foundation
import SwiftData

struct PlannedExercise: Identifiable {
    var exercise: Exercise
    var prescription: Prescription
    var id: UUID { exercise.id }
}

/// One line about a muscle's weekly volume, shown on the Today tab.
nonisolated struct VolumeNote: Hashable, Sendable {
    var muscle: Muscle
    var sets: Double
    var band: VolumeBand
    var text: String
}

enum PlanService {
    /// How far back the stall check looks when averaging weekly volume (DESIGN.md §2.5).
    static let volumeWindowDays = 14

    /// The program day after the most recently completed one, or the first day.
    static func nextDay(in program: Program, completedSessions: [WorkoutSession]) -> ProgramDay? {
        let days = program.orderedDays
        guard !days.isEmpty else { return nil }
        guard let last = completedSessions.max(by: { $0.date < $1.date }) else { return days[0] }
        let byID = last.programDayID.flatMap { id in days.firstIndex { $0.id == id } }
        guard let index = byID ?? days.firstIndex(where: { $0.name == last.templateDayName }) else { return days[0] }
        return days[(index + 1) % days.count]
    }

    /// The day to plan for today: the one the lifter picked, if it is still in the program,
    /// otherwise the next in rotation. Picking a day does not edit the rotation; after it is
    /// completed, `nextDay` carries on from it.
    static func day(in program: Program, chosenID: UUID?, completedSessions: [WorkoutSession]) -> ProgramDay? {
        if let chosenID, let chosen = program.orderedDays.first(where: { $0.id == chosenID }) { return chosen }
        return nextDay(in: program, completedSessions: completedSessions)
    }

    /// Hard sets per muscle over the 7 days ending at `asOf`. Shown on the Progress tab.
    static func weeklyVolume(completedSessions: [WorkoutSession], asOf: Date = .now) -> [Muscle: Double] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: asOf)!
        return VolumeTracker.weeklyVolume(hardSets(in: completedSessions, after: weekAgo, through: asOf))
    }

    /// Average hard sets per muscle per week over the `windowDays` ending at `asOf`.
    ///
    /// A single rolling week depends on the day of the week it is read: on a Monday it drops
    /// last Monday's session and reports a full-volume muscle as under minimum. Averaging over
    /// two weeks smooths that out. With less history than the window, the sets are spread over
    /// the span actually trained (never less than one week), so a lifter in their first days
    /// is not told their volume is low.
    static func averageWeeklyVolume(completedSessions: [WorkoutSession], asOf: Date = .now,
                                    windowDays: Int = volumeWindowDays) -> [Muscle: Double] {
        let calendar = Calendar.current
        let windowStart = calendar.date(byAdding: .day, value: -windowDays, to: asOf)!
        let inWindow = completedSessions.filter { $0.date > windowStart && $0.date <= asOf }
        guard let oldest = inWindow.map(\.date).min() else { return [:] }
        let totals = VolumeTracker.weeklyVolume(hardSets(in: inWindow, after: windowStart, through: asOf))
        let historyFillsWindow = completedSessions.contains { $0.date <= windowStart }
        let spanDays = historyFillsWindow
            ? Double(windowDays)
            : min(Double(windowDays), max(7, asOf.timeIntervalSince(oldest) / 86_400))
        return totals.mapValues { $0 / (spanDays / 7) }
    }

    /// Hard sets per muscle that `exercises` will add today if every planned set is done.
    static func plannedVolume(for exercises: [Exercise]) -> [Muscle: Double] {
        let sets = exercises.flatMap { exercise in
            Array(repeating: VolumeSet(muscles: exercise.muscles), count: exercise.setCount)
        }
        return VolumeTracker.weeklyVolume(sets)
    }

    /// The volume the stall check sees (DESIGN.md §2.3 step 1): the two-week average alone.
    /// That average already holds the last instance of today's day, so adding today's planned
    /// sets on top counted the day twice and the "under 10, add a set" branch almost never ran.
    static func volumeForStallCheck(dayExercises: [Exercise], completedSessions: [WorkoutSession], asOf: Date = .now) -> [Muscle: Double] {
        averageWeeklyVolume(completedSessions: completedSessions, asOf: asOf)
    }

    static func prescription(for exercise: Exercise, readiness: Readiness?, weeklyVolume: [Muscle: Double], metric: Bool) -> Prescription {
        // A muscle with no sets in the window is at zero, not unknown: the stall check's first
        // step (under 10 sets, add a set) must see it rather than skip straight to a deload.
        let primaryVolume = exercise.primaryMuscle.map { weeklyVolume[$0] ?? 0 }
        return ProgressionEngine.prescription(history: exercise.sessionResults(),
                                              config: exercise.config,
                                              muscles: exercise.muscles,
                                              readiness: readiness,
                                              weeklySetsForPrimaryMuscle: primaryVolume,
                                              formatWeight: { Units.weight($0, metric: metric) })
    }

    static func plan(day: ProgramDay, exercises: [Exercise], completedSessions: [WorkoutSession], readiness: Readiness?, metric: Bool) -> [PlannedExercise] {
        let dayExercises = day.exercises(from: exercises)
        let volume = volumeForStallCheck(dayExercises: dayExercises, completedSessions: completedSessions)
        return dayExercises.map { exercise in
            PlannedExercise(exercise: exercise,
                            prescription: prescription(for: exercise, readiness: readiness, weeklyVolume: volume, metric: metric))
        }
    }

    /// What the week's volume says about the muscles today's plan trains (DESIGN.md §2.5): under
    /// the minimum, suggest a set or two; over the high band while a lift for it is stalling,
    /// suggest dropping two. Muscles in range say nothing.
    static func volumeNotes(plan: [PlannedExercise], volume: [Muscle: Double]) -> [VolumeNote] {
        var muscles: [Muscle] = []
        for item in plan {
            for mw in item.exercise.muscles where mw.weight >= 1 && !muscles.contains(mw.muscle) { muscles.append(mw.muscle) }
        }
        return muscles.compactMap { muscle in
            let sets = volume[muscle] ?? 0
            switch VolumeTracker.band(sets) {
            case .low:
                let lift = plan.first { $0.exercise.primaryMuscle == muscle }?.exercise.name ?? "a \(muscle.displayName.lowercased()) lift"
                return VolumeNote(muscle: muscle, sets: sets, band: .low,
                                  text: "\(muscle.displayName): \(Units.number(sets)) sets/week, under the 10-set minimum. Add a set or two to \(lift).")
            case .high:
                let stalling = plan.filter { $0.exercise.primaryMuscle == muscle && $0.prescription.stallStreak > 0 }
                guard let lift = stalling.first else {
                    return VolumeNote(muscle: muscle, sets: sets, band: .high,
                                      text: "\(muscle.displayName): \(Units.number(sets)) sets/week, above 20. Fine while it keeps progressing.")
                }
                return VolumeNote(muscle: muscle, sets: sets, band: .high,
                                  text: "\(muscle.displayName): \(Units.number(sets)) sets/week, above 20, and \(lift.exercise.name) is stalling. Drop two sets.")
            case .ok:
                return nil
            }
        }
    }

    private static func hardSets(in sessions: [WorkoutSession], after start: Date, through end: Date) -> [VolumeSet] {
        var sets: [VolumeSet] = []
        for session in sessions where session.date > start && session.date <= end {
            for set in session.sets where set.reps > 0 {
                guard let exercise = set.exercise else { continue }
                sets.append(VolumeSet(muscles: exercise.muscles, isWarmup: set.isWarmup))
            }
        }
        return sets
    }
}
