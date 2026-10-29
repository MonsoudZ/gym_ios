import Foundation

/// What the − and + buttons on a set row do (DESIGN.md §4, "During a workout"). Pure.
///
/// Weights step by the lift's plate increment and snap onto that grid, so a typed 187 lb
/// becomes 190 on +, not 192. Reps step by one. Stepping up from an empty field starts at a
/// sensible value (the previous set, last session, or the target) instead of at one step, so
/// a set is usually one or two taps from logged.
nonisolated enum SetStepRule {
    enum Direction { case up, down }

    /// The next weight in display units. Nil means the field is empty.
    static func weight(_ current: Double?, step: Double, direction: Direction, start: Double) -> Double? {
        let step = max(step, 0.001)
        guard let current, current > 0 else {
            return direction == .up ? snap(start, to: step) : nil
        }
        // Pound weights are stored in kilograms and come back as 154.99999999999997 or
        // 75.00000000000001; floor and ceil on the raw quotient would then step nowhere.
        let gridded = ((current / step) * 1_000_000).rounded() / 1_000_000
        let next: Double
        switch direction {
        case .up: next = (gridded.rounded(.down) + 1) * step
        case .down: next = (gridded.rounded(.up) - 1) * step
        }
        let rounded = (next * 1000).rounded() / 1000
        return rounded > 0 ? rounded : nil
    }

    /// The next rep count. Nil means the field is empty.
    static func reps(_ current: Int?, direction: Direction, start: Int) -> Int? {
        guard let current, current > 0 else {
            return direction == .up ? max(1, start) : nil
        }
        let next = direction == .up ? current + 1 : current - 1
        return next > 0 ? next : nil
    }

    /// The nearest multiple of `step` at or above a positive start value, so an odd carried-over
    /// weight still lands on a loadable number.
    private static func snap(_ value: Double, to step: Double) -> Double {
        guard value > 0 else { return step }
        let snapped = (value / step).rounded() * step
        return ((snapped > 0 ? snapped : step) * 1000).rounded() / 1000
    }
}
