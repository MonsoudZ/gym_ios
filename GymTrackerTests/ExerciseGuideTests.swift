import XCTest
@testable import GymTracker

/// Every library exercise has a guide, every guide is complete, and every movement pattern
/// draws inside its frame.
final class ExerciseGuideTests: XCTestCase {
    func testEveryLibraryExerciseHasAGuideAndNothingElseDoes() {
        let library = Set(ExerciseLibrary.all.map(\.name))
        let guided = Set(ExerciseGuides.all.keys)
        XCTAssertEqual(library.subtracting(guided), [], "library exercises without a guide")
        XCTAssertEqual(guided.subtracting(library), [], "guides for names not in the library")
    }

    func testGuidesAreComplete() {
        for (name, guide) in ExerciseGuides.all {
            XCTAssertFalse(guide.summary.isEmpty, name)
            XCTAssertTrue(guide.summary.hasSuffix("."), "\(name): summary should be sentences")
            XCTAssertFalse(guide.equipment.isEmpty, name)
            XCTAssertTrue((3...5).contains(guide.cues.count), "\(name) has \(guide.cues.count) cues")
            for cue in guide.cues {
                XCTAssertFalse(cue.isEmpty, name)
                XCTAssertTrue(cue.hasSuffix("."), "\(name): cue should be a sentence: \(cue)")
            }
        }
    }

    func testEveryPatternIsUsedAndDrawsInsideItsFrame() {
        let used = Set(ExerciseGuides.all.values.map(\.pattern))
        XCTAssertEqual(used, Set(MovementPattern.allCases), "patterns with no exercise, or exercises with no pattern")
        for pattern in MovementPattern.allCases {
            let frames = pattern.frames
            XCTAssertNotEqual(frames.start, frames.finish, "\(pattern) does not move")
            for (index, pose) in [frames.start, frames.finish].enumerated() {
                for point in pose.joints.all + [pose.hip] {
                    XCTAssertTrue((-3...103).contains(point.x) && (-3...103).contains(point.y),
                                  "\(pattern) frame \(index + 1) draws outside the square at \(point)")
                }
            }
        }
    }

    func testFigureGeometryFollowsTheAngleConvention() {
        // Standing straight: shoulder above the hip, knee and ankle below, arm hanging.
        let standing = FigurePose(hip: CGPoint(x: 50, y: 50), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180)
        let j = standing.joints
        XCTAssertEqual(j.shoulder.x, 50, accuracy: 0.001)
        XCTAssertEqual(j.shoulder.y, 50 - FigurePose.torsoLength, accuracy: 0.001)
        XCTAssertEqual(j.ankle.y, 50 + FigurePose.thighLength + FigurePose.shinLength, accuracy: 0.001)
        XCTAssertEqual(j.hand.y, j.shoulder.y + FigurePose.upperArmLength + FigurePose.forearmLength, accuracy: 0.001)
        // 90 is forward: lying with the head to the right.
        let lying = FigurePose(hip: CGPoint(x: 40, y: 60), torso: 90, thigh: 270, shin: 270, arm: 0, forearm: 0)
        XCTAssertEqual(lying.joints.shoulder.x, 62, accuracy: 0.001)
        XCTAssertEqual(lying.joints.knee.x, 22, accuracy: 0.001)
        XCTAssertEqual(lying.joints.hand.y, 60 - 25, accuracy: 0.001)
        // Shrug raises the shoulder without moving the torso angle.
        var shrug = standing
        shrug.props = [.shrugUp]
        XCTAssertLessThan(shrug.joints.shoulder.y, j.shoulder.y)
    }

    func testEveryPatternHasAnAccessibilityDescription() {
        for pattern in MovementPattern.allCases {
            XCTAssertFalse(pattern.accessibilityDescription.isEmpty, "\(pattern)")
        }
    }
}
