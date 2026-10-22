import Foundation

/// The personal records in an exercise's history, from its working sets only. Three records,
/// each the set that produced it: the best estimated 1RM, the heaviest set inside the
/// exercise's rep range, and the most reps at the heaviest weight ever lifted. Ties go to the
/// set that was done first, since that is when the record was set.
nonisolated struct PersonalRecords: Hashable, Sendable {
    nonisolated struct Record: Hashable, Sendable {
        var weight: Double   // kg
        var reps: Int
        var rpe: Double?
        var date: Date
        var sessionID: UUID?

        var e1RM: Double? { OneRepMax.epley(weight: weight, reps: reps) }

        /// "100 kg × 5 @ RPE 8 · 2 left", in the lifter's unit.
        func setLabel(metric: Bool) -> String {
            let base = "\(Units.weight(weight, metric: metric)) × \(reps)"
            return rpe.map { "\(base) @ \(Units.rpeLabel($0))" } ?? base
        }
    }

    var bestE1RM: Record?
    var bestInRepRange: Record?
    var mostRepsAtTopWeight: Record?

    var isEmpty: Bool { bestE1RM == nil && bestInRepRange == nil && mostRepsAtTopWeight == nil }

    /// `results` in any order; warm-ups and empty sets never count.
    static func compute(from results: [SessionResult], repRangeLow: Int, repRangeHigh: Int) -> PersonalRecords {
        var sets: [Record] = []
        for result in results.sorted(by: { $0.date < $1.date }) {
            for set in result.sets where !set.isWarmup && set.reps > 0 && set.weight > 0 {
                sets.append(Record(weight: set.weight, reps: set.reps, rpe: set.rpe, date: result.date, sessionID: result.sessionID))
            }
        }
        guard !sets.isEmpty else { return PersonalRecords() }

        // `sets` is oldest first, so a strict comparison keeps the earliest of a tie.
        func first(_ candidates: [Record], _ better: (Record, Record) -> Bool) -> Record? {
            candidates.reduce(nil) { best, set in
                guard let best else { return set }
                return better(set, best) ? set : best
            }
        }
        let withE1RM = sets.filter { $0.e1RM != nil }
        let bestE1RM = first(withE1RM) { $0.e1RM! > $1.e1RM! }
        let inRange = sets.filter { (repRangeLow...max(repRangeLow, repRangeHigh)).contains($0.reps) }
        let bestInRange = first(inRange) { $0.weight > $1.weight || ($0.weight == $1.weight && $0.reps > $1.reps) }
        let top = sets.map(\.weight).max()!
        let mostReps = first(sets.filter { $0.weight == top }) { $0.reps > $1.reps }
        return PersonalRecords(bestE1RM: bestE1RM, bestInRepRange: bestInRange, mostRepsAtTopWeight: mostReps)
    }

    /// The most recent sessions, newest first.
    static func recent(_ results: [SessionResult], limit: Int = 5) -> [SessionResult] {
        Array(results.sorted { $0.date > $1.date }.prefix(limit))
    }
}
