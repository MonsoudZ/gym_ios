import Foundation
import SwiftData

@Model
final class Exercise {
    /// Stable identity for program days and plans; the name is editable.
    var id: UUID = UUID()
    @Attribute(.unique) var name: String
    /// The library entry this exercise was seeded from, if any. Survives renaming, so the
    /// seeder does not recreate a renamed library lift and unit changes still find its plate step.
    var librarySpecName: String?
    /// The lifter's own note: setup, cues, what hurt last time. Shown in the workout and the guide.
    var notes: String?
    var muscles: [MuscleWeight]
    var repRangeLow: Int
    var repRangeHigh: Int
    var increment: Double   // kg
    var setCount: Int
    var rpeCap: Double
    var startingWeight: Double?
    /// Rest between working sets, started when a set is ticked done (RestRule).
    var restSeconds: Int = RestRule.lightSeconds
    @Relationship(inverse: \SetEntry.exercise) var sets: [SetEntry] = []

    init(spec: ExerciseSpec) {
        id = UUID()
        name = spec.name
        librarySpecName = spec.name
        muscles = spec.muscles
        repRangeLow = spec.repRangeLow
        repRangeHigh = spec.repRangeHigh
        increment = spec.increment
        setCount = spec.setCount
        rpeCap = 9
        startingWeight = nil
        restSeconds = RestRule.defaultSeconds(repRangeHigh: spec.repRangeHigh)
    }

    /// A blank custom exercise. Defaults: 3 sets in the style's range (8–12 balanced, 4–6
    /// heavy), one small plate step.
    init(name: String, metric: Bool, repStyle: RepStyle = .balanced) {
        id = UUID()
        self.name = name
        muscles = []
        repRangeLow = repStyle.customDefault.low
        repRangeHigh = repStyle.customDefault.high
        increment = ExerciseLibrary.increment(forKg: 2.5, metric: metric)
        setCount = 3
        rpeCap = 9
        startingWeight = nil
        restSeconds = RestRule.defaultSeconds(repRangeHigh: repRangeHigh)
    }

    /// The library entry behind this exercise: the one it was seeded from, or, for exercises
    /// made before that was recorded, the one sharing its name.
    var librarySpec: ExerciseSpec? { ExerciseLibrary.spec(librarySpecName ?? name) }
    var isFromLibrary: Bool { librarySpec != nil }

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
        for set in completedSets() {
            guard let session = set.session else { continue }
            bySession[session.id, default: (session, [])].sets.append(set)
        }
        return bySession.values
            .sorted { $0.session.date < $1.session.date }
            .map { entry in
                let logged = entry.sets
                    .sorted { $0.setNumber < $1.setNumber }
                    .map { LoggedSet(weight: $0.weight, reps: $0.reps, rpe: $0.rpe, isWarmup: $0.isWarmup) }
                return SessionResult(date: entry.session.date, sets: logged,
                                     readinessWasLow: entry.session.readiness.isLow(for: muscles),
                                     sessionID: entry.session.id,
                                     missReason: entry.session.missReason(for: self))
            }
    }

    /// This exercise's sets in completed sessions, fetched by predicate so the store does the
    /// filtering instead of every set's session being faulted in. Falls back to the relationship
    /// when the exercise is not in a context yet.
    private func completedSets() -> [SetEntry] {
        guard let modelContext else {
            return sets.filter { $0.session?.isCompleted == true }
        }
        let exerciseID = id
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exercise?.id == exerciseID && $0.session?.isCompleted == true })
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            return sets.filter { $0.session?.isCompleted == true }
        }
    }
}
