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
