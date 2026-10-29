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

    func testPoundLiftersFloorAtTheirBarNotTwentyKilograms() {
        // 50 lb working, 5 lb plates: the one light set would be 30 lb, under the bar, so it is
        // the bar: 45 lb, not 20 kg (44.1 lb, which is not on the plate grid).
        let ramp = WarmupRule.ramp(workingWeight: Units.kg(fromLb: 50), increment: Units.kg(fromLb: 5), metric: false)
        XCTAssertEqual(ramp.count, 1)
        XCTAssertEqual(Units.lb(fromKg: ramp[0].weight), 45, accuracy: 0.001)
        XCTAssertTrue(WarmupRule.ramp(workingWeight: Units.kg(fromLb: 40), increment: Units.kg(fromLb: 5), metric: false).isEmpty,
                      "under an empty bar there is no warm-up")
        // In kilograms the bar is still 20.
        XCTAssertEqual(WarmupRule.ramp(workingWeight: 22.5, increment: 2.5, metric: true).map(\.weight), [20])
    }

    func testNoStepReachesTheWorkingWeight() {
        for weight in stride(from: 20.0, through: 200, by: 2.5) {
            for step in WarmupRule.ramp(workingWeight: weight, increment: 2.5) {
                XCTAssertLessThan(step.weight, weight)
            }
        }
    }
}
