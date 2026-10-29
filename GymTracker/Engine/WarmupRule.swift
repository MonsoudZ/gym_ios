import Foundation

/// One warm-up set: a fraction of the working weight for a few easy reps.
nonisolated struct WarmupStep: Hashable, Sendable {
    var weight: Double
    var reps: Int
}

/// Ramp to the working weight before the first hard set (DESIGN.md §2.2). Warm-ups never count
/// toward volume or verdicts. The 50 / 70 / 90 % ladder is a common coaching convention, not a
/// study result; the fractions and rep counts are design choices.
nonisolated enum WarmupRule {
    static let ladder: [(fraction: Double, reps: Int)] = [(0.5, 8), (0.7, 5), (0.9, 2)]
    /// Below this working weight a single lighter set is enough; below `minimumWeight` none.
    static let fullRampThreshold = 40.0   // kg
    static let minimumWeight = 20.0       // kg: an empty barbell

    /// An empty bar in the lifter's unit: 20 kg, or 45 lb. The floor has to sit on the plate
    /// grid the lifter loads, and 20 kg is 44.1 lb, which is not a bar anyone owns.
    static func barWeight(metric: Bool) -> Double { metric ? minimumWeight : Units.kg(fromLb: 45) }

    static func ramp(workingWeight: Double, increment: Double, metric: Bool = true) -> [WarmupStep] {
        let bar = barWeight(metric: metric)
        guard workingWeight >= bar else { return [] }
        let steps: [(fraction: Double, reps: Int)] = workingWeight >= fullRampThreshold ? ladder : [(0.6, 6)]
        var result: [WarmupStep] = []
        for step in steps {
            let weight = max(bar, ProgressionEngine.round(workingWeight * step.fraction, toIncrement: increment))
            // Skip a step that rounds onto the previous one or onto the working weight itself.
            if let last = result.last, weight <= last.weight { continue }
            if weight >= workingWeight { continue }
            result.append(WarmupStep(weight: weight, reps: step.reps))
        }
        return result
    }
}
