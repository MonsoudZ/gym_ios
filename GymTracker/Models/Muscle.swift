import Foundation

nonisolated enum Muscle: String, Codable, CaseIterable, Identifiable, Sendable {
    case chest, lats, upperBack, lowerBack
    case frontDelt, sideDelt, rearDelt
    case biceps, triceps, forearms
    case quads, hamstrings, glutes, calves, abs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chest: "Chest"
        case .lats: "Lats"
        case .upperBack: "Upper back"
        case .lowerBack: "Lower back"
        case .frontDelt: "Front delts"
        case .sideDelt: "Side delts"
        case .rearDelt: "Rear delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .glutes: "Glutes"
        case .calves: "Calves"
        case .abs: "Abs"
        }
    }
}

/// How much one set of an exercise counts toward a muscle's weekly volume.
/// Bench press: chest 1.0, triceps 0.5, front delt 0.5.
nonisolated struct MuscleWeight: Codable, Hashable, Sendable {
    var muscle: Muscle
    var weight: Double
}
