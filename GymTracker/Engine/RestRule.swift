import Foundation

/// Rest between working sets (DESIGN.md §2.1). Longer rests (≥2 min) beat 1 min for both
/// strength and hypertrophy in trained lifters, so the default is never short. Heavy, low-rep
/// work gets 3 min; higher-rep and isolation work 2 min. The value is per exercise and editable.
nonisolated enum RestRule {
    static let heavySeconds = 180
    static let lightSeconds = 120
    /// Rep ranges topping out at this or fewer reps are treated as heavy work.
    static let heavyRepRangeHigh = 10
    static let minimumSeconds = 30
    static let maximumSeconds = 600
    static let stepSeconds = 15

    static func defaultSeconds(repRangeHigh: Int) -> Int {
        repRangeHigh <= heavyRepRangeHigh ? heavySeconds : lightSeconds
    }

    static func clamp(_ seconds: Int) -> Int {
        min(maximumSeconds, max(minimumSeconds, seconds))
    }

    /// "3:00", "0:45", "12:30".
    static func label(_ seconds: Int) -> String {
        let clamped = max(0, seconds)
        return "\(clamped / 60):" + String(format: "%02d", clamped % 60)
    }
}
