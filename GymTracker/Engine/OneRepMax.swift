import Foundation

/// Epley estimate: weight × (1 + reps / 30).
/// Only trusted for sets of 10 reps or fewer (LeSuer et al. 1997).
nonisolated enum OneRepMax {
    static let maxTrustedReps = 10

    static func epley(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= maxTrustedReps else { return nil }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30)
    }

    /// Best estimate from the working sets of one session, or nil if no set qualifies.
    static func best(from sets: [LoggedSet]) -> Double? {
        sets.filter { !$0.isWarmup }
            .compactMap { epley(weight: $0.weight, reps: $0.reps) }
            .max()
    }
}
