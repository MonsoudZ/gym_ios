import XCTest
import SwiftUI
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
        shrug.shoulderLift = 4
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

    // MARK: Body figure

    /// Every muscle has a region on the plates, and every region sits on the drawn figure
    /// (sampled against the plate's alpha) without covering more than a modest share of it.
    @MainActor
    func testEveryMuscleRegionSitsOnThePlate() throws {
        var covered: Set<Muscle> = []
        for side in BodyFigure.Side.allCases {
            let plate = try XCTUnwrap(UIImage(named: side.assetName)?.cgImage, "\(side) plate missing from the asset catalogue")
            let width = plate.width, height = plate.height
            XCTAssertEqual(CGSize(width: width, height: height), side.imageSize, "\(side) regions are traced in the wrong pixel space")
            var alpha = [UInt8](repeating: 0, count: width * height)
            let context = try XCTUnwrap(CGContext(data: &alpha, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue))
            context.draw(plate, in: CGRect(x: 0, y: 0, width: width, height: height))
            func opaque(_ point: CGPoint) -> Bool {
                // Row 0 of a bitmap context's buffer is the top of the drawn image.
                let x = Int(point.x), y = Int(point.y)
                guard x >= 0, y >= 0, x < width, y < height else { return false }
                return alpha[y * width + x] > 128
            }
            let plateArea = Double(width * height)
            for region in BodyFigure.regions(side) {
                covered.insert(region.muscle)
                let rect = region.path.boundingRect
                var inside = 0, onFigure = 0
                let steps = 14
                for i in 0..<steps {
                    for j in 0..<steps {
                        let point = CGPoint(x: rect.minX + rect.width * (Double(i) + 0.5) / Double(steps),
                                            y: rect.minY + rect.height * (Double(j) + 0.5) / Double(steps))
                        guard region.path.contains(point) else { continue }
                        inside += 1
                        if opaque(point) { onFigure += 1 }
                    }
                }
                XCTAssertGreaterThan(inside, 0, "\(side) \(region.muscle) has no area")
                XCTAssertGreaterThanOrEqual(Double(onFigure), Double(inside) * 0.85, "\(side) \(region.muscle) hangs off the figure at \(rect)")
                let area = rect.width * rect.height * Double(inside) / Double(steps * steps)
                XCTAssertLessThan(area, plateArea / 10, "\(side) \(region.muscle) covers too much of the figure")
            }
        }
        XCTAssertEqual(covered, Set(Muscle.allCases), "muscles with no region on either side")
    }

    // MARK: Keyframes, callouts and implements

    func testEveryPatternHasThreeDistinctPosesThatStayInsideTheFrame() {
        for pattern in MovementPattern.allCases {
            let keyframes = pattern.keyframes
            XCTAssertEqual(keyframes.count, 3, "\(pattern)")
            XCTAssertNotEqual(keyframes[0].joints, keyframes[1].joints, "\(pattern): midpoint equals the start")
            XCTAssertNotEqual(keyframes[1].joints, keyframes[2].joints, "\(pattern): midpoint equals the finish")
            XCTAssertNotEqual(keyframes[0].joints, keyframes[2].joints, "\(pattern) does not move")
            for step in 0...8 {
                let pose = FigurePose.along(keyframes, Double(step) / 8)
                for point in pose.joints.everything + [pose.hip] {
                    XCTAssertTrue((-6...106).contains(point.x) && (-6...106).contains(point.y),
                                  "\(pattern) leaves the frame at step \(step), \(point)")
                }
            }
        }
    }

    func testTheLoopHoldsAtEachEndAndEasesBetween() {
        XCTAssertEqual(MovementLoop.liftFraction(at: 0), 0)
        XCTAssertEqual(MovementLoop.liftFraction(at: 0.1), 0)
        XCTAssertEqual(MovementLoop.liftFraction(at: 0.31), 0.5, accuracy: 0.001)
        XCTAssertEqual(MovementLoop.liftFraction(at: 0.55), 1)
        XCTAssertEqual(MovementLoop.liftFraction(at: 0.81), 0.5, accuracy: 0.001)
        XCTAssertEqual(MovementLoop.liftFraction(at: 0.999), 0, accuracy: 0.001)
        XCTAssertEqual(MovementLoop.liftFraction(at: 1.31), 0.5, accuracy: 0.001, "wraps")
        // Four cues: one per quarter of the loop.
        XCTAssertEqual((0..<8).map { MovementLoop.step(at: Double($0) / 8, count: 4) }, [0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(MovementLoop.step(at: 0.999, count: 3), 2)
        XCTAssertEqual(MovementLoop.step(at: 0.3, count: 0), 0)
        // The figure at the ends of the lift is exactly the start and finish keyframes.
        let squat = MovementPattern.squat.keyframes
        XCTAssertEqual(FigurePose.along(squat, 0).joints, squat[0].joints)
        XCTAssertEqual(FigurePose.along(squat, 1).joints, squat[2].joints)
    }

    func testPhasesCoverTheLoopAndFadeAtTheirEdges() {
        XCTAssertEqual(MovementPhase.setup.opacity(at: 0.05), 1)
        XCTAssertEqual(MovementPhase.setup.opacity(at: 0.4), 0)
        XCTAssertEqual(MovementPhase.lift.opacity(at: 0.3), 1)
        XCTAssertEqual(MovementPhase.top.opacity(at: 0.55), 1)
        XCTAssertEqual(MovementPhase.lower.opacity(at: 0.8), 1)
        XCTAssertEqual(MovementPhase.always.opacity(at: 0.8), 1)
        let fading = MovementPhase.setup.opacity(at: MovementLoop.holdStart + 0.03 + 0.025)
        XCTAssertTrue(fading > 0 && fading < 1, "half way through the fade: \(fading)")
        for p in stride(from: 0.0, through: 1.0, by: 0.05) {
            let covered = [MovementPhase.setup, .lift, .top, .lower].contains { $0.opacity(at: p) > 0.99 }
            XCTAssertTrue(covered, "no phase is fully on at \(p)")
        }
    }

    func testEveryPatternHasCalloutsThatAreSentencesOnJoints() {
        for pattern in MovementPattern.allCases {
            let callouts = pattern.callouts
            XCTAssertTrue((2...4).contains(callouts.count), "\(pattern) has \(callouts.count) callouts")
            for callout in callouts {
                XCTAssertFalse(callout.text.isEmpty)
                XCTAssertLessThanOrEqual(callout.text.count, 34, "\(pattern): callout too long to fit beside the figure: \(callout.text)")
                let point = callout.point(in: pattern.keyframes[0])
                XCTAssertTrue((-6...106).contains(point.x) && (-6...106).contains(point.y), "\(pattern) callout off the frame")
            }
            XCTAssertEqual(Set(callouts.map(\.text)).count, callouts.count, "\(pattern) repeats a callout")
        }
    }

    func testEveryExerciseResolvesToAnImplementAndADiagram() {
        for (name, guide) in ExerciseGuides.all {
            let keyframes = guide.pattern.keyframes(for: guide.implement)
            XCTAssertEqual(keyframes.count, 3, name)
            let loads = keyframes[0].props.filter(\.isLoad)
            XCTAssertLessThanOrEqual(loads.count, 1, "\(name) holds two things")
            XCTAssertFalse(keyframes[0].props.contains(.plate) && keyframes[0].props.contains(.dumbbell), name)
        }
        func props(_ name: String) -> [FigureProp] { let g = ExerciseGuides.guide(for: name)!; return g.pattern.keyframes(for: g.implement)[0].props }
        func hasCable(_ p: [FigureProp]) -> Bool { p.contains { if case .cable = $0 { return true } else { return false } } }
        XCTAssertEqual(ExerciseGuides.guide(for: "Barbell Row")?.implement, .barbell)
        XCTAssertEqual(ExerciseGuides.guide(for: "Dumbbell Row")?.implement, .dumbbell)
        XCTAssertTrue(props("Barbell Row").contains(.plate) && !props("Barbell Row").contains(.dumbbell))
        XCTAssertTrue(props("Dumbbell Row").contains(.dumbbell) && !props("Dumbbell Row").contains(.plate))
        XCTAssertEqual(ExerciseGuides.guide(for: "Cable Curl")?.implement, .cable)
        XCTAssertTrue(hasCable(props("Cable Curl")) && props("Cable Curl").contains(.plateSmall))
        XCTAssertFalse(hasCable(props("Barbell Curl")))
        XCTAssertEqual(ExerciseGuides.guide(for: "Kettlebell Swing")?.implement, .kettlebell)
        XCTAssertTrue(props("Kettlebell Swing").contains(.kettlebell))
        XCTAssertEqual(ExerciseGuides.guide(for: "Smith Machine Squat")?.implement, .smith)
        XCTAssertTrue(props("Smith Machine Squat").contains(.rails))
        XCTAssertEqual(ExerciseGuides.guide(for: "Pull-Up")?.implement, .bodyweight)
        XCTAssertTrue(props("Pull-Up").filter(\.isLoad).isEmpty)
        XCTAssertEqual(ExerciseGuides.guide(for: "Lat Pulldown")?.pattern, .latPulldown)
        XCTAssertEqual(ExerciseGuides.guide(for: "Lat Pulldown")?.implement, .machine)
        XCTAssertTrue(hasCable(props("Lat Pulldown")), "a pulldown keeps the machine's cable")
        XCTAssertEqual(ExerciseGuides.guide(for: "Leg Press")?.implement, .machine)
        XCTAssertTrue(props("Leg Press").filter(\.isLoad).isEmpty)
        XCTAssertEqual(ExerciseGuides.guide(for: "Preacher Curl")?.implement, .ezBar, "the first implement named wins")
        XCTAssertEqual(ExerciseGuides.guide(for: "Back Extension")?.implement, .bodyweight)
        XCTAssertEqual(Implement.from(equipment: "Trap bar"), .trapBar)
        XCTAssertEqual(Implement.from(equipment: "Dumbbells, bench"), .dumbbell)
    }
}
