import Foundation

/// How the lifter likes to train, applied to the library's rep ranges (DESIGN.md §2.1: 3–6 for
/// strength, 6–12 for hypertrophy, 12–20 for isolation are all valid; the engine progresses
/// whichever is used). The library ships balanced; a heavy lifter who does 4–5 reps on
/// everything picks the strength style once instead of editing 95 exercises.
nonisolated enum RepStyle: String, Codable, CaseIterable, Sendable {
    case strength, balanced

    var label: String {
        switch self {
        case .strength: "Heavy: 3–6 reps"
        case .balanced: "Balanced: 6–12 reps"
        }
    }

    var summary: String {
        switch self {
        case .strength: "Barbell lifts 3–5, compounds 4–6, machines 6–8, small isolation 8–12. Add weight once every set hits the top."
        case .balanced: "Barbell lifts 5–8, compounds 8–12, machines 10–15, isolation 12–20, as the library ships."
        }
    }

    /// The range a library exercise gets under this style, from the range the library gives it.
    func range(forDefault low: Int, high: Int) -> (low: Int, high: Int) {
        switch self {
        case .balanced:
            return (low, high)
        case .strength:
            switch high {
            case ...6: return (low, high)   // already heavy: deadlift 3–5, front squat 4–6
            case ...8: return (3, 5)        // bench 6–8, squat 5–8
            case ...12: return (4, 6)       // rows, presses, pulldowns, curls
            case ...15: return (6, 8)       // machines, leg press, shrugs
            default: return (8, 12)         // flies, raises, core
            }
        }
    }

    /// What a new custom exercise starts with.
    var customDefault: (low: Int, high: Int) {
        self == .strength ? (4, 6) : (8, 12)
    }
}
