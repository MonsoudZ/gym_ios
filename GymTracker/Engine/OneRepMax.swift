import Foundation

/// Epley estimate: weight × (1 + reps / 30).
/// Only trusted for sets of 10 reps or fewer (LeSuer et al. 1997).
nonisolated enum OneRepMax {
    static let maxTrustedReps = 10

    static func epley(weight: Double, reps: Int) -> Double? {
        guard weight > 0, reps >= 1, reps <= maxTrustedReps else { return nil }
        // No special case for a single: the formula gives 1.033 × weight, and that is what the
        // spec says. Returning the bare weight scored singles 3.3% under every other set on the
        // same chart, so a 105 × 1 read as 105 against a 102.5 × 2's 109.3.
        return weight * (1 + Double(reps) / 30)
    }

    /// Best estimate from the working sets of one session, or nil if no set qualifies.
    static func best(from sets: [LoggedSet]) -> Double? {
        sets.filter { !$0.isWarmup }
            .compactMap { epley(weight: $0.weight, reps: $0.reps) }
            .max()
    }
}
