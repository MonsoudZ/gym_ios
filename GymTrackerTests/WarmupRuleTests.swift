import XCTest
@testable import GymTracker

final class WarmupRuleTests: XCTestCase {
    func testRampIsHalfSeventyNinetyRoundedToIncrement() {
        let ramp = WarmupRule.ramp(workingWeight: 100, increment: 2.5)
        XCTAssertEqual(ramp.map(\.weight), [50, 70, 90])
        XCTAssertEqual(ramp.map(\.reps), [8, 5, 2])
    }

    func testRampRoundsToPlateStepsAndDropsCollisions() {
        // 22.5 kg working: 11.25 → 20 (floor), 15.75 → 20 (collides, dropped), 20.25 → 20 (dropped).
        let ramp = WarmupRule.ramp(workingWeight: 22.5, increment: 2.5)
        XCTAssertEqual(ramp.map(\.weight), [20])
        XCTAssertEqual(ramp.first?.reps, 6)
    }

    func testLightWorkingWeightGetsOneWarmupOrNone() {
        XCTAssertEqual(WarmupRule.ramp(workingWeight: 30, increment: 2.5).count, 1)
        XCTAssertTrue(WarmupRule.ramp(workingWeight: 15, increment: 1).isEmpty)
    }

    func testNoStepReachesTheWorkingWeight() {
        for weight in stride(from: 20.0, through: 200, by: 2.5) {
            for step in WarmupRule.ramp(workingWeight: weight, increment: 2.5) {
                XCTAssertLessThan(step.weight, weight)
            }
        }
    }
}
