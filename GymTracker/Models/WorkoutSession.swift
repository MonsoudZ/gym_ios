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
    /// The morning's Health reading as the day's check-in held it (see ReadinessEntry).
    var hrvMs: Double?
    var restingHeartRate: Double?
    var hrvBaselineMean: Double?
    var hrvBaselineSD: Double?
    var hrvBaselineDays: Int?
    var restingHeartRateBaselineMean: Double?
    var restingHeartRateBaselineSD: Double?
    var restingHeartRateBaselineDays: Int?
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
        hrvMs = entry?.hrvMs
        restingHeartRate = entry?.restingHeartRate
        hrvBaselineMean = entry?.hrvBaselineMean
        hrvBaselineSD = entry?.hrvBaselineSD
        hrvBaselineDays = entry?.hrvBaselineDays
        restingHeartRateBaselineMean = entry?.restingHeartRateBaselineMean
        restingHeartRateBaselineSD = entry?.restingHeartRateBaselineSD
        restingHeartRateBaselineDays = entry?.restingHeartRateBaselineDays
    }

    var heart: HeartReadiness? {
        guard hrvMs != nil || restingHeartRate != nil else { return nil }
        func baseline(_ mean: Double?, _ sd: Double?, _ days: Int?) -> HeartBaseline? {
            guard let mean, let sd, let days else { return nil }
            return HeartBaseline(mean: mean, standardDeviation: sd, days: days)
        }
        return HeartReadiness(hrvMs: hrvMs, restingHeartRate: restingHeartRate,
                              hrvBaseline: baseline(hrvBaselineMean, hrvBaselineSD, hrvBaselineDays),
                              restingHeartRateBaseline: baseline(restingHeartRateBaselineMean, restingHeartRateBaselineSD,
                                                                 restingHeartRateBaselineDays))
    }

    var readiness: Readiness {
        var soreness: [Muscle: Int] = [:]
        for (key, value) in sorenessByMuscle {
            if let muscle = Muscle(rawValue: key) { soreness[muscle] = value }
        }
        return Readiness(sleepHours: sleepHours, soreness: soreness, heart: heart)
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

    private func exerciseOrder(of exercise: Exercise) -> Int {
        sets(for: exercise).first?.exerciseOrder ?? ((sets.map(\.exerciseOrder).max() ?? -1) + 1)
    }

    /// Appends one more working set to an exercise already in the session, at the last set's weight.
    @discardableResult
    func addSet(for exercise: Exercise, in context: ModelContext) -> SetEntry {
        let existing = sets(for: exercise)
        let weight = existing.last(where: { !$0.isWarmup })?.weight ?? existing.last?.weight ?? 0
        let set = SetEntry(exerciseOrder: exerciseOrder(of: exercise),
                           setNumber: (existing.map(\.setNumber).max() ?? -1) + 1, weight: weight)
        set.exercise = exercise
        set.session = self
        context.insert(set)
        sets.append(set)
        return set
    }

    /// Inserts ramp sets before the exercise's working sets, renumbering so they sort first.
    @discardableResult
    func addWarmups(for exercise: Exercise, in context: ModelContext) -> [SetEntry] {
        let existing = sets(for: exercise)
        guard let working = existing.first(where: { !$0.isWarmup }) else { return [] }
        let ramp = WarmupRule.ramp(workingWeight: working.weight, increment: exercise.increment)
        guard !ramp.isEmpty else { return [] }
        for set in existing { set.setNumber += ramp.count }
        let order = exerciseOrder(of: exercise)
        return ramp.enumerated().map { index, step in
            let set = SetEntry(exerciseOrder: order, setNumber: index, weight: step.weight, reps: step.reps, isWarmup: true)
            set.exercise = exercise
            set.session = self
            context.insert(set)
            sets.append(set)
            return set
        }
    }

    /// Drops an exercise's sets that have no reps. Sets already logged stay, so skipping
    /// halfway keeps what was done. Returns whether any logged sets remain.
    @discardableResult
    func skip(_ exercise: Exercise, in context: ModelContext) -> Bool {
        for set in sets(for: exercise) where set.reps <= 0 { context.delete(set) }
        return sets.contains { $0.exercise?.persistentModelID == exercise.persistentModelID && $0.reps > 0 }
    }

    /// Replaces `old`'s unlogged sets with the same number of working sets of `replacement` at
    /// `weight`. The replacement takes `old`'s place in the order; the program is untouched.
    func swap(_ old: Exercise, for replacement: Exercise, weight: Double, in context: ModelContext) {
        guard old.persistentModelID != replacement.persistentModelID, sets(for: replacement).isEmpty else { return }
        let existing = sets(for: old)
        let order = exerciseOrder(of: old)
        let count = max(1, existing.filter { !$0.isWarmup && $0.reps <= 0 }.count)
        // Numbered after any sets of `old` that stay, so the two never interleave.
        let first = (existing.map(\.setNumber).max() ?? -1) + 1
        for set in existing where set.reps <= 0 { context.delete(set) }
        for number in 0..<count {
            let set = SetEntry(exerciseOrder: order, setNumber: first + number, weight: weight)
            set.exercise = replacement
            set.session = self
            context.insert(set)
            sets.append(set)
        }
    }

    /// Adds an exercise that was not in the plan, with its usual set count at `weight`.
    func addExercise(_ exercise: Exercise, weight: Double, in context: ModelContext) {
        guard sets(for: exercise).isEmpty else { return }
        let order = exerciseOrder(of: exercise)
        for number in 0..<max(1, exercise.setCount) {
            let set = SetEntry(exerciseOrder: order, setNumber: number, weight: weight)
            set.exercise = exercise
            set.session = self
            context.insert(set)
            sets.append(set)
        }
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
