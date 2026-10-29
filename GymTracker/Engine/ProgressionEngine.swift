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
    /// The session these sets came from, so a history row can open it for correction.
    var sessionID: UUID? = nil
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

    /// Shown with the label so the verdict never rests on colour alone.
    var systemImage: String {
        switch self {
        case .progressed: "arrow.up.circle.fill"
        case .held: "equal.circle"
        case .failed: "arrow.down.circle.fill"
        case .incomplete: "minus.circle"
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
    /// This morning's HRV and resting heart rate against the lifter's baseline, from Health.
    var heart: HeartReadiness? = nil

    var hasAnyInput: Bool { sleepHours != nil || !soreness.isEmpty || heart?.hasReading == true }

    /// Any one low input makes the day low. They never stack, and nothing here raises a load:
    /// the caller applies the single `loadMultiplier` once.
    func isLow(for muscles: [MuscleWeight]) -> Bool {
        if let sleepHours, sleepHours < Self.sleepThresholdHours { return true }
        if heart?.isLow == true { return true }
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

    var systemImage: String {
        switch self {
        case .addSet: "plus.circle"
        case .fixRecovery: "bed.double"
        case .deload: "arrow.down.right.circle"
        }
    }
}

nonisolated struct Prescription: Hashable, Sendable {
    var weight: Double
    var repRangeLow: Int
    var repRangeHigh: Int
    var setCount: Int
    var reason: String
    var rpeCap: Double = 9
    /// Last session's top load, when today's differs from it: what "up from 80" refers to.
    var previousWeight: Double? = nil
    var lastVerdict: Verdict? = nil
    var stallStreak: Int = 0
    var stallAction: StallAction? = nil
    var readinessAdjusted: Bool = false
    var needsStartingWeight: Bool = false

    var isNotable: Bool { stallAction != nil || lastVerdict == .progressed || readinessAdjusted }
}

/// A session where the top load dropped by more than the deload boundary: what it came down
/// from, and how long the lift had been stuck before it.
nonisolated struct DeloadMark: Hashable, Sendable {
    var fromWeight: Double
    var toWeight: Double
    var stalledSessionsBefore: Int

    var percentDrop: Double { fromWeight > 0 ? (1 - toWeight / fromWeight) * 100 : 0 }
}

/// One session of history as the engine saw it: its verdict, the stall streak as of that
/// session, and whether it was a deload. Lets the history screen show why loads moved.
nonisolated struct SessionAnnotation: Hashable, Sendable {
    var date: Date
    var verdict: Verdict
    /// Consecutive non-progressed sessions up to and including this one.
    var stallStreak: Int
    var deload: DeloadMark?
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

    /// `weight × factor` on the plate grid, always at least one step below `weight`. Rounding
    /// alone can land back on the same load (25 lb × 0.9 with a 5 lb step), and a deload that
    /// changes nothing never clears the stall it was meant to break.
    static func reduce(_ weight: Double, by factor: Double, increment: Double) -> Double {
        let rounded = round(weight * factor, toIncrement: increment)
        guard rounded < weight else { return max(0, weight - max(increment, 0)) }
        return rounded
    }

    /// Whether `current` is a deload from `previous`: a drop past the deload boundary. On a day
    /// readiness was low the engine itself cut the load by 5%, and that cut can round below
    /// the boundary (97.5 kg → 92.5 kg is a 5.1% drop), so there the boundary is the cut
    /// load: only a session lighter than the readiness cut would have made it is a deload.
    static func isDeloadBoundary(current: Double, previous: Double, readinessWasLow: Bool, increment: Double) -> Bool {
        var boundary = previous * deloadBoundaryFactor
        if readinessWasLow {
            let cut = round(previous * Readiness.loadMultiplier, toIncrement: increment)
            if cut < previous { boundary = cut }
        }
        return current < boundary - 1e-9
    }

    /// Working sets that reached the top of the range but carry no RPE. The verdict counts a
    /// missing RPE as 10, so these are the sets that silently block progression.
    static func topSetsMissingRPE(_ sets: [LoggedSet], config: ExerciseConfig) -> Int {
        sets.filter { !$0.isWarmup && $0.reps >= config.repRangeHigh && $0.rpe == nil }.count
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
               isDeloadBoundary(current: current, previous: previous,
                                readinessWasLow: history[index].readinessWasLow, increment: config.increment) {
                break   // this session was a deload; the counter restarts here
            }
        }
        return (streak, consecutiveFails, lowReadiness)
    }

    /// Walks the history forwards with the same rules `stallStreak` applies backwards, so the
    /// streak shown on a past session matches what the engine counted at the time.
    static func annotate(history: [SessionResult], config: ExerciseConfig) -> [SessionAnnotation] {
        var streak = 0
        var result: [SessionAnnotation] = []
        for (index, session) in history.enumerated() {
            let verdict = verdict(for: session.sets, config: config)
            var deload: DeloadMark?
            if index > 0,
               let current = topWorkingWeight(session.sets),
               let previous = topWorkingWeight(history[index - 1].sets),
               isDeloadBoundary(current: current, previous: previous,
                                readinessWasLow: session.readinessWasLow, increment: config.increment) {
                deload = DeloadMark(fromWeight: previous, toWeight: current, stalledSessionsBefore: streak)
                streak = 0
            }
            switch verdict {
            case .progressed: streak = 0
            case .incomplete: break
            case .held, .failed: streak += 1
            }
            result.append(SessionAnnotation(date: session.date, verdict: verdict, stallStreak: streak, deload: deload))
        }
        return result
    }

    static func prescription(history: [SessionResult],
                             config: ExerciseConfig,
                             muscles: [MuscleWeight] = [],
                             readiness: Readiness? = nil,
                             weeklySetsForPrimaryMuscle: Double? = nil,
                             formatWeight: (Double) -> String = { "\(format($0)) kg" }) -> Prescription {
        let low = config.repRangeLow, high = config.repRangeHigh
        var result = Prescription(weight: 0, repRangeLow: low, repRangeHigh: high, setCount: config.setCount, reason: "", rpeCap: config.rpeCap)

        // The last session with a working set. A session holding only warm-ups (the lift was
        // skipped after warming up) has no verdict and must not read as "no history".
        guard let last = history.last(where: { topWorkingWeight($0.sets) != nil }),
              let lastWeight = topWorkingWeight(last.sets) else {
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

        // A trailing run of low-readiness days, each lifted at or under the session before it and
        // none by enough to be a deload, was the engine's own 5% pull-back (one bad day, or a bad
        // week). The lift's baseline is what the engine would have prescribed before the run with
        // readiness aside (DESIGN.md §2.4: readiness only pulls a bad day back): the lighter days
        // neither lower the baseline nor earn an increment on top of it.
        var runStart: Int?
        if var cursorIndex = history.lastIndex(where: { $0 == last }) {
            var cursorWeight = lastWeight
            while history[cursorIndex].readinessWasLow,
                  let beforeIndex = history[..<cursorIndex].lastIndex(where: { topWorkingWeight($0.sets) != nil }),
                  let beforeWeight = topWorkingWeight(history[beforeIndex].sets),
                  cursorWeight <= beforeWeight,
                  !isDeloadBoundary(current: cursorWeight, previous: beforeWeight, readinessWasLow: true, increment: config.increment) {
                runStart = cursorIndex
                cursorIndex = beforeIndex
                cursorWeight = beforeWeight
            }
        }
        let pulledBack = runStart != nil
        let baseline = runStart.map {
            prescription(history: Array(history[..<$0]), config: config, muscles: muscles,
                         weeklySetsForPrimaryMuscle: weeklySetsForPrimaryMuscle, formatWeight: formatWeight).weight
        } ?? lastWeight

        let stalled = stall.streak >= stallThreshold || stall.consecutiveFails >= consecutiveFailThreshold
        if stalled {
            if let weekly = weeklySetsForPrimaryMuscle, weekly < minimumWeeklySets {
                result.stallAction = .addSet
                result.weight = baseline
                result.setCount = config.setCount + 1
                result.reason = "Stalled for \(stall.streak) sessions and weekly volume is under \(Int(minimumWeeklySets)) sets. Add a set before changing the load."
            } else if stall.streak > 0 && stall.lowReadiness * 2 > stall.streak {
                result.stallAction = .fixRecovery
                result.weight = baseline
                result.reason = "Stalled, but readiness was low for most of those sessions. Fix sleep and soreness before deloading."
            } else {
                result.stallAction = .deload
                result.weight = reduce(baseline, by: deloadFactor, increment: config.increment)
                result.reason = "Stalled for \(stall.streak) sessions. Deload 10% to \(formatWeight(result.weight)) and climb back."
                if everySetAtFailure(history.suffix(max(1, stall.streak))) {
                    result.reason += " Every set was RPE 10; stop a rep or two short of failure on the way back up."
                }
            }
        } else if pulledBack && lastVerdict == .failed {
            // A miss is a miss, lighter day or not: same load once (§2.3), not back up.
            result.weight = lastWeight
            result.reason = "Missed the rep range on last session's lighter day. Repeat the weight once."
        } else if pulledBack {
            result.weight = baseline
            result.reason = lastVerdict == .progressed
                ? "Hit \(high) reps on every set on last session's lighter day. Back to \(formatWeight(baseline))."
                : "Last session was 5% lighter for low readiness. Back to \(formatWeight(baseline))."
        } else {
            switch lastVerdict {
            case .progressed:
                result.weight = lastWeight + config.increment
                result.reason = "Hit \(high) reps on every set at RPE \(format(config.rpeCap)) or below. Add \(formatWeight(config.increment))."
            case .held:
                result.weight = lastWeight
                let missing = topSetsMissingRPE(last.sets, config: config)
                result.reason = missing > 0
                    ? "Same weight. \(missing) set\(missing == 1 ? "" : "s") hit \(high) reps with no RPE logged, which counts as RPE 10. Log RPE to progress."
                    : "Same weight. Chase \(high) reps on every set."
            case .failed:
                result.weight = lastWeight
                result.reason = "Missed the rep range last time. Repeat the weight once."
            case .incomplete:
                result.weight = lastWeight
                result.reason = "Last session was incomplete. Repeat it."
            }
        }

        if let readiness, readiness.isLow(for: muscles), result.weight > 0 {
            let lighter = round(result.weight * Readiness.loadMultiplier, toIncrement: config.increment)
            if lighter < result.weight {
                result.weight = lighter
                result.readinessAdjusted = true
                result.reason += " Readiness is low, so today is 5% lighter."
            } else {
                result.reason += " Readiness is low, but 5% is less than a plate step here, so the load stays."
            }
        }
        if result.weight != lastWeight { result.previousWeight = lastWeight }
        return result
    }

    /// Every working set in these sessions was taken to RPE 10. Going to failure on every set
    /// while stalling is the pattern the spec says to flag (DESIGN.md §2.1).
    static func everySetAtFailure<S: Sequence>(_ sessions: S) -> Bool where S.Element == SessionResult {
        var any = false
        for session in sessions {
            for set in session.sets where !set.isWarmup && set.reps > 0 {
                any = true
                if (set.rpe ?? 10) < 10 { return false }
            }
        }
        return any
    }

    static func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }
}
