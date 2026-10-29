import XCTest
@testable import GymTracker

final class SetStepRuleTests: XCTestCase {
    func testWeightStepsByThePlateIncrementAndSnapsToItsGrid() {
        XCTAssertEqual(SetStepRule.weight(185, step: 5, direction: .up, start: 0), 190)
        XCTAssertEqual(SetStepRule.weight(185, step: 5, direction: .down, start: 0), 180)
        XCTAssertEqual(SetStepRule.weight(187, step: 5, direction: .up, start: 0), 190, "a typed odd weight snaps up")
        XCTAssertEqual(SetStepRule.weight(187, step: 5, direction: .down, start: 0), 185, "and down")
        XCTAssertEqual(SetStepRule.weight(82.5, step: 2.5, direction: .up, start: 0), 85)
        XCTAssertEqual(SetStepRule.weight(20, step: 2, direction: .down, start: 0), 18)
    }

    func testPoundWeightsStepAfterTheKilogramRoundTrip() {
        // Pound loads are stored in kilograms; the display value comes back a few ulps off the
        // grid (75.00000000000001, 154.99999999999997) and the buttons must still move.
        for lb in [75.0, 95.0, 135.0, 155.0, 310.0, 395.0] {
            let display = Units.display(Units.kg(fromLb: lb), metric: false)
            XCTAssertEqual(SetStepRule.weight(display, step: 5, direction: .up, start: 0), lb + 5, "\(lb) lb +")
            XCTAssertEqual(SetStepRule.weight(display, step: 5, direction: .down, start: 0), lb - 5, "\(lb) lb −")
        }
        let display = Units.display(Units.kg(fromLb: 77.5), metric: false)
        XCTAssertEqual(SetStepRule.weight(display, step: 2.5, direction: .up, start: 0), 80)
        XCTAssertEqual(SetStepRule.weight(display, step: 2.5, direction: .down, start: 0), 75)
    }

    func testWeightUpFromEmptyStartsAtTheSuggestionSnapped() {
        XCTAssertEqual(SetStepRule.weight(nil, step: 5, direction: .up, start: 187.4), 185)
        XCTAssertEqual(SetStepRule.weight(0, step: 2.5, direction: .up, start: 80), 80)
        XCTAssertEqual(SetStepRule.weight(nil, step: 5, direction: .up, start: 0), 5, "no history: one plate step")
        XCTAssertNil(SetStepRule.weight(nil, step: 5, direction: .down, start: 100), "down from empty stays empty")
    }

    func testWeightDownToZeroClearsTheField() {
        XCTAssertNil(SetStepRule.weight(5, step: 5, direction: .down, start: 0))
        XCTAssertNil(SetStepRule.weight(3, step: 5, direction: .down, start: 0))
    }

    func testRepsStepByOneAndStartAtTheSuggestion() {
        XCTAssertEqual(SetStepRule.reps(8, direction: .up, start: 0), 9)
        XCTAssertEqual(SetStepRule.reps(8, direction: .down, start: 0), 7)
        XCTAssertEqual(SetStepRule.reps(nil, direction: .up, start: 12), 12)
        XCTAssertEqual(SetStepRule.reps(nil, direction: .up, start: 0), 1)
        XCTAssertNil(SetStepRule.reps(nil, direction: .down, start: 12))
        XCTAssertNil(SetStepRule.reps(1, direction: .down, start: 12))
    }
}
