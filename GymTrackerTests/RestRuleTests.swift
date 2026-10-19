import XCTest
@testable import GymTracker

final class RestRuleTests: XCTestCase {
    func testHeavyRepRangesGetThreeMinutes() {
        XCTAssertEqual(RestRule.defaultSeconds(repRangeHigh: 5), 180)
        XCTAssertEqual(RestRule.defaultSeconds(repRangeHigh: 8), 180)
        XCTAssertEqual(RestRule.defaultSeconds(repRangeHigh: 10), 180)
    }

    func testHigherRepRangesGetTwoMinutes() {
        XCTAssertEqual(RestRule.defaultSeconds(repRangeHigh: 12), 120)
        XCTAssertEqual(RestRule.defaultSeconds(repRangeHigh: 20), 120)
    }

    func testClampKeepsRestWithinBounds() {
        XCTAssertEqual(RestRule.clamp(5), 30)
        XCTAssertEqual(RestRule.clamp(180), 180)
        XCTAssertEqual(RestRule.clamp(10_000), 600)
    }

    func testLabelIsMinutesAndZeroPaddedSeconds() {
        XCTAssertEqual(RestRule.label(180), "3:00")
        XCTAssertEqual(RestRule.label(45), "0:45")
        XCTAssertEqual(RestRule.label(750), "12:30")
        XCTAssertEqual(RestRule.label(-3), "0:00")
    }

    @MainActor
    func testLibraryExercisesGetRestFromTheirRepRange() {
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)   // 6–8
        let raise = Exercise(spec: ExerciseLibrary.spec("Lateral Raise")!)         // 12–20
        XCTAssertEqual(bench.restSeconds, 180)
        XCTAssertEqual(raise.restSeconds, 120)
        XCTAssertEqual(Exercise(name: "Cable Fly", metric: false).restSeconds, 120)   // 8–12 default
    }
}
