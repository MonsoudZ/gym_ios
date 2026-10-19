import Foundation

nonisolated enum VolumeBand: Sendable {
    case low, ok, high

    var label: String {
        switch self {
        case .low: "Under minimum"
        case .ok: "In range"
        case .high: "High"
        }
    }

    /// Short form for chart annotations, where colour alone would carry the band.
    var shortLabel: String {
        switch self {
        case .low: "low"
        case .ok: ""
        case .high: "high"
        }
    }
}

nonisolated struct VolumeSet: Hashable, Sendable {
    var muscles: [MuscleWeight]
    var isWarmup: Bool = false
}

/// Weekly hard sets per muscle, with evidence-based bands (DESIGN.md §2.5).
nonisolated enum VolumeTracker {
    static let minimumWeeklySets = 10.0
    static let highWeeklySets = 20.0

    static func weeklyVolume(_ sets: [VolumeSet]) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for set in sets where !set.isWarmup {
            for mw in set.muscles {
                totals[mw.muscle, default: 0] += mw.weight
            }
        }
        return totals
    }

    static func band(_ sets: Double) -> VolumeBand {
        if sets < minimumWeeklySets { return .low }
        if sets > highWeeklySets { return .high }
        return .ok
    }
}
