import Foundation

nonisolated struct ExerciseConfig: Hashable, Sendable {
    var repRangeLow: Int
    var repRangeHigh: Int
    var increment: Double
    var setCount: Int
    var rpeCap: Double = 9
    var startingWeight: Double? = nil
}

nonisolated struct LoggedSet: Hashable, Sendable {
    var weight: Double
    var reps: Int
    var rpe: Double? = nil
    var isWarmup: Bool = false
}

/// One exercise's working sets in one completed session.
nonisolated struct SessionResult: Hashable, Sendable {
    var date: Date
    var sets: [LoggedSet]
    var readinessWasLow: Bool = false
}

nonisolated enum Verdict: String, Sendable {
    case progressed, held, failed, incomplete

    var label: String {
        switch self {
        case .progressed: "Progressed"
        case .held: "Held"
        case .failed: "Missed"
        case .incomplete: "Incomplete"
        }
    }
}

/// Daily readiness inputs. Deliberately small, capped effect (DESIGN.md §2.4).
nonisolated struct Readiness: Hashable, Sendable {
    static let sleepThresholdHours = 6.0
    static let sorenessThreshold = 4
    static let loadMultiplier = 0.95

    var sleepHours: Double? = nil
    var soreness: [Muscle: Int] = [:]

    var hasAnyInput: Bool { sleepHours != nil || !soreness.isEmpty }

    func isLow(for muscles: [MuscleWeight]) -> Bool {
        if let sleepHours, sleepHours < Self.sleepThresholdHours { return true }
        return muscles.contains { $0.weight >= 0.5 && (soreness[$0.muscle] ?? 0) >= Self.sorenessThreshold }
    }
}

nonisolated enum StallAction: String, Sendable {
    case addSet, fixRecovery, deload

    var label: String {
        switch self {
        case .addSet: "Add a set"
        case .fixRecovery: "Fix recovery"
        case .deload: "Deload"
        }
    }
}

nonisolated struct Prescription: Hashable, Sendable {
    var weight: Double
    var repRangeLow: Int
    var repRangeHigh: Int
    var setCount: Int
    var reason: String
    var lastVerdict: Verdict? = nil
    var stallStreak: Int = 0
    var stallAction: StallAction? = nil
    var readinessAdjusted: Bool = false
    var needsStartingWeight: Bool = false

    var isNotable: Bool { stallAction != nil || lastVerdict == .progressed || readinessAdjusted }
}

