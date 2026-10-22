import Foundation

// MARK: - Keyframes and the loop

nonisolated extension FigurePose {
    /// The pose at `t` in 0...1 along a run of keyframes, interpolating piecewise.
    static func along(_ keyframes: [FigurePose], _ t: Double) -> FigurePose {
        guard keyframes.count > 1 else { return keyframes[0] }
        let clamped = min(max(t, 0), 1)
        let segments = Double(keyframes.count - 1)
        let index = min(Int(clamped * segments), keyframes.count - 2)
        let local = clamped * segments - Double(index)
        return keyframes[index].interpolated(to: keyframes[index + 1], local)
    }
}

/// The diagram loops: hold the start, lift to the finish, hold, lower back. Progress is 0...1
/// over one loop; the lift fraction is 0...1 along the keyframes.
nonisolated enum MovementLoop {
    static let period: TimeInterval = 5.2
    static let holdStart = 0.12
    static let liftEnd = 0.5
    static let holdTop = 0.62

    static func progress(at date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return t / period
    }

    /// Ease in and out, so the figure settles at each end instead of bouncing.
    static func smooth(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// Where along the keyframes the figure is, 0 at the start pose and 1 at the finish.
    static func liftFraction(at progress: Double) -> Double {
        let p = progress - floor(progress)
        if p < holdStart { return 0 }
        if p < liftEnd { return smooth((p - holdStart) / (liftEnd - holdStart)) }
        if p < holdTop { return 1 }
        return 1 - smooth((p - holdTop) / (1 - holdTop))
    }

    /// The cue to highlight: the cues are read in order over one loop.
    static func step(at progress: Double, count: Int) -> Int {
        guard count > 0 else { return 0 }
        let p = progress - floor(progress)
        return min(count - 1, Int(p * Double(count)))
    }
}

/// When in the loop a callout applies.
nonisolated enum MovementPhase: Hashable, Sendable {
    case setup, lift, top, lower, always

    var range: ClosedRange<Double> {
        switch self {
        case .setup: 0...MovementLoop.holdStart + 0.03
        case .lift: MovementLoop.holdStart...MovementLoop.liftEnd
        case .top: MovementLoop.liftEnd - 0.02...MovementLoop.holdTop + 0.03
        case .lower: MovementLoop.holdTop...1
        case .always: 0...1
        }
    }

    /// 1 inside the phase, fading over a short margin either side.
    func opacity(at progress: Double) -> Double {
        if self == .always { return 1 }
        let p = progress - floor(progress)
        let margin = 0.05
        let r = range
        if p < r.lowerBound - margin || p > r.upperBound + margin { return 0 }
        if p < r.lowerBound { return (p - (r.lowerBound - margin)) / margin }
        if p > r.upperBound { return ((r.upperBound + margin) - p) / margin }
        return 1
    }
}

/// A short coaching note pinned to a joint during part of the loop.
nonisolated struct Callout: Hashable, Sendable {
    nonisolated enum Anchor: Hashable, Sendable { case hip, knee, ankle, shoulder, elbow, hand, head, torso }
    nonisolated enum Placement: Hashable, Sendable { case left, right, above, below }

    var text: String
    var anchor: Anchor
    var phase: MovementPhase
    var placement: Placement

    init(_ text: String, at anchor: Anchor, _ phase: MovementPhase, _ placement: Placement) {
        self.text = text
        self.anchor = anchor
        self.phase = phase
        self.placement = placement
    }

    func point(in pose: FigurePose) -> CGPoint {
        let j = pose.joints
        switch anchor {
        case .hip: return pose.hip
        case .knee: return j.knee
        case .ankle: return j.ankle
        case .shoulder: return j.shoulder
        case .elbow: return j.elbow
        case .hand: return j.hand
        case .head: return j.head
        case .torso: return CGPoint(x: (pose.hip.x + j.shoulder.x) / 2, y: (pose.hip.y + j.shoulder.y) / 2)
        }
    }
}

// MARK: - Implements

/// What the lifter holds, read from the guide's equipment line. It swaps the load drawn in the
/// figure's hands so a dumbbell row does not look like a barbell row.
nonisolated enum Implement: String, CaseIterable, Hashable, Sendable {
    case barbell, ezBar, trapBar, smith, dumbbell, kettlebell, cable, machine, bodyweight

    /// The first implement named in an equipment line wins; nothing named means bodyweight.
    static func from(equipment: String) -> Implement {
        let text = equipment.lowercased()
        let keywords: [(String, Implement)] = [
            ("smith machine", .smith), ("trap bar", .trapBar), ("ez-bar", .ezBar), ("barbell", .barbell),
            ("dumbbell", .dumbbell), ("kettlebell", .kettlebell), ("cable", .cable),
            ("machine", .machine), ("station", .machine), ("deck", .machine), ("landmine", .machine),
        ]
        var best: (Int, Implement)? = nil
        for (word, implement) in keywords {
            guard let range = text.range(of: word) else { continue }
            let at = text.distance(from: text.startIndex, to: range.lowerBound)
            if best == nil || at < best!.0 { best = (at, implement) }
        }
        return best?.1 ?? .bodyweight
    }

    /// The pattern's props with the load in the hands replaced by this implement's.
    func apply(to props: [FigureProp], pattern: MovementPattern) -> [FigureProp] {
        let hadLoad = props.contains { $0.isLoad }
        var out = props.filter { !$0.isLoad }
        let hasCable = props.contains { if case .cable = $0 { return true } else { return false } }
        switch self {
        case .barbell, .ezBar, .trapBar:
            out.append(.plate)
        case .smith:
            out.append(.rails)
            out.append(.plate)
        case .dumbbell:
            out.append(.dumbbell)
        case .kettlebell:
            out.append(.kettlebell)
        case .cable:
            if !hasCable { out.append(pattern.cableAnchor) }
            out.append(.plateSmall)
        case .machine:
            if hadLoad { out.append(.handle) }
        case .bodyweight:
            out.removeAll { if case .cable = $0 { return true } else { return false } }
        }
        return out
    }
}

nonisolated extension ExerciseGuide {
    var implement: Implement { Implement.from(equipment: equipment) }
}

// MARK: - Per-pattern data

nonisolated extension MovementPattern {
    /// Start, midpoint and finish of the lifting phase. Most midpoints are the halfway
    /// interpolation; the big lifts have a hand-set one so the bar path bends the right way.
    var keyframes: [FigurePose] {
        let f = frames
        return [f.start, midpoint ?? f.start.interpolated(to: f.finish, 0.5), f.finish]
    }

    /// The keyframes with the load in the hands swapped for the exercise's implement.
    func keyframes(for implement: Implement) -> [FigurePose] {
        keyframes.map { pose in
            var p = pose
            p.props = implement.apply(to: pose.props, pattern: self)
            return p
        }
    }

    private var midpoint: FigurePose? {
        let f = frames
        switch self {
        case .squat:
            // Hips rise first; the torso stays inclined until the knees are nearly straight.
            return FigurePose(hip: CGPoint(x: 41, y: 61), torso: 26, thigh: 132, shin: 186, arm: 300, forearm: 20, props: f.start.props)
        case .frontSquat:
            return FigurePose(hip: CGPoint(x: 44, y: 61), torso: 8, thigh: 136, shin: 186, arm: 100, forearm: 0, props: f.start.props)
        case .deadlift:
            // Bar at the knees: the knees have straightened, the back angle has barely changed.
            return FigurePose(hip: CGPoint(x: 38, y: 60), torso: 48, thigh: 160, shin: 180, arm: 168, forearm: 168, props: f.start.props)
        case .hinge:
            return FigurePose(hip: CGPoint(x: 43, y: 57), torso: 40, thigh: 178, shin: 180, arm: 170, forearm: 170, props: f.start.props)
        case .benchPress:
            // The bar drifts back over the shoulders as it rises.
            return FigurePose(hip: f.start.hip, torso: 90, thigh: 230, shin: 180, arm: 290, forearm: 345, props: f.start.props)
        case .overheadPress:
            // Lean back a touch to clear the chin, then bring the head through.
            return FigurePose(hip: f.start.hip, torso: 354, thigh: 180, shin: 180, arm: 80, forearm: 356, props: f.start.props)
        case .seatedPress:
            return FigurePose(hip: f.start.hip, torso: 0, thigh: 90, shin: 180, arm: 80, forearm: 356, props: f.start.props)
        case .legPress:
            return FigurePose(hip: f.start.hip, torso: 315, thigh: 50, shin: 86, arm: 90, forearm: 150, props: f.start.props)
        default:
            return nil
        }
    }

    /// Where a cable comes from when a cable exercise uses a pattern drawn without one.
    var cableAnchor: FigureProp {
        switch self {
        case .lateralRaise, .hinge, .frontRaise: .cable(x: 6, y: 88)
        case .overheadExtension: .cable(x: 8, y: 10)
        case .rearDeltFly, .facePull, .uprightRow: .cable(x: 95, y: 30)
        default: .cable(x: 94, y: 88)
        }
    }

    /// The coaching notes drawn beside the figure, each during its phase of the loop.
    var callouts: [Callout] {
        switch self {
        case .benchPress:
            [Callout("Bar to the lower chest", at: .hand, .setup, .above),
             Callout("Elbows about 45° out", at: .elbow, .lift, .below),
             Callout("Lock out over the shoulders", at: .hand, .top, .above)]
        case .inclinePress:
            [Callout("Bench at 30–45°", at: .torso, .setup, .left),
             Callout("Press up and slightly in", at: .hand, .lift, .right)]
        case .overheadPress:
            [Callout("Brace, glutes tight", at: .hip, .setup, .left),
             Callout("Bar close to the face", at: .hand, .lift, .right),
             Callout("Head through at the top", at: .head, .top, .left)]
        case .seatedPress:
            [Callout("Back on the pad", at: .torso, .setup, .left),
             Callout("Elbows under the wrists", at: .elbow, .lift, .right),
             Callout("Lock out overhead", at: .hand, .top, .left)]
        case .machineChestPress:
            [Callout("Handles at mid-chest", at: .hand, .setup, .above),
             Callout("Shoulders back on the pad", at: .shoulder, .always, .left),
             Callout("Press to a full reach", at: .hand, .top, .above)]
        case .dip:
            [Callout("Lean forward a little", at: .torso, .setup, .left),
             Callout("Upper arms to parallel", at: .elbow, .setup, .right),
             Callout("Press to lockout", at: .hand, .top, .right)]
        case .pushUp:
            [Callout("Body in one line", at: .hip, .always, .above),
             Callout("Chest to the floor", at: .shoulder, .setup, .above)]
        case .fly:
            [Callout("Slight elbow bend, held", at: .elbow, .always, .above),
             Callout("Squeeze at the centre", at: .hand, .top, .right)]
        case .bentRow:
            [Callout("Hinge, spine neutral", at: .torso, .always, .above),
             Callout("Pull to the lower ribs", at: .hand, .lift, .below),
             Callout("Elbows past the torso", at: .elbow, .top, .left)]
        case .supportedRow:
            [Callout("Chest on the pad", at: .torso, .always, .above),
             Callout("Drive the elbows back", at: .elbow, .lift, .above)]
        case .verticalPull:
            [Callout("Hang from the shoulders", at: .shoulder, .setup, .left),
             Callout("Chest to the bar", at: .head, .top, .left)]
        case .latPulldown:
            [Callout("Thighs under the pad", at: .knee, .setup, .right),
             Callout("Elbows down and back", at: .elbow, .lift, .left),
             Callout("Bar to the upper chest", at: .hand, .top, .right)]
        case .straightArmPulldown:
            [Callout("Arms almost straight", at: .elbow, .always, .right),
             Callout("Sweep to the thighs", at: .hand, .top, .right)]
        case .deadlift:
            [Callout("Bar over midfoot", at: .hand, .setup, .right),
             Callout("Back flat, chest up", at: .torso, .always, .above),
             Callout("Push the floor away", at: .knee, .lift, .right),
             Callout("Hips through at the top", at: .hip, .top, .left)]
        case .hinge:
            [Callout("Spine neutral", at: .torso, .always, .above),
             Callout("Hips back, knees soft", at: .hip, .lower, .left),
             Callout("Bar down the thighs", at: .hand, .lower, .right)]
        case .backExtension:
            [Callout("Hips on the pad edge", at: .hip, .always, .below),
             Callout("Lift to a flat line", at: .shoulder, .top, .above)]
        case .shrug:
            [Callout("Arms stay straight", at: .elbow, .always, .right),
             Callout("Shoulders to the ears", at: .shoulder, .top, .left)]
        case .lateralRaise:
            [Callout("Lead with the elbow", at: .elbow, .lift, .right),
             Callout("To shoulder height", at: .hand, .top, .right)]
        case .frontRaise:
            [Callout("No swing from the hips", at: .hip, .always, .left),
             Callout("To eye height", at: .hand, .top, .right)]
        case .rearDeltFly:
            [Callout("Hinged, back flat", at: .torso, .always, .above),
             Callout("Arms out, elbows soft", at: .hand, .top, .right)]
        case .facePull:
            [Callout("Elbows high and wide", at: .elbow, .lift, .above),
             Callout("Pull to the face", at: .hand, .top, .right)]
        case .seatedReverseFly:
            [Callout("Chest on the pad", at: .torso, .setup, .left),
             Callout("Sweep the arms back", at: .hand, .top, .right)]
        case .uprightRow:
            [Callout("Elbows lead the bar", at: .elbow, .lift, .right),
             Callout("Bar to chest height", at: .hand, .top, .right)]
        case .curl:
            [Callout("Elbows pinned to the sides", at: .elbow, .always, .left),
             Callout("Squeeze at the top", at: .hand, .top, .right)]
        case .overheadExtension:
            [Callout("Upper arms stay vertical", at: .elbow, .always, .left),
             Callout("Lower behind the head", at: .hand, .lower, .right)]
        case .pushdown:
            [Callout("Elbows tucked", at: .elbow, .always, .left),
             Callout("Lock out fully", at: .hand, .top, .right)]
        case .skullCrusher:
            [Callout("Upper arms still", at: .elbow, .always, .above),
             Callout("Lower toward the forehead", at: .hand, .lower, .above)]
        case .kickback:
            [Callout("Upper arm level with the floor", at: .elbow, .always, .above),
             Callout("Straighten fully", at: .hand, .top, .right)]
        case .wristCurl:
            [Callout("Forearms on the bench", at: .elbow, .always, .left),
             Callout("Curl the wrists up", at: .hand, .top, .right)]
        case .squat:
            [Callout("Bar over midfoot", at: .hand, .always, .left),
             Callout("Knees track over the toes", at: .knee, .setup, .right),
             Callout("Chest up, spine neutral", at: .torso, .lift, .left),
             Callout("Stand tall", at: .head, .top, .right)]
        case .frontSquat:
            [Callout("Elbows up", at: .elbow, .always, .right),
             Callout("Knees over the toes", at: .knee, .setup, .right),
             Callout("Torso upright", at: .torso, .lift, .left)]
        case .legPress:
            [Callout("Lower back on the pad", at: .hip, .always, .below),
             Callout("Knees to about 90°", at: .knee, .setup, .above),
             Callout("Don't lock the knees", at: .knee, .top, .above)]
        case .lunge:
            [Callout("Torso upright", at: .torso, .always, .left),
             Callout("Front knee over the foot", at: .knee, .setup, .right),
             Callout("Drive through the heel", at: .ankle, .lift, .below)]
        case .sissySquat:
            [Callout("Hips straight, lean back", at: .hip, .setup, .left),
             Callout("Knees forward over the toes", at: .knee, .setup, .right)]
        case .legExtension:
            [Callout("Pad just above the ankles", at: .ankle, .always, .below),
             Callout("Squeeze at the top", at: .knee, .top, .above)]
        case .legCurl:
            [Callout("Hips stay down", at: .hip, .always, .above),
             Callout("Heels to the glutes", at: .ankle, .top, .right)]
        case .seatedLegCurl:
            [Callout("Pad behind the ankles", at: .ankle, .setup, .right),
             Callout("Curl down and back", at: .ankle, .top, .below)]
        case .nordic:
            [Callout("Hips straight", at: .hip, .always, .above),
             Callout("Lower slowly", at: .shoulder, .lower, .right)]
        case .hipThrust:
            [Callout("Upper back on the bench", at: .shoulder, .always, .left),
             Callout("Chin tucked", at: .head, .always, .above),
             Callout("Hips to level, squeeze", at: .hip, .top, .above)]
        case .gluteBridge:
            [Callout("Feet flat, heels close", at: .ankle, .always, .right),
             Callout("Squeeze at the top", at: .hip, .top, .above)]
        case .hipAbduction:
            [Callout("Sit tall", at: .torso, .always, .left),
             Callout("Push the knees out", at: .knee, .lift, .right)]
        case .calfRaise:
            [Callout("Heels off the step", at: .ankle, .setup, .below),
             Callout("Pause at the top", at: .ankle, .top, .right)]
        case .seatedCalfRaise:
            [Callout("Pad on the knees", at: .knee, .always, .above),
             Callout("Full stretch at the bottom", at: .ankle, .setup, .right)]
        case .crunch:
            [Callout("Round the spine", at: .torso, .lift, .left),
             Callout("Ribs toward the hips", at: .head, .top, .right)]
        case .sitUp:
            [Callout("Lower back leaves the bench last", at: .hip, .lift, .above),
             Callout("Curl up, don't swing", at: .shoulder, .top, .right)]
        case .legRaise:
            [Callout("Hang still", at: .hip, .setup, .left),
             Callout("Legs to level, tilt the pelvis", at: .knee, .top, .right)]
        case .abWheel:
            [Callout("Hips don't sag", at: .hip, .always, .above),
             Callout("Roll out as far as you control", at: .hand, .setup, .right)]
        case .pallofPress:
            [Callout("Don't let the torso turn", at: .torso, .always, .left),
             Callout("Press straight out", at: .hand, .top, .right)]
        }
    }

    /// Read out in place of the diagram.
    var accessibilityDescription: String {
        switch self {
        case .benchPress, .inclinePress: "lying on a bench, pressing a bar from the chest to straight arms"
        case .overheadPress: "standing, pressing a bar from the shoulders to overhead"
        case .seatedPress: "seated, pressing from the shoulders to overhead"
        case .machineChestPress: "seated, pressing handles forward to straight arms"
        case .dip: "on parallel bars, lowering until the upper arms are level and pressing back up"
        case .pushUp: "face down, lowering the chest to the floor and pressing back up"
        case .fly: "arms sweeping together in front of the chest with slightly bent elbows"
        case .bentRow: "bent over, pulling a weight from arm's length to the torso"
        case .supportedRow: "chest on a pad, pulling the elbows back"
        case .verticalPull: "hanging from a bar, pulling the chest up to it"
        case .latPulldown: "seated, pulling a bar from overhead down to the upper chest"
        case .straightArmPulldown: "straight arms sweeping from overhead down to the thighs"
        case .deadlift: "lifting a bar from the floor to standing"
        case .hinge: "standing, pushing the hips back and lowering the weight down the legs, then standing"
        case .backExtension: "hips on a pad, lowering the torso and raising it to level"
        case .shrug: "shoulders rising toward the ears"
        case .lateralRaise: "arms raising out to the sides to shoulder height"
        case .frontRaise: "arms raising in front to shoulder height"
        case .rearDeltFly: "bent over, arms raising out to the sides"
        case .facePull: "standing, pulling a rope to the face with the elbows high"
        case .seatedReverseFly: "seated, sweeping the arms from in front out to the sides"
        case .uprightRow: "pulling a bar up the front of the body to chest height"
        case .curl: "forearms curling up with the elbows still"
        case .overheadExtension: "arms overhead, lowering the weight behind the head and extending"
        case .pushdown: "elbows at the sides, pushing a cable handle down to straight arms"
        case .skullCrusher: "lying down, lowering a bar toward the forehead and extending the arms"
        case .kickback: "bent over, extending the forearm back"
        case .wristCurl: "forearms resting, wrists curling up"
        case .squat, .frontSquat: "squatting down to below parallel and standing up"
        case .legPress: "reclined, pushing a platform away with the legs"
        case .lunge: "one foot forward, lowering until both knees bend and driving up"
        case .sissySquat: "leaning back with the hips straight as the knees bend"
        case .legExtension: "seated, straightening the knees against a pad"
        case .legCurl: "face down, curling the heels toward the glutes"
        case .seatedLegCurl: "seated, curling the heels down and back"
        case .nordic: "kneeling, lowering the body forward from the knees"
        case .hipThrust: "upper back on a bench, driving the hips up to level"
        case .gluteBridge: "lying down, driving the hips up"
        case .hipAbduction: "seated, pushing the thighs apart"
        case .calfRaise: "standing, rising onto the toes"
        case .seatedCalfRaise: "seated, rising onto the toes"
        case .crunch: "kneeling, rounding the spine to bring the ribs toward the hips"
        case .sitUp: "lying on a bench, curling the torso up to sitting"
        case .legRaise: "hanging, raising the legs to level"
        case .abWheel: "kneeling, rolling a wheel forward and pulling it back"
        case .pallofPress: "side-on to a cable, pressing the handle straight out"
        }
    }
}
