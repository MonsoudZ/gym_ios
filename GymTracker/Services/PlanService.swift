import Foundation

struct PlannedExercise: Identifiable {
    var exercise: Exercise
    var prescription: Prescription
    var id: PersistentIdentifierBox { PersistentIdentifierBox(exercise.persistentModelID) }
}

struct PersistentIdentifierBox: Hashable {
    let id: SwiftData.PersistentIdentifier
    init(_ id: SwiftData.PersistentIdentifier) { self.id = id }
}

import SwiftData

enum PlanService {
    /// The template day after the most recently completed one.
    static func nextDay(template: ProgramTemplate, completedSessions: [WorkoutSession]) -> TemplateDay? {
        guard !template.days.isEmpty else { return nil }
        guard let last = completedSessions.max(by: { $0.date < $1.date }),
              let index = template.days.firstIndex(where: { $0.name == last.templateDayName })
        else { return template.days[0] }
        return template.days[(index + 1) % template.days.count]
    }

    /// Hard sets per muscle over the 7 days ending at `asOf`.
    static func weeklyVolume(completedSessions: [WorkoutSession], asOf: Date = .now) -> [Muscle: Double] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: asOf)!
        var sets: [VolumeSet] = []
        for session in completedSessions where session.date > weekAgo && session.date <= asOf {
            for set in session.sets where set.reps > 0 {
                guard let exercise = set.exercise else { continue }
                sets.append(VolumeSet(muscles: exercise.muscles, isWarmup: set.isWarmup))
            }
        }
        return VolumeTracker.weeklyVolume(sets)
    }

    static func prescription(for exercise: Exercise, readiness: Readiness?, weeklyVolume: [Muscle: Double], metric: Bool) -> Prescription {
        let primaryVolume = exercise.primaryMuscle.flatMap { weeklyVolume[$0] }
        return ProgressionEngine.prescription(history: exercise.sessionResults(),
                                              config: exercise.config,
                                              muscles: exercise.muscles,
                                              readiness: readiness,
                                              weeklySetsForPrimaryMuscle: primaryVolume,
                                              formatWeight: { Units.weight($0, metric: metric) })
    }

    static func plan(day: TemplateDay, exercises: [Exercise], completedSessions: [WorkoutSession], readiness: Readiness?, metric: Bool) -> [PlannedExercise] {
        let volume = weeklyVolume(completedSessions: completedSessions)
        return day.exerciseNames.compactMap { name in
            guard let exercise = exercises.first(where: { $0.name == name }) else { return nil }
            return PlannedExercise(exercise: exercise,
                                   prescription: prescription(for: exercise, readiness: readiness, weeklyVolume: volume, metric: metric))
        }
    }
}