/// Double progression with autoregulated deloads. Rules in DESIGN.md §2.3–2.4.
nonisolated enum ProgressionEngine {
    static let deloadFactor = 0.9
    static let stallThreshold = 3
    static let consecutiveFailThreshold = 2
    static let minimumWeeklySets = 10.0
    /// A session whose top load is below this fraction of the previous session's is treated as a deload,
    /// which resets the stall counter.
    static let deloadBoundaryFactor = 0.95

    static func verdict(for sets: [LoggedSet], config: ExerciseConfig) -> Verdict {
        let working = sets.filter { !$0.isWarmup && $0.reps > 0 }
        guard !working.isEmpty else { return .incomplete }
        if working.contains(where: { $0.reps < config.repRangeLow }) { return .failed }
        let allAtTop = working.allSatisfy { $0.reps >= config.repRangeHigh && ($0.rpe ?? 10) <= config.rpeCap }
        return allAtTop ? .progressed : .held
    }

    static func topWorkingWeight(_ sets: [LoggedSet]) -> Double? {
        sets.filter { !$0.isWarmup && $0.reps > 0 }.map(\.weight).max()
    }

    static func round(_ weight: Double, toIncrement increment: Double) -> Double {
        guard increment > 0 else { return weight }
        return (weight / increment).rounded() * increment
    }

    /// Consecutive sessions without a Progressed verdict, counted back from the most recent,
    /// stopping at a deload boundary. Also returns consecutive fails and how many of the
    /// streak's sessions had low readiness.
    static func stallStreak(history: [SessionResult], config: ExerciseConfig) -> (streak: Int, consecutiveFails: Int, lowReadiness: Int) {
        var streak = 0
        var lowReadiness = 0
        var consecutiveFails = 0
        var countingFails = true
        for index in stride(from: history.count - 1, through: 0, by: -1) {
            let verdict = verdict(for: history[index].sets, config: config)
            if verdict == .incomplete { continue }
            if verdict == .progressed { break }
            if verdict == .failed && countingFails { consecutiveFails += 1 } else { countingFails = false }
            streak += 1
            if history[index].readinessWasLow { lowReadiness += 1 }
            if index > 0,
               let current = topWorkingWeight(history[index].sets),
               let previous = topWorkingWeight(history[index - 1].sets),
               current < previous * deloadBoundaryFactor {
                break   // this session was a deload; the counter restarts here
            }
        }
        return (streak, consecutiveFails, lowReadiness)
    }

    static func prescription(history: [SessionResult],
                             config: ExerciseConfig,
                             muscles: [MuscleWeight] = [],
                             readiness: Readiness? = nil,
                             weeklySetsForPrimaryMuscle: Double? = nil,
                             formatWeight: (Double) -> String = { "\(format($0)) kg" }) -> Prescription {
        let low = config.repRangeLow, high = config.repRangeHigh
        var result = Prescription(weight: 0, repRangeLow: low, repRangeHigh: high, setCount: config.setCount, reason: "")

        guard let last = history.last, let lastWeight = topWorkingWeight(last.sets) else {
            if let start = config.startingWeight, start > 0 {
                result.weight = start
                result.reason = "First session. Start at \(formatWeight(start)) and aim for RPE 7."
            } else {
                result.reason = "No history yet. Pick a weight you can lift for \(high) reps at RPE 7."
                result.needsStartingWeight = true
            }
            return result
        }

        let lastVerdict = verdict(for: last.sets, config: config)
        let stall = stallStreak(history: history, config: config)
        result.lastVerdict = lastVerdict
        result.stallStreak = stall.streak

        let stalled = stall.streak >= stallThreshold || stall.consecutiveFails >= consecutiveFailThreshold
        if stalled {
            if let weekly = weeklySetsForPrimaryMuscle, weekly < minimumWeeklySets {
                result.stallAction = .addSet
                result.weight = lastWeight
                result.setCount = config.setCount + 1
                result.reason = "Stalled for \(stall.streak) sessions and weekly volume is under \(Int(minimumWeeklySets)) sets. Add a set before changing the load."
            } else if stall.streak > 0 && stall.lowReadiness * 2 > stall.streak {
                result.stallAction = .fixRecovery
                result.weight = lastWeight
                result.reason = "Stalled, but readiness was low for most of those sessions. Fix sleep and soreness before deloading."
            } else {
                result.stallAction = .deload
                result.weight = round(lastWeight * deloadFactor, toIncrement: config.increment)
                result.reason = "Stalled for \(stall.streak) sessions. Deload 10% to \(formatWeight(result.weight)) and climb back."
            }
        } else {
            switch lastVerdict {
            case .progressed:
                result.weight = lastWeight + config.increment
                result.reason = "Hit \(high) reps on every set at RPE \(format(config.rpeCap)) or below. Add \(formatWeight(config.increment))."
            case .held:
                result.weight = lastWeight
                result.reason = "Same weight. Chase \(high) reps on every set."
            case .failed:
                result.weight = lastWeight
                result.reason = "Missed the rep range last time. Repeat the weight once."
            case .incomplete:
                result.weight = lastWeight
                result.reason = "Last session was incomplete. Repeat it."
            }
        }

        if let readiness, readiness.isLow(for: muscles), result.weight > 0 {
            result.weight = round(result.weight * Readiness.loadMultiplier, toIncrement: config.increment)
            result.readinessAdjusted = true
            result.reason += " Readiness is low, so today is 5% lighter."
        }
        return result
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
