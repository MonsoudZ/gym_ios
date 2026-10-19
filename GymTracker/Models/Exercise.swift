import Foundation
import SwiftData

@Model
final class Exercise {
    @Attribute(.unique) var name: String
    var muscles: [MuscleWeight]
    var repRangeLow: Int
    var repRangeHigh: Int
    var increment: Double   // kg
    var setCount: Int
    var rpeCap: Double
    var startingWeight: Double?
    @Relationship(inverse: \SetEntry.exercise) var sets: [SetEntry] = []

    init(spec: ExerciseSpec) {
        name = spec.name
        muscles = spec.muscles
        repRangeLow = spec.repRangeLow
        repRangeHigh = spec.repRangeHigh
        increment = spec.increment
        setCount = spec.setCount
        rpeCap = 9
        startingWeight = nil
    }

    var config: ExerciseConfig {
        ExerciseConfig(repRangeLow: repRangeLow, repRangeHigh: repRangeHigh, increment: increment,
                       setCount: setCount, rpeCap: rpeCap, startingWeight: startingWeight)
    }

    var primaryMuscle: Muscle? {
        muscles.max(by: { $0.weight < $1.weight })?.muscle
    }

    /// Completed sessions that include this exercise, oldest first, as engine input.
    func sessionResults() -> [SessionResult] {
        var bySession: [UUID: (session: WorkoutSession, sets: [SetEntry])] = [:]
        for set in sets {
            guard let session = set.session, session.isCompleted else { continue }
            bySession[session.id, default: (session, [])].sets.append(set)
        }
        return bySession.values
            .sorted { $0.session.date < $1.session.date }
            .map { entry in
                let logged = entry.sets
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, isWarmup: $0.isWarmup) }
                return SessionResult(date: entry.session.date, sets: logged,
                                     readinessWasLow: entry.session.readiness.isLow(for: muscles))
            }
    }
}
