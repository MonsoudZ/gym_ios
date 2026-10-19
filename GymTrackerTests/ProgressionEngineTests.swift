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
