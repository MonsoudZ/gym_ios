import XCTest
@testable import GymTracker

final class VolumeTrackerTests: XCTestCase {
    func testWeightedSetsSumPerMuscle() {
        let bench = [MuscleWeight(muscle: .chest, weight: 1), MuscleWeight(muscle: .triceps, weight: 0.5)]
        let sets = Array(repeating: VolumeSet(muscles: bench), count: 4) + [VolumeSet(muscles: bench, isWarmup: true)]
        let volume = VolumeTracker.weeklyVolume(sets)
        XCTAssertEqual(volume[.chest], 4)
        XCTAssertEqual(volume[.triceps], 2)
        XCTAssertNil(volume[.lats])
    }

    func testBands() {
        XCTAssertEqual(VolumeTracker.band(9), .low)
        XCTAssertEqual(VolumeTracker.band(10), .ok)
        XCTAssertEqual(VolumeTracker.band(20), .ok)
        XCTAssertEqual(VolumeTracker.band(21), .high)
    }
}
