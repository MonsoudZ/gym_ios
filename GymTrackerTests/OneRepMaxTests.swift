import XCTest
@testable import GymTracker

final class OneRepMaxTests: XCTestCase {
    func testEpleyFormula() {
        XCTAssertEqual(OneRepMax.epley(weight: 100, reps: 5)!, 116.67, accuracy: 0.01)
    }

    func testSingleRepIsTheWeight() {
        XCTAssertEqual(OneRepMax.epley(weight: 140, reps: 1), 140)
    }

    func testHighRepSetsAreNotTrusted() {
        XCTAssertNil(OneRepMax.epley(weight: 60, reps: 12))
        XCTAssertNotNil(OneRepMax.epley(weight: 60, reps: 10))
    }

    func testBestIgnoresWarmups() {
        let sets = [
            LoggedSet(weight: 200, reps: 1, isWarmup: true),
            LoggedSet(weight: 100, reps: 8),
            LoggedSet(weight: 100, reps: 6),
        ]
        XCTAssertEqual(OneRepMax.best(from: sets)!, 100 * (1 + 8.0 / 30), accuracy: 0.001)
    }
}
