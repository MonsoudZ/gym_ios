import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var date: Date
    var templateDayName: String
    /// The program day this session came from. Rotation matches on this first and falls back to
    /// the name for sessions logged before days had ids, so renaming a day no longer resets it.
    var programDayID: UUID?
    var sleepHours: Double?
    var sorenessByMuscle: [String: Int]
    var isCompleted: Bool
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.session) var sets: [SetEntry] = []

    init(date: Date = .now, templateDayName: String, sleepHours: Double? = nil, soreness: [Muscle: Int] = [:]) {
        id = UUID()
        self.date = date
        self.templateDayName = templateDayName
        self.sleepHours = sleepHours
        sorenessByMuscle = Dictionary(uniqueKeysWithValues: soreness.map { ($0.key.rawValue, $0.value) })
        isCompleted = false
    }

    /// Copies the day's check-in onto the session, so history keeps what the lifter reported.
    convenience init(date: Date = .now, templateDayName: String, readiness entry: ReadinessEntry?) {
        var soreness: [Muscle: Int] = [:]
        for (key, value) in entry?.sorenessByMuscle ?? [:] {
            if let muscle = Muscle(rawValue: key) { soreness[muscle] = value }
        }
        self.init(date: date, templateDayName: templateDayName, sleepHours: entry?.sleepHours, soreness: soreness)
    }

    var readiness: Readiness {
        var soreness: [Muscle: Int] = [:]
        for (key, value) in sorenessByMuscle {
            if let muscle = Muscle(rawValue: key) { soreness[muscle] = value }
        }
        return Readiness(sleepHours: sleepHours, soreness: soreness)
    }

    /// Exercises in this session in the order they were planned.
    var orderedExercises: [Exercise] {
        var seen: Set<PersistentIdentifier> = []
        var result: [Exercise] = []
        for set in sets.sorted(by: { ($0.exerciseOrder, $0.setNumber) < ($1.exerciseOrder, $1.setNumber) }) {
            guard let exercise = set.exercise, !seen.contains(exercise.persistentModelID) else { continue }
            seen.insert(exercise.persistentModelID)
            result.append(exercise)
        }
        return result
    }

    /// Sets with reps entered. Finishing drops the others, so the Finish dialog quotes this.
    var loggedSetCount: Int { sets.filter { $0.reps > 0 }.count }

    func sets(for exercise: Exercise) -> [SetEntry] {
        sets.filter { $0.exercise?.persistentModelID == exercise.persistentModelID }
            .sorted { $0.setNumber < $1.setNumber }
    }
}

@Model
final class SetEntry {
    var exerciseOrder: Int
    var setNumber: Int
    var weight: Double   // kg
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
    var completedAt: Date?
    var session: WorkoutSession?
    var exercise: Exercise?

    init(exerciseOrder: Int, setNumber: Int, weight: Double, reps: Int = 0, rpe: Double? = nil, isWarmup: Bool = false) {
        self.exerciseOrder = exerciseOrder
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.rpe = rpe
        self.isWarmup = isWarmup
    }
}
