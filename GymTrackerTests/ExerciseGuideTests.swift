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

    // MARK: Muscle grading

    func testEveryLibraryExerciseHasAPrimaryMoverAndEachMuscleInOneTier() {
        for spec in ExerciseLibrary.all {
            let tiers = spec.muscles.byInvolvement
            XCTAssertFalse(tiers[.primary, default: []].isEmpty, "\(spec.name) has no primary mover")
            let listed = spec.muscles.map(\.muscle)
            XCTAssertEqual(Set(listed).count, listed.count, "\(spec.name) grades a muscle twice")
            for mw in spec.muscles {
                XCTAssertNotNil(mw.involvement, "\(spec.name): \(mw.muscle) weight \(mw.weight) is in no tier")
                XCTAssertEqual(mw.weight, mw.involvement?.weight, "\(spec.name): \(mw.muscle) weight is not a tier's weight")
            }
        }
        let graded = ExerciseLibrary.all.filter { !$0.muscles.byInvolvement[.stabiliser, default: []].isEmpty }.count
        XCTAssertGreaterThanOrEqual(graded, 80, "most exercises name a stabiliser; \(graded) do")
    }

    func testTiersFollowTheStoredWeight() {
        XCTAssertEqual(MuscleInvolvement(weight: 1), .primary)
        XCTAssertEqual(MuscleInvolvement(weight: 0.5), .secondary)
        XCTAssertEqual(MuscleInvolvement(weight: 0.25), .stabiliser)
        XCTAssertEqual(MuscleInvolvement(weight: 0.75), .secondary, "anything between the tiers rounds down")
        XCTAssertNil(MuscleInvolvement(weight: 0))
        XCTAssertTrue(MuscleInvolvement.primary < .secondary && .secondary < .stabiliser)
        XCTAssertEqual(MuscleWeight(muscle: .abs, involvement: .stabiliser).weight, 0.25)
    }

    func testInvolvementSummaryListsTiersInOrder() {
        let squat = ExerciseLibrary.spec("Back Squat")!.muscles
        XCTAssertEqual(squat.involvementSummary, "Primary movers: Quads, Glutes. Secondary: Lower back. Stabilisers: Abs, Hamstrings, Calves.")
        XCTAssertEqual([MuscleWeight]().involvementSummary, "No muscles set")
        // A muscle listed twice keeps its highest tier.
        let twice = [MuscleWeight(muscle: .chest, weight: 0.25), MuscleWeight(muscle: .chest, weight: 1)]
        XCTAssertEqual(twice.byInvolvement, [.primary: [.chest]])
    }

    // MARK: Motion

    func testTurnTakesTheShortWayRound() {
        XCTAssertEqual(FigurePose.turn(from: 275, to: 30), 115, accuracy: 0.001)
        XCTAssertEqual(FigurePose.turn(from: 180, to: 90), -90, accuracy: 0.001)
        XCTAssertEqual(FigurePose.turn(from: 350, to: 10), 20, accuracy: 0.001)
        XCTAssertEqual(FigurePose.turn(from: 10, to: 350), -20, accuracy: 0.001)
    }

    func testInterpolationMeetsBothFramesAndStaysInside() {
        for pattern in MovementPattern.allCases {
            let frames = pattern.frames
            assertSamePose(frames.start.interpolated(to: frames.finish, 0), frames.start, "\(pattern) at 0")
            assertSamePose(frames.start.interpolated(to: frames.finish, 1), frames.finish, "\(pattern) at 1")
            for step in 1..<8 {
                let pose = frames.start.interpolated(to: frames.finish, Double(step) / 8)
                for point in pose.joints.all + [pose.hip] {
                    XCTAssertTrue((-8...108).contains(point.x) && (-8...108).contains(point.y),
                                  "\(pattern) leaves the square part way through, at \(point)")
                }
            }
        }
    }

    private func assertSamePose(_ a: FigurePose, _ b: FigurePose, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        for (p, q) in zip(a.joints.all + [a.hip], b.joints.all + [b.hip]) {
            XCTAssertEqual(p.x, q.x, accuracy: 0.001, message, file: file, line: line)
            XCTAssertEqual(p.y, q.y, accuracy: 0.001, message, file: file, line: line)
        }
    }

    func testEveryPatternHasAPathAndSomethingThatMoves() {
        for pattern in MovementPattern.allCases {
            let motion = pattern.motion
            XCTAssertGreaterThanOrEqual(motion.path.count, 2, "\(pattern)")
            let travel = MovementMotion.distance(motion.path.first!, motion.path.last!)
            XCTAssertGreaterThanOrEqual(travel, 3, "\(pattern): the \(motion.anchor) barely moves")
            XCTAssertFalse(motion.turns.isEmpty && motion.shifts.isEmpty, "\(pattern) has no arrow to draw")
            for point in motion.path + motion.turns.flatMap(\.points) {
                XCTAssertTrue((-8...108).contains(point.x) && (-8...108).contains(point.y), "\(pattern) draws a mark outside the square at \(point)")
            }
            XCTAssertFalse(pattern.pathDescription.isEmpty)
        }
    }

    func testMotionPicksTheLoadWhenHeldAndTheMovingLimbOtherwise() {
        XCTAssertEqual(MovementPattern.benchPress.motion.anchor, .hand)
        XCTAssertEqual(MovementPattern.squat.motion.anchor, .hand, "the bar, not the hips")
        XCTAssertEqual(MovementPattern.verticalPull.motion.anchor, .hip, "the body rises to a fixed bar")
        XCTAssertEqual(MovementPattern.legExtension.motion.anchor, .ankle)
        // A curl turns only the elbow; a squat turns the torso and the thigh at the hip (the shin
        // stays near vertical) and the hips shift up and forward.
        XCTAssertEqual(MovementPattern.curl.motion.turns.map(\.joint), ["elbow"])
        XCTAssertEqual(Set(MovementPattern.squat.motion.turns.map(\.joint)), ["torso", "hip"])
        XCTAssertEqual(MovementPattern.squat.motion.shifts.map(\.point), ["hips"])
        // The curl's hand follows an arc around the elbow, so the path bows out past the straight line.
        let curl = MovementPattern.curl.motion.path
        let mid = curl[curl.count / 2]
        let chord = CGPoint(x: (curl.first!.x + curl.last!.x) / 2, y: (curl.first!.y + curl.last!.y) / 2)
        XCTAssertGreaterThan(MovementMotion.distance(mid, chord), 2)
        // The shrug has no joint turn: the shoulders shift straight up.
        XCTAssertEqual(MovementPattern.shrug.motion.shifts.map(\.point), ["shoulders"])
        XCTAssertLessThan(MovementPattern.shrug.motion.path.last!.y, MovementPattern.shrug.motion.path.first!.y)
    }
}
