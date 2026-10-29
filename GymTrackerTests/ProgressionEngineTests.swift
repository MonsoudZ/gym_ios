import XCTest
@testable import GymTracker

final class ProgressionEngineTests: XCTestCase {
    let config = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: 2.5, setCount: 3, rpeCap: 9)
    let chest = [MuscleWeight(muscle: .chest, weight: 1), MuscleWeight(muscle: .triceps, weight: 0.5)]

    private func session(_ weight: Double, reps: [Int], rpe: Double = 8, daysAgo: Int = 0, lowReadiness: Bool = false) -> SessionResult {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
        return SessionResult(date: date, sets: reps.map { LoggedSet(weight: weight, reps: $0, rpe: rpe) }, readinessWasLow: lowReadiness)
    }

    // MARK: Verdicts

    func testAllSetsAtTopUnderCapIsProgressed() {
        XCTAssertEqual(ProgressionEngine.verdict(for: session(80, reps: [8, 8, 8]).sets, config: config), .progressed)
    }

    func testTopRepsOverCapIsHeld() {
        XCTAssertEqual(ProgressionEngine.verdict(for: session(80, reps: [8, 8, 8], rpe: 9.5).sets, config: config), .held)
    }

    func testInRangeButNotTopIsHeld() {
        XCTAssertEqual(ProgressionEngine.verdict(for: session(80, reps: [8, 7, 6]).sets, config: config), .held)
    }

    func testBelowRangeIsFailed() {
        XCTAssertEqual(ProgressionEngine.verdict(for: session(80, reps: [8, 7, 5]).sets, config: config), .failed)
    }

    func testNoWorkingSetsIsIncomplete() {
        XCTAssertEqual(ProgressionEngine.verdict(for: [LoggedSet(weight: 60, reps: 5, isWarmup: true)], config: config), .incomplete)
    }

    // MARK: Prescriptions

    func testProgressedAddsIncrement() {
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 8, 8])], config: config)
        XCTAssertEqual(p.weight, 82.5)
        XCTAssertEqual(p.lastVerdict, .progressed)
        XCTAssertNil(p.stallAction)
    }

    func testHeldRepeatsWeight() {
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 7, 7])], config: config)
        XCTAssertEqual(p.weight, 80)
        XCTAssertEqual(p.lastVerdict, .held)
    }

    func testSingleFailRepeatsWeight() {
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 7, 4])], config: config)
        XCTAssertEqual(p.weight, 80)
        XCTAssertNil(p.stallAction)
    }

    func testTwoConsecutiveFailsTriggersStall() {
        let history = [session(80, reps: [6, 5, 5], daysAgo: 4), session(80, reps: [6, 5, 5], daysAgo: 1)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.stallAction, .deload)
    }

    func testThreeHeldSessionsDeloadsTenPercentRounded() {
        let history = [session(80, reps: [8, 7, 7], daysAgo: 7), session(80, reps: [8, 7, 6], daysAgo: 4), session(80, reps: [7, 7, 7], daysAgo: 1)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.stallAction, .deload)
        XCTAssertEqual(p.stallStreak, 3)
        XCTAssertEqual(p.weight, 72.5)   // 72 rounded to the 2.5 kg increment
    }

    func testStallWithLowVolumeSuggestsAddingASet() {
        let history = [session(80, reps: [7, 7, 7], daysAgo: 7), session(80, reps: [7, 7, 7], daysAgo: 4), session(80, reps: [7, 7, 7], daysAgo: 1)]
        let p = ProgressionEngine.prescription(history: history, config: config, weeklySetsForPrimaryMuscle: 6)
        XCTAssertEqual(p.stallAction, .addSet)
        XCTAssertEqual(p.weight, 80)
        XCTAssertEqual(p.setCount, 4)
    }

    func testStallWithLowReadinessSuggestsRecovery() {
        let history = [
            session(80, reps: [7, 7, 7], daysAgo: 7, lowReadiness: true),
            session(80, reps: [7, 7, 7], daysAgo: 4, lowReadiness: true),
            session(80, reps: [7, 7, 7], daysAgo: 1),
        ]
        let p = ProgressionEngine.prescription(history: history, config: config, weeklySetsForPrimaryMuscle: 14)
        XCTAssertEqual(p.stallAction, .fixRecovery)
        XCTAssertEqual(p.weight, 80)
    }

    func testDeloadAlwaysDropsAtLeastOneStep() {
        // 10 kg × 0.9 = 9, which rounds back to 10 on a 2.5 kg grid; the deload must still drop.
        XCTAssertEqual(ProgressionEngine.reduce(10, by: 0.9, increment: 2.5), 7.5)
        XCTAssertEqual(ProgressionEngine.reduce(12.5, by: 0.9, increment: 2.5), 10)
        XCTAssertEqual(ProgressionEngine.reduce(100, by: 0.9, increment: 2.5), 90)
        let fiveLb = Units.kg(fromLb: 5)
        XCTAssertEqual(Units.lb(fromKg: ProgressionEngine.reduce(Units.kg(fromLb: 25), by: 0.9, increment: fiveLb)), 20, accuracy: 0.001)
        XCTAssertEqual(ProgressionEngine.reduce(0, by: 0.9, increment: 2.5), 0)

        let light = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: 2.5, setCount: 3, rpeCap: 9)
        let stalled = [session(10, reps: [7, 7, 7], daysAgo: 6), session(10, reps: [7, 7, 7], daysAgo: 3), session(10, reps: [7, 7, 7])]
        let p = ProgressionEngine.prescription(history: stalled, config: light, weeklySetsForPrimaryMuscle: 12)
        XCTAssertEqual(p.stallAction, .deload)
        XCTAssertEqual(p.weight, 7.5)
    }

    func testReadinessCutSmallerThanAStepIsNotClaimed() {
        let low = Readiness(sleepHours: 5)
        let heavy = ProgressionEngine.prescription(history: [session(100, reps: [7, 7, 7])], config: config, muscles: chest, readiness: low)
        XCTAssertEqual(heavy.weight, 95)
        XCTAssertTrue(heavy.readinessAdjusted)
        let light = ProgressionEngine.prescription(history: [session(20, reps: [7, 7, 7])], config: config, muscles: chest, readiness: low)
        XCTAssertEqual(light.weight, 20, "5% of 20 kg is 1 kg, under half a 2.5 kg step")
        XCTAssertFalse(light.readinessAdjusted)
        XCTAssertTrue(light.reason.contains("less than a plate step"))
    }

    func testMissingRPEOnATopSetIsExplained() {
        let noRPE = SessionResult(date: .now, sets: [LoggedSet(weight: 80, reps: 8, rpe: nil), LoggedSet(weight: 80, reps: 8, rpe: 8), LoggedSet(weight: 80, reps: 8, rpe: 8)])
        XCTAssertEqual(ProgressionEngine.verdict(for: noRPE.sets, config: config), .held)
        XCTAssertEqual(ProgressionEngine.topSetsMissingRPE(noRPE.sets, config: config), 1)
        let p = ProgressionEngine.prescription(history: [noRPE], config: config)
        XCTAssertEqual(p.weight, 80)
        XCTAssertTrue(p.reason.contains("no RPE logged"), p.reason)
        XCTAssertEqual(p.rpeCap, 9)
    }

    func testPrescriptionNamesThePreviousWeightOnlyWhenItChanges() {
        let up = ProgressionEngine.prescription(history: [session(80, reps: [8, 8, 8])], config: config)
        XCTAssertEqual(up.weight, 82.5)
        XCTAssertEqual(up.previousWeight, 80)
        let held = ProgressionEngine.prescription(history: [session(80, reps: [8, 7, 7])], config: config)
        XCTAssertNil(held.previousWeight)
    }

    func testStallingAtFailureEverySetIsFlagged() {
        let grinding = [session(80, reps: [7, 7, 7], rpe: 10, daysAgo: 6), session(80, reps: [7, 7, 7], rpe: 10, daysAgo: 3), session(80, reps: [7, 7, 7], rpe: 10)]
        let p = ProgressionEngine.prescription(history: grinding, config: config, weeklySetsForPrimaryMuscle: 12)
        XCTAssertEqual(p.stallAction, .deload)
        XCTAssertTrue(p.reason.contains("RPE 10"), p.reason)
        let steady = [session(80, reps: [7, 7, 7], rpe: 9, daysAgo: 6), session(80, reps: [7, 7, 7], rpe: 10, daysAgo: 3), session(80, reps: [7, 7, 7], rpe: 10)]
        XCTAssertFalse(ProgressionEngine.prescription(history: steady, config: config, weeklySetsForPrimaryMuscle: 12).reason.contains("RPE 10"))
    }

    func testDeloadBoundaryResetsStreak() {
        // Three stalls, then a deload session, then one more held session: streak should be 2, not 5.
        let history = [
            session(80, reps: [7, 7, 7], daysAgo: 14), session(80, reps: [7, 7, 7], daysAgo: 11), session(80, reps: [7, 7, 7], daysAgo: 8),
            session(72.5, reps: [8, 8, 7], daysAgo: 4),
            session(72.5, reps: [8, 8, 7], daysAgo: 1),
        ]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.stallStreak, 2)
        XCTAssertNil(p.stallAction)
        XCTAssertEqual(p.weight, 72.5)
    }

    func testReadinessCutIsNotADeload() {
        // 97.5 × 0.95 = 92.625 → 92.5 on the 2.5 kg grid: a 5.1% drop, past the 5% deload
        // boundary. The low-readiness session must still count toward the stall.
        let history = [
            session(97.5, reps: [7, 7, 7], daysAgo: 8),
            session(92.5, reps: [7, 7, 7], daysAgo: 4, lowReadiness: true),
            session(92.5, reps: [7, 7, 7], daysAgo: 1),
        ]
        let p = ProgressionEngine.prescription(history: history, config: config, weeklySetsForPrimaryMuscle: 12)
        XCTAssertEqual(p.stallStreak, 3)
        XCTAssertEqual(p.stallAction, .deload)
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.map { $0.deload != nil }, [false, false, false])
        XCTAssertEqual(notes.map(\.stallStreak), [1, 2, 3])
    }

    func testDeloadOnALowReadinessDayStillResetsTheStreak() {
        // Deload 100 → 90, then the 5% cut → 85.5 → 85: lighter than the cut alone (95).
        let history = [
            session(100, reps: [7, 7, 7], daysAgo: 11), session(100, reps: [7, 7, 7], daysAgo: 8), session(100, reps: [7, 7, 7], daysAgo: 5),
            session(85, reps: [8, 8, 7], daysAgo: 1, lowReadiness: true),
        ]
        XCTAssertEqual(ProgressionEngine.stallStreak(history: history, config: config).streak, 1)
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.last?.deload?.fromWeight, 100)
        XCTAssertEqual(notes.last?.deload?.stalledSessionsBefore, 3)
    }

    func testWarmupOnlyLastSessionKeepsTheLiftsHistory() {
        // Warm-ups done, lift skipped: the session has no working sets and no verdict. The
        // prescription comes from the last real session, not "no history yet".
        let warmupsOnly = SessionResult(date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!,
                                        sets: [LoggedSet(weight: 60, reps: 8, isWarmup: true), LoggedSet(weight: 90, reps: 5, isWarmup: true)])
        let history = [session(120, reps: [8, 8, 8], daysAgo: 4), warmupsOnly]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertFalse(p.needsStartingWeight)
        XCTAssertEqual(p.weight, 122.5)
        XCTAssertEqual(p.lastVerdict, .progressed)
        XCTAssertEqual(p.previousWeight, 120)
    }

    func testALighterLowReadinessDayDoesNotBecomeTheBaseline() {
        // 100 Held; low sleep → 95 prescribed; the lifter hits 8s on the lighter load. Next
        // session goes back to 100, not to 97.5 "up from 95".
        let progressedLight = [session(100, reps: [7, 7, 7], daysAgo: 4), session(95, reps: [8, 8, 8], daysAgo: 1, lowReadiness: true)]
        let p = ProgressionEngine.prescription(history: progressedLight, config: config)
        XCTAssertEqual(p.weight, 100)
        XCTAssertEqual(p.previousWeight, 95)
        XCTAssertTrue(p.reason.contains("Back to"), p.reason)

        let heldLight = [session(100, reps: [7, 7, 7], daysAgo: 4), session(95, reps: [7, 7, 7], daysAgo: 1, lowReadiness: true)]
        XCTAssertEqual(ProgressionEngine.prescription(history: heldLight, config: config).weight, 100)

        // A deload taken on a low day is a new baseline, not a pull-back.
        let deloaded = [
            session(100, reps: [7, 7, 7], daysAgo: 11), session(100, reps: [7, 7, 7], daysAgo: 8), session(100, reps: [7, 7, 7], daysAgo: 5),
            session(85, reps: [7, 7, 7], daysAgo: 1, lowReadiness: true),
        ]
        XCTAssertEqual(ProgressionEngine.prescription(history: deloaded, config: config).weight, 85)

        // A low day lifted at the same load (5% was under half a step) changes nothing.
        let unchanged = [session(100, reps: [8, 8, 8], daysAgo: 4), session(100, reps: [8, 8, 8], daysAgo: 1, lowReadiness: true)]
        XCTAssertEqual(ProgressionEngine.prescription(history: unchanged, config: config).weight, 102.5)
    }

    func testAMissOnTheLighterDayHoldsThatLoadOnce() {
        // 100 Held → 95 on a bad day → 5,5,5: Failed. Same load once (§2.3), not back up to 100.
        let history = [session(100, reps: [7, 7, 7], daysAgo: 4), session(95, reps: [5, 5, 5], daysAgo: 1, lowReadiness: true)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.weight, 95)
        XCTAssertEqual(p.lastVerdict, .failed)
    }

    func testABadWeekOfPullBacksStillReturnsToTheBaseline() {
        // Two low days in a row, both at the cut load: the baseline is still the 100 before them.
        let history = [
            session(100, reps: [7, 7, 7], daysAgo: 7),
            session(95, reps: [7, 7, 7], daysAgo: 4, lowReadiness: true),
            session(95, reps: [7, 7, 7], daysAgo: 1, lowReadiness: true),
        ]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.weight, 100)
        XCTAssertEqual(p.stallStreak, 3, "the lighter days still count toward the stall")
        // Two of the three stalled sessions were low-readiness days: step 2 says fix recovery
        // before deloading, at the real baseline.
        XCTAssertEqual(p.stallAction, .fixRecovery)
        let withVolume = ProgressionEngine.prescription(history: history, config: config, weeklySetsForPrimaryMuscle: 12)
        XCTAssertEqual(withVolume.stallAction, .fixRecovery)
        XCTAssertEqual(withVolume.weight, 100)
    }

    func testAnEarnedIncrementSurvivesALowDay() {
        // 100 Progressed earns 102.5; the bad day cut that to 97.5. The baseline is the 102.5
        // the lifter earned, not the 100 they last lifted on a normal day.
        let history = [session(100, reps: [8, 8, 8], daysAgo: 4), session(97.5, reps: [8, 8, 8], daysAgo: 1, lowReadiness: true)]
        XCTAssertEqual(ProgressionEngine.prescription(history: history, config: config).weight, 102.5)
    }

    func testProgressBreaksTheStreak() {
        let history = [session(80, reps: [7, 7, 7], daysAgo: 7), session(80, reps: [7, 7, 7], daysAgo: 4), session(80, reps: [8, 8, 8], daysAgo: 1)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.stallStreak, 0)
        XCTAssertEqual(p.weight, 82.5)
    }

    // MARK: History annotation

    func testAnnotateMarksDeloadWithStreakBeforeIt() {
        let history = [
            session(80, reps: [8, 8, 8], daysAgo: 20),
            session(82.5, reps: [7, 7, 7], daysAgo: 17), session(82.5, reps: [7, 7, 7], daysAgo: 14), session(82.5, reps: [7, 7, 7], daysAgo: 11),
            session(75, reps: [8, 8, 7], daysAgo: 8),
            session(75, reps: [8, 8, 8], daysAgo: 4),
        ]
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.map(\.stallStreak), [0, 1, 2, 3, 1, 0])
        XCTAssertEqual(notes.map { $0.deload != nil }, [false, false, false, false, true, false])
        let deload = notes[4].deload!
        XCTAssertEqual(deload.fromWeight, 82.5)
        XCTAssertEqual(deload.toWeight, 75)
        XCTAssertEqual(deload.stalledSessionsBefore, 3)
        XCTAssertEqual(deload.percentDrop, 9.09, accuracy: 0.01)
    }

    func testAnnotateStreakMatchesStallStreak() {
        let history = [
            session(80, reps: [7, 7, 7], daysAgo: 14), session(80, reps: [7, 7, 7], daysAgo: 11), session(80, reps: [7, 7, 7], daysAgo: 8),
            session(72.5, reps: [8, 8, 7], daysAgo: 4),
            session(72.5, reps: [8, 8, 7], daysAgo: 1),
        ]
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.last?.stallStreak, ProgressionEngine.stallStreak(history: history, config: config).streak)
        XCTAssertEqual(notes.last?.stallStreak, 2)
    }

    func testAnnotateIgnoresIncompleteSessionsForTheStreak() {
        let history = [session(80, reps: [7, 7, 7], daysAgo: 7), session(80, reps: [0, 0, 0], daysAgo: 4), session(80, reps: [7, 7, 7], daysAgo: 1)]
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.map(\.verdict), [.held, .incomplete, .held])
        XCTAssertEqual(notes.map(\.stallStreak), [1, 1, 2])
    }

    // MARK: Readiness

    func testLowSleepReducesLoadFivePercent() {
        let readiness = Readiness(sleepHours: 5)
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 8, 8])], config: config, muscles: chest, readiness: readiness)
        XCTAssertTrue(p.readinessAdjusted)
        XCTAssertEqual(p.weight, 77.5)   // 82.5 × 0.95 = 78.4 → 77.5
    }

    func testSorenessOnSecondaryMuscleDoesNotCount() {
        let readiness = Readiness(sleepHours: 8, soreness: [.lats: 5])
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 8, 8])], config: config, muscles: chest, readiness: readiness)
        XCTAssertFalse(p.readinessAdjusted)
        XCTAssertEqual(p.weight, 82.5)
    }

    func testSorenessOnPrimaryMuscleCounts() {
        let readiness = Readiness(sleepHours: 8, soreness: [.chest: 4])
        XCTAssertTrue(readiness.isLow(for: chest))
    }

    // MARK: Missed with a reason

    private func missed(_ weight: Double, daysAgo: Int, reason: MissReason?) -> SessionResult {
        var s = session(weight, reps: [5, 5, 5], rpe: 10, daysAgo: daysAgo)
        s.missReason = reason
        return s
    }

    func testAnExcusedMissIsLeftOutOfTheStallCount() {
        // Held, held, then missed because the squat rack was taken: still two, not three, and
        // not a consecutive-fail stall either.
        let history = [session(80, reps: [7, 7, 7], daysAgo: 8), session(80, reps: [7, 7, 7], daysAgo: 4),
                       missed(80, daysAgo: 1, reason: .equipmentBusy)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertEqual(p.stallStreak, 2)
        XCTAssertNil(p.stallAction)
        XCTAssertEqual(p.weight, 80, "carries on from the session before the excused miss")
        XCTAssertEqual(p.lastVerdict, .held)
        XCTAssertTrue(p.reason.hasPrefix("Last session's miss (equipment busy) doesn't count."), p.reason)
    }

    func testAnUnexcusedMissCountsLikeAnyMiss() {
        let history = [session(80, reps: [7, 7, 7], daysAgo: 8), session(80, reps: [7, 7, 7], daysAgo: 4),
                       missed(80, daysAgo: 1, reason: .feltWeak)]
        let p = ProgressionEngine.prescription(history: history, config: config, weeklySetsForPrimaryMuscle: 12)
        XCTAssertEqual(p.stallStreak, 3)
        XCTAssertEqual(p.stallAction, .deload)
        let noReason = [history[0], history[1], missed(80, daysAgo: 1, reason: nil)]
        XCTAssertEqual(ProgressionEngine.prescription(history: noReason, config: config, weeklySetsForPrimaryMuscle: 12).stallStreak, 3)
    }

    func testTwoExcusedMissesInARowDoNotMakeAFailStall() {
        let history = [session(80, reps: [8, 8, 8], daysAgo: 8), missed(82.5, daysAgo: 4, reason: .outOfTime),
                       missed(82.5, daysAgo: 1, reason: .sickOrInjured)]
        let p = ProgressionEngine.prescription(history: history, config: config)
        XCTAssertNil(p.stallAction)
        XCTAssertEqual(p.weight, 82.5, "the increment earned before the two excused sessions still stands")
        XCTAssertEqual(p.lastVerdict, .progressed)
    }

    func testAnnotationShowsTheMissWithItsReasonAndKeepsTheStreak() {
        let history = [session(80, reps: [7, 7, 7], daysAgo: 8), missed(80, daysAgo: 4, reason: .outOfTime),
                       missed(80, daysAgo: 1, reason: .feltWeak)]
        let notes = ProgressionEngine.annotate(history: history, config: config)
        XCTAssertEqual(notes.map(\.verdict), [.held, .failed, .failed])
        XCTAssertEqual(notes.map(\.stallStreak), [1, 1, 2], "the excused miss neither adds nor resets")
        XCTAssertEqual(notes.map(\.isExcused), [false, true, false])
        XCTAssertEqual(notes[1].missReason, .outOfTime)
        XCTAssertEqual(notes[2].missReason, .feltWeak)
    }

    func testAReasonOnACorrectedSessionExcusesNothing() {
        // The miss was corrected to a Held session in the editor; the stale reason must not hide it.
        var corrected = session(80, reps: [7, 7, 7], daysAgo: 1)
        corrected.missReason = .outOfTime
        XCTAssertFalse(ProgressionEngine.isExcused(corrected, config: config))
        let p = ProgressionEngine.prescription(history: [session(80, reps: [7, 7, 7], daysAgo: 4), corrected], config: config)
        XCTAssertEqual(p.stallStreak, 2)
        XCTAssertFalse(p.reason.contains("doesn't count"))
    }

    // MARK: Edges the spec states

    func testSleepThresholdIsStrictlyUnderSixHours() {
        XCTAssertFalse(Readiness(sleepHours: 6.0).isLow(for: chest), "six hours is not under six")
        XCTAssertTrue(Readiness(sleepHours: 5.9).isLow(for: chest))
        XCTAssertFalse(Readiness(sleepHours: nil).isLow(for: chest), "no answer is not a low day")
    }

    func testSorenessCountsOnMusclesWeightedHalfOrMoreOnly() {
        // Bench: chest 1, triceps 0.5. Library benches also carry upper back at 0.25.
        let bench = chest + [MuscleWeight(muscle: .upperBack, weight: 0.25)]
        XCTAssertTrue(Readiness(soreness: [.triceps: 4]).isLow(for: bench), "a 0.5 muscle is a target")
        XCTAssertFalse(Readiness(soreness: [.upperBack: 5]).isLow(for: bench), "a 0.25 muscle is not")
        XCTAssertFalse(Readiness(soreness: [.chest: 3]).isLow(for: bench), "soreness 3 is under the threshold")
        XCTAssertTrue(Readiness(soreness: [.chest: 4]).isLow(for: bench))
    }

    func testStallVolumeBoundaryIsExactlyTenSets() {
        let stalled = [session(80, reps: [7, 7, 7], daysAgo: 7), session(80, reps: [7, 7, 7], daysAgo: 4), session(80, reps: [7, 7, 7], daysAgo: 1)]
        let atTen = ProgressionEngine.prescription(history: stalled, config: config, weeklySetsForPrimaryMuscle: 10)
        XCTAssertEqual(atTen.stallAction, .deload, "ten sets is not under ten")
        XCTAssertEqual(atTen.setCount, config.setCount)
        let underTen = ProgressionEngine.prescription(history: stalled, config: config, weeklySetsForPrimaryMuscle: 9.5)
        XCTAssertEqual(underTen.stallAction, .addSet)
        XCTAssertEqual(underTen.setCount, config.setCount + 1)
        XCTAssertEqual(underTen.weight, 80, "the load is left alone while a set is added")
    }

    func testReadinessChangesTheLoadButNotTheRepTargets() {
        let p = ProgressionEngine.prescription(history: [session(80, reps: [8, 8, 8])], config: config, muscles: chest, readiness: Readiness(sleepHours: 5))
        XCTAssertTrue(p.readinessAdjusted)
        XCTAssertEqual(p.repRangeLow, config.repRangeLow)
        XCTAssertEqual(p.repRangeHigh, config.repRangeHigh)
        XCTAssertEqual(p.setCount, config.setCount)
        XCTAssertEqual(p.rpeCap, config.rpeCap)
    }

    // MARK: First session

    func testNoHistoryUsesStartingWeight() {
        var c = config
        c.startingWeight = 60
        let p = ProgressionEngine.prescription(history: [], config: c)
        XCTAssertEqual(p.weight, 60)
        XCTAssertFalse(p.needsStartingWeight)
    }

    func testNoHistoryNoStartingWeightAsksForOne() {
        let p = ProgressionEngine.prescription(history: [], config: config)
        XCTAssertTrue(p.needsStartingWeight)
    }
}
