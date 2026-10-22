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

/// How much of the work a muscle does in an exercise, graded from its volume weight: a primary
/// mover counts a full hard set, a secondary mover half, a stabiliser or lightly involved muscle
/// a quarter. The muscle map and the exercise editor speak in these tiers; the engine sums the
/// weights.
nonisolated enum MuscleInvolvement: Int, CaseIterable, Identifiable, Comparable, Sendable {
    case primary, secondary, stabiliser

    var id: Int { rawValue }

    /// The volume weight a muscle at this tier is stored with.
    var weight: Double {
        switch self {
        case .primary: 1
        case .secondary: 0.5
        case .stabiliser: 0.25
        }
    }

    /// The tier a stored weight falls in, or nil for a muscle that is not worked at all.
    init?(weight: Double) {
        guard weight > 0 else { return nil }
        self = weight >= 1 ? .primary : weight >= 0.5 ? .secondary : .stabiliser
    }

    var displayName: String {
        switch self {
        case .primary: "Primary"
        case .secondary: "Secondary"
        case .stabiliser: "Stabiliser"
        }
    }

    /// Plural, for a list heading.
    var pluralName: String {
        switch self {
        case .primary: "Primary movers"
        case .secondary: "Secondary"
        case .stabiliser: "Stabilisers"
        }
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated extension MuscleWeight {
    init(muscle: Muscle, involvement: MuscleInvolvement) {
        self.init(muscle: muscle, weight: involvement.weight)
    }

    var involvement: MuscleInvolvement? { MuscleInvolvement(weight: weight) }
}

nonisolated extension Array where Element == MuscleWeight {
    /// The muscles at each tier, in the order they are listed. A muscle listed twice keeps its
    /// highest tier.
    var byInvolvement: [MuscleInvolvement: [Muscle]] {
        var best: [Muscle: MuscleInvolvement] = [:]
        var order: [Muscle] = []
        for mw in self {
            guard let tier = mw.involvement else { continue }
            if let current = best[mw.muscle] {
                if tier < current { best[mw.muscle] = tier }
            } else {
                best[mw.muscle] = tier
                order.append(mw.muscle)
            }
        }
        var result: [MuscleInvolvement: [Muscle]] = [:]
        for muscle in order { result[best[muscle]!, default: []].append(muscle) }
        return result
    }

    /// "Primary: Quads, Glutes. Secondary: Lower back. Stabilisers: Abs."
    var involvementSummary: String {
        let tiers = byInvolvement
        let parts = MuscleInvolvement.allCases.compactMap { tier -> String? in
            guard let muscles = tiers[tier], !muscles.isEmpty else { return nil }
            return "\(tier.pluralName): \(muscles.map(\.displayName).joined(separator: ", "))"
        }
        return parts.isEmpty ? "No muscles set" : parts.joined(separator: ". ") + "."
    }
}
