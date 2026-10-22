import Foundation

/// The movement a library exercise follows, drawn as a two-frame stick figure (side view,
/// facing right) in `MovementDiagram`. Frame 1 to frame 2 is the lifting phase.
nonisolated enum MovementPattern: String, CaseIterable, Hashable, Sendable {
    case benchPress, inclinePress, overheadPress, dip, pushUp, fly, bentRow, supportedRow, verticalPull, straightArmPulldown, deadlift, hinge, backExtension, shrug, lateralRaise, frontRaise, rearDeltFly, uprightRow, curl, overheadExtension, pushdown, skullCrusher, kickback, wristCurl, squat, frontSquat, legPress, lunge, sissySquat, legExtension, legCurl, seatedLegCurl, nordic, hipThrust, gluteBridge, hipAbduction, calfRaise, seatedCalfRaise, crunch, sitUp, legRaise, abWheel, pallofPress, latPulldown, facePull, seatedReverseFly, machineChestPress, seatedPress

    /// Both frames, in a 0...100 square. The poses are schematic: they show which joints move
    /// and in which direction, not exact angles.
    var frames: (start: FigurePose, finish: FigurePose) {
        switch self {
        case .benchPress:
            (FigurePose(hip: CGPoint(x: 36, y: 58), torso: 90, thigh: 230, shin: 180, arm: 200, forearm: 0, props: [.floor(y: 92), .rack(x: 74, y: 26), .bench(x1: 20, x2: 68, y: 60), .plate]),
             FigurePose(hip: CGPoint(x: 36, y: 58), torso: 90, thigh: 230, shin: 180, arm: 0, forearm: 0, props: [.floor(y: 92), .rack(x: 74, y: 26), .bench(x1: 20, x2: 68, y: 60), .plate]))
        case .inclinePress:
            (FigurePose(hip: CGPoint(x: 30, y: 62), torso: 40, thigh: 210, shin: 180, arm: 200, forearm: 40, props: [.floor(y: 92), .support(x1: 26, y1: 68, x2: 50, y2: 40), .support(x1: 26, y1: 68, x2: 36, y2: 68), .plate]),
             FigurePose(hip: CGPoint(x: 30, y: 62), torso: 40, thigh: 210, shin: 180, arm: 40, forearm: 40, props: [.floor(y: 92), .support(x1: 26, y1: 68, x2: 50, y2: 40), .support(x1: 26, y1: 68, x2: 36, y2: 68), .plate]))
        case .overheadPress:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 160, forearm: 340, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 0, forearm: 0, props: [.floor(y: 92), .plate]))
        case .dip:
            (FigurePose(hip: CGPoint(x: 46, y: 58), torso: 15, thigh: 200, shin: 250, arm: 280, forearm: 170, props: [.floor(y: 92), .post]),
             FigurePose(hip: CGPoint(x: 46, y: 48), torso: 8, thigh: 190, shin: 240, arm: 180, forearm: 180, props: [.floor(y: 92), .post]))
        case .pushUp:
            (FigurePose(hip: CGPoint(x: 36, y: 84), torso: 88, thigh: 268, shin: 268, arm: 300, forearm: 170, props: [.floor(y: 92)]),
             FigurePose(hip: CGPoint(x: 36, y: 72), torso: 72, thigh: 250, shin: 250, arm: 175, forearm: 175, props: [.floor(y: 92)]))
        case .fly:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .cable(x: 95, y: 30), .plateSmall]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 60, forearm: 110, props: [.floor(y: 92), .cable(x: 95, y: 30), .plateSmall]))
        case .bentRow:
            (FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 250, forearm: 120, props: [.floor(y: 92), .plate]))
        case .supportedRow:
            (FigurePose(hip: CGPoint(x: 36, y: 62), torso: 40, thigh: 160, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .support(x1: 33, y1: 73, x2: 63, y2: 47), .support(x1: 52, y1: 62, x2: 52, y2: 92), .plateSmall]),
             FigurePose(hip: CGPoint(x: 36, y: 62), torso: 40, thigh: 160, shin: 180, arm: 250, forearm: 120, props: [.floor(y: 92), .support(x1: 33, y1: 73, x2: 63, y2: 47), .support(x1: 52, y1: 62, x2: 52, y2: 92), .plateSmall]))
        case .verticalPull:
            (FigurePose(hip: CGPoint(x: 46, y: 64), torso: 0, thigh: 180, shin: 250, arm: 0, forearm: 0, props: [.barOverhead(y: 17)]),
             FigurePose(hip: CGPoint(x: 46, y: 40), torso: 5, thigh: 180, shin: 250, arm: 190, forearm: 340, props: [.barOverhead(y: 17)]))
        case .straightArmPulldown:
            (FigurePose(hip: CGPoint(x: 44, y: 56), torso: 15, thigh: 180, shin: 180, arm: 50, forearm: 50, props: [.floor(y: 92), .cable(x: 92, y: 8), .plateSmall]),
             FigurePose(hip: CGPoint(x: 44, y: 56), torso: 15, thigh: 180, shin: 180, arm: 150, forearm: 150, props: [.floor(y: 92), .cable(x: 92, y: 8), .plateSmall]))
        case .deadlift:
            (FigurePose(hip: CGPoint(x: 34, y: 64), torso: 60, thigh: 140, shin: 175, arm: 160, forearm: 160, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]))
        case .hinge:
            (FigurePose(hip: CGPoint(x: 40, y: 58), torso: 75, thigh: 175, shin: 180, arm: 160, forearm: 160, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]))
        case .backExtension:
            (FigurePose(hip: CGPoint(x: 44, y: 56), torso: 110, thigh: 170, shin: 180, arm: 170, forearm: 170, props: [.floor(y: 92), .box(x: 36, y: 58, w: 14, h: 34), .support(x1: 20, y1: 92, x2: 50, y2: 66)]),
             FigurePose(hip: CGPoint(x: 44, y: 56), torso: 60, thigh: 170, shin: 180, arm: 170, forearm: 170, props: [.floor(y: 92), .box(x: 36, y: 58, w: 14, h: 34), .support(x1: 20, y1: 92, x2: 50, y2: 66)]))
        case .shrug:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate], shoulderLift: 4))
        case .lateralRaise:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 175, forearm: 175, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .dumbbell]))
        case .frontRaise:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 170, forearm: 170, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .dumbbell]))
        case .rearDeltFly:
            (FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 290, forearm: 290, props: [.floor(y: 92), .dumbbell]))
        case .uprightRow:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 300, props: [.floor(y: 92), .plate]))
        case .curl:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 30, props: [.floor(y: 92), .plate]))
        case .overheadExtension:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 0, forearm: 0, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 0, forearm: 230, props: [.floor(y: 92), .dumbbell]))
        case .pushdown:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 30, props: [.floor(y: 92), .cable(x: 70, y: 4), .plateSmall]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 120, props: [.floor(y: 92), .cable(x: 70, y: 4), .plateSmall]))
        case .skullCrusher:
            (FigurePose(hip: CGPoint(x: 36, y: 58), torso: 90, thigh: 230, shin: 180, arm: 0, forearm: 0, props: [.floor(y: 92), .bench(x1: 20, x2: 68, y: 60), .plate]),
             FigurePose(hip: CGPoint(x: 36, y: 58), torso: 90, thigh: 230, shin: 180, arm: 350, forearm: 250, props: [.floor(y: 92), .bench(x1: 20, x2: 68, y: 60), .plate]))
        case .kickback:
            (FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 250, forearm: 180, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 40, y: 58), torso: 60, thigh: 170, shin: 180, arm: 250, forearm: 250, props: [.floor(y: 92), .dumbbell]))
        case .wristCurl:
            (FigurePose(hip: CGPoint(x: 44, y: 62), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 100, props: [.floor(y: 92), .box(x: 40, y: 78, w: 22, h: 14), .plate]),
             FigurePose(hip: CGPoint(x: 44, y: 62), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 80, props: [.floor(y: 92), .box(x: 40, y: 78, w: 22, h: 14), .plate]))
        case .squat:
            (FigurePose(hip: CGPoint(x: 38, y: 66), torso: 30, thigh: 95, shin: 190, arm: 300, forearm: 20, props: [.floor(y: 92), .rack(x: 16, y: 30), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 300, forearm: 20, props: [.floor(y: 92), .rack(x: 16, y: 30), .plate]))
        case .frontSquat:
            (FigurePose(hip: CGPoint(x: 42, y: 66), torso: 10, thigh: 100, shin: 190, arm: 100, forearm: 0, props: [.floor(y: 92), .rack(x: 16, y: 30), .plate]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 100, forearm: 0, props: [.floor(y: 92), .rack(x: 16, y: 30), .plate]))
        case .legPress:
            (FigurePose(hip: CGPoint(x: 40, y: 66), torso: 315, thigh: 40, shin: 100, arm: 90, forearm: 150, props: [.support(x1: 46, y1: 74, x2: 12, y2: 40), .box(x: 10, y: 80, w: 40, h: 6), .support(x1: 74, y1: 42, x2: 68, y2: 72)]),
             FigurePose(hip: CGPoint(x: 40, y: 66), torso: 315, thigh: 60, shin: 70, arm: 90, forearm: 150, props: [.support(x1: 46, y1: 74, x2: 12, y2: 40), .box(x: 10, y: 80, w: 40, h: 6), .support(x1: 80, y1: 36, x2: 72, y2: 68)]))
        case .lunge:
            (FigurePose(hip: CGPoint(x: 44, y: 66), torso: 5, thigh: 90, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .dumbbell]),
             FigurePose(hip: CGPoint(x: 44, y: 52), torso: 5, thigh: 160, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .dumbbell]))
        case .sissySquat:
            (FigurePose(hip: CGPoint(x: 50, y: 56), torso: 340, thigh: 100, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92)]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92)]))
        case .legExtension:
            (FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]),
             FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 90, shin: 90, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]))
        case .legCurl:
            (FigurePose(hip: CGPoint(x: 44, y: 66), torso: 270, thigh: 90, shin: 90, arm: 270, forearm: 180, props: [.floor(y: 92), .bench(x1: 16, x2: 78, y: 68), .anklePad], footAngle: 180),
             FigurePose(hip: CGPoint(x: 44, y: 66), torso: 270, thigh: 90, shin: 10, arm: 270, forearm: 180, props: [.floor(y: 92), .bench(x1: 16, x2: 78, y: 68), .anklePad], footAngle: 100))
        case .seatedLegCurl:
            (FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 90, shin: 90, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]),
             FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 90, shin: 170, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]))
        case .nordic:
            (FigurePose(hip: CGPoint(x: 44, y: 66), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 120, props: [.floor(y: 92), .box(x: 66, y: 86, w: 14, h: 6)]),
             FigurePose(hip: CGPoint(x: 44, y: 66), torso: 70, thigh: 90, shin: 180, arm: 160, forearm: 110, props: [.floor(y: 92), .box(x: 66, y: 86, w: 14, h: 6)]))
        case .hipThrust:
            (FigurePose(hip: CGPoint(x: 44, y: 82), torso: 304, thigh: 60, shin: 180, arm: 120, forearm: 120, props: [.floor(y: 92), .box(x: 8, y: 70, w: 20, h: 22), .plate]),
             FigurePose(hip: CGPoint(x: 44, y: 72), torso: 276, thigh: 90, shin: 180, arm: 100, forearm: 90, props: [.floor(y: 92), .box(x: 8, y: 70, w: 20, h: 22), .plate]))
        case .gluteBridge:
            (FigurePose(hip: CGPoint(x: 48, y: 84), torso: 265, thigh: 56, shin: 180, arm: 120, forearm: 120, props: [.floor(y: 92), .plate]),
             FigurePose(hip: CGPoint(x: 48, y: 74), torso: 250, thigh: 80, shin: 180, arm: 110, forearm: 110, props: [.floor(y: 92), .plate]))
        case .hipAbduction:
            (FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]),
             FigurePose(hip: CGPoint(x: 44, y: 60), torso: 0, thigh: 60, shin: 180, arm: 180, forearm: 180, props: [.box(x: 30, y: 70, w: 30, h: 22), .support(x1: 22, y1: 60, x2: 24, y2: 92), .anklePad]))
        case .calfRaise:
            (FigurePose(hip: CGPoint(x: 46, y: 52), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .box(x: 36, y: 86, w: 20, h: 6), .dumbbell]),
             FigurePose(hip: CGPoint(x: 46, y: 48), torso: 0, thigh: 180, shin: 180, arm: 180, forearm: 180, props: [.floor(y: 92), .box(x: 36, y: 86, w: 20, h: 6), .dumbbell]))
        case .seatedCalfRaise:
            (FigurePose(hip: CGPoint(x: 44, y: 62), torso: 0, thigh: 90, shin: 180, arm: 180, forearm: 100, props: [.floor(y: 92), .box(x: 36, y: 84, w: 34, h: 8), .support(x1: 60, y1: 70, x2: 70, y2: 70)]),
             FigurePose(hip: CGPoint(x: 44, y: 58), torso: 0, thigh: 90, shin: 175, arm: 180, forearm: 100, props: [.floor(y: 92), .box(x: 36, y: 84, w: 34, h: 8), .support(x1: 60, y1: 70, x2: 70, y2: 70)]))
        case .crunch:
            (FigurePose(hip: CGPoint(x: 44, y: 70), torso: 0, thigh: 90, shin: 180, arm: 20, forearm: 340, props: [.floor(y: 92), .cable(x: 92, y: 6), .plateSmall]),
             FigurePose(hip: CGPoint(x: 44, y: 70), torso: 45, thigh: 90, shin: 180, arm: 45, forearm: 0, props: [.floor(y: 92), .cable(x: 92, y: 6), .plateSmall]))
        case .sitUp:
            (FigurePose(hip: CGPoint(x: 40, y: 70), torso: 275, thigh: 60, shin: 170, arm: 350, forearm: 350, props: [.floor(y: 92), .bench(x1: 16, x2: 72, y: 72)]),
             FigurePose(hip: CGPoint(x: 40, y: 70), torso: 30, thigh: 60, shin: 170, arm: 20, forearm: 20, props: [.floor(y: 92), .bench(x1: 16, x2: 72, y: 72)]))
        case .legRaise:
            (FigurePose(hip: CGPoint(x: 46, y: 50), torso: 0, thigh: 180, shin: 180, arm: 0, forearm: 0, props: [.barOverhead(y: 3)]),
             FigurePose(hip: CGPoint(x: 46, y: 50), torso: 0, thigh: 90, shin: 90, arm: 0, forearm: 0, props: [.barOverhead(y: 3)]))
        case .abWheel:
            (FigurePose(hip: CGPoint(x: 40, y: 68), torso: 30, thigh: 180, shin: 270, arm: 40, forearm: 40, props: [.floor(y: 92), .wheel]),
             FigurePose(hip: CGPoint(x: 40, y: 66), torso: 80, thigh: 140, shin: 270, arm: 85, forearm: 85, props: [.floor(y: 92), .wheel]))
        case .pallofPress:
            (FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 120, forearm: 0, props: [.floor(y: 92), .cable(x: 95, y: 32), .plateSmall]),
             FigurePose(hip: CGPoint(x: 46, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .cable(x: 95, y: 32), .plateSmall]))
        case .latPulldown:
            (FigurePose(hip: CGPoint(x: 46, y: 62), torso: 5, thigh: 90, shin: 180, arm: 15, forearm: 345, props: [.floor(y: 92), .box(x: 34, y: 72, w: 24, h: 20), .support(x1: 58, y1: 64, x2: 72, y2: 64), .cable(x: 50, y: 2), .plateSmall]),
             FigurePose(hip: CGPoint(x: 46, y: 62), torso: 5, thigh: 90, shin: 180, arm: 200, forearm: 20, props: [.floor(y: 92), .box(x: 34, y: 72, w: 24, h: 20), .support(x1: 58, y1: 64, x2: 72, y2: 64), .cable(x: 50, y: 2), .plateSmall]))
        case .facePull:
            (FigurePose(hip: CGPoint(x: 42, y: 55), torso: 0, thigh: 180, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .cable(x: 95, y: 28), .plateSmall]),
             FigurePose(hip: CGPoint(x: 42, y: 55), torso: 0, thigh: 180, shin: 180, arm: 130, forearm: 10, props: [.floor(y: 92), .cable(x: 95, y: 28), .plateSmall]))
        case .seatedReverseFly:
            (FigurePose(hip: CGPoint(x: 40, y: 62), torso: 0, thigh: 90, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .box(x: 28, y: 72, w: 24, h: 20), .support(x1: 52, y1: 36, x2: 52, y2: 62), .plateSmall]),
             FigurePose(hip: CGPoint(x: 40, y: 62), torso: 0, thigh: 90, shin: 180, arm: 165, forearm: 160, props: [.floor(y: 92), .box(x: 28, y: 72, w: 24, h: 20), .support(x1: 52, y1: 36, x2: 52, y2: 62), .plateSmall]))
        case .machineChestPress:
            (FigurePose(hip: CGPoint(x: 38, y: 62), torso: 0, thigh: 90, shin: 180, arm: 110, forearm: 330, props: [.floor(y: 92), .box(x: 26, y: 72, w: 24, h: 20), .support(x1: 32, y1: 32, x2: 32, y2: 62), .plateSmall]),
             FigurePose(hip: CGPoint(x: 38, y: 62), torso: 0, thigh: 90, shin: 180, arm: 90, forearm: 90, props: [.floor(y: 92), .box(x: 26, y: 72, w: 24, h: 20), .support(x1: 32, y1: 32, x2: 32, y2: 62), .plateSmall]))
        case .seatedPress:
            (FigurePose(hip: CGPoint(x: 40, y: 62), torso: 0, thigh: 90, shin: 180, arm: 160, forearm: 340, props: [.floor(y: 92), .box(x: 28, y: 72, w: 24, h: 20), .support(x1: 34, y1: 34, x2: 34, y2: 62), .plate]),
             FigurePose(hip: CGPoint(x: 40, y: 62), torso: 0, thigh: 90, shin: 180, arm: 0, forearm: 0, props: [.floor(y: 92), .box(x: 28, y: 72, w: 24, h: 20), .support(x1: 34, y1: 34, x2: 34, y2: 62), .plate]))
        }    }
}

/// Something drawn with the figure: what it lies or sits on, and what it holds.
nonisolated enum FigureProp: Hashable, Sendable {
    case floor(y: Double)
    case bench(x1: Double, x2: Double, y: Double)
    case support(x1: Double, y1: Double, x2: Double, y2: Double)
    case box(x: Double, y: Double, w: Double, h: Double)
    case cable(x: Double, y: Double)
    case barOverhead(y: Double)
    case plate        // a bar seen end-on, at the hand
    case plateSmall   // a cable handle, at the hand
    case dumbbell
    case post         // a dip bar: from the hand to the floor
    case wheel
    case kettlebell
    case handle       // a machine grip, at the hand
    case rack(x: Double, y: Double)   // an upright with a J-hook at the bar's resting height
    case rails        // Smith machine rails, through the bar
    case anklePad     // a machine's roller pad, at the ankle

    /// Whether this is the load in the hands, which the exercise's implement decides.
    var isLoad: Bool {
        switch self {
        case .plate, .plateSmall, .dumbbell, .kettlebell, .handle: true
        default: false
        }
    }
}

/// A side-view stick figure, built from the hip outward. Angles are in degrees with 0 pointing
/// up, 90 forward (to the right), 180 down and 270 back, each measured at its own joint.
nonisolated struct FigurePose: Hashable, Sendable {
    static let torsoLength = 22.0
    static let thighLength = 18.0
    static let shinLength = 18.0
    static let upperArmLength = 13.0
    static let forearmLength = 12.0
    static let headOffset = 7.0
    static let headRadius = 5.0

    var hip: CGPoint
    var torso: Double
    var thigh: Double
    var shin: Double
    var arm: Double
    var forearm: Double
    var props: [FigureProp] = []
    /// How far the shoulders are raised toward the ears (a shrug), in figure units.
    var shoulderLift: Double = 0
    /// The foot's direction, heel to toe; nil points it forward, at right angles to the shin.
    var footAngle: Double? = nil

    static let neckLength = 3.0
    static let footLength = 7.5
    static let heelLength = 2.5

    nonisolated struct Joints: Hashable, Sendable {
        var shoulder: CGPoint
        var neck: CGPoint
        var head: CGPoint
        var knee: CGPoint
        var ankle: CGPoint
        var heel: CGPoint
        var toe: CGPoint
        var elbow: CGPoint
        var hand: CGPoint

        /// The articulated points, for bounds checks.
        var all: [CGPoint] { [shoulder, head, knee, ankle, elbow, hand] }
        /// Everything drawn, feet included.
        var everything: [CGPoint] { all + [neck, heel, toe] }
    }

    private static func step(_ from: CGPoint, _ degrees: Double, _ length: Double) -> CGPoint {
        let r = degrees * .pi / 180
        return CGPoint(x: from.x + length * sin(r), y: from.y - length * cos(r))
    }

    var joints: Joints {
        var shoulder = Self.step(hip, torso, Self.torsoLength)
        shoulder.y -= shoulderLift
        let neck = Self.step(shoulder, torso, Self.neckLength)
        let head = Self.step(shoulder, torso, Self.headOffset)
        let knee = Self.step(hip, thigh, Self.thighLength)
        let ankle = Self.step(knee, shin, Self.shinLength)
        let foot = footAngle ?? (shin - 90)
        let heel = Self.step(ankle, foot + 180, Self.heelLength)
        let toe = Self.step(ankle, foot, Self.footLength)
        let elbow = Self.step(shoulder, arm, Self.upperArmLength)
        let hand = Self.step(elbow, forearm, Self.forearmLength)
        return Joints(shoulder: shoulder, neck: neck, head: head, knee: knee, ankle: ankle, heel: heel, toe: toe, elbow: elbow, hand: hand)
    }
}

nonisolated extension FigurePose {
    /// The shortest way round from one limb angle to another, in degrees (-180...180).
    static func turn(from a: Double, to b: Double) -> Double {
        var d = (b - a).truncatingRemainder(dividingBy: 360)
        if d > 180 { d -= 360 }
        if d < -180 { d += 360 }
        return d
    }

    /// The pose part way (`t` in 0...1) from this one to `other`: the hip slides in a straight line,
    /// each joint turns the short way round. Props come from whichever end is nearer.
    func interpolated(to other: FigurePose, _ t: Double) -> FigurePose {
        func lerp(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        func angle(_ a: Double, _ b: Double) -> Double { a + Self.turn(from: a, to: b) * t }
        var foot: Double? = nil
        if let a = footAngle, let b = other.footAngle { foot = angle(a, b) } else { foot = t < 0.5 ? footAngle : other.footAngle }
        return FigurePose(hip: CGPoint(x: lerp(hip.x, other.hip.x), y: lerp(hip.y, other.hip.y)),
                          torso: angle(torso, other.torso), thigh: angle(thigh, other.thigh), shin: angle(shin, other.shin),
                          arm: angle(arm, other.arm), forearm: angle(forearm, other.forearm),
                          props: t < 0.5 ? props : other.props,
                          shoulderLift: lerp(shoulderLift, other.shoulderLift), footAngle: foot)
    }

    /// Whether the figure holds a load whose path is worth drawing.
    var holdsLoad: Bool {
        props.contains { prop in
            switch prop {
            case .plate, .plateSmall, .dumbbell, .kettlebell, .handle, .wheel, .cable: true
            default: false
            }
        }
    }
}

/// What moves between the two frames, worked out from them: the path of the load (or of the
/// limb that moves most when nothing is held), the joints whose angle changes and which way,
/// and any straight shift of the hips or shoulders the arcs do not already show.
nonisolated struct MovementMotion: Hashable, Sendable {
    nonisolated enum Anchor: String, Hashable, Sendable { case hand, hip, shoulder, knee, ankle }

    /// A joint turning from one limb angle to another, drawn as an arc around the joint.
    nonisolated struct Turn: Hashable, Sendable {
        var joint: String
        var pivot: CGPoint
        var from: Double
        var to: Double
        var radius: Double

        var degrees: Double { FigurePose.turn(from: from, to: to) }

        /// Points along the arc, start to finish, in the figure's 0...100 square.
        var points: [CGPoint] {
            let steps = max(4, Int(abs(degrees) / 10))
            return (0...steps).map { i in
                let a = (from + degrees * Double(i) / Double(steps)) * .pi / 180
                return CGPoint(x: pivot.x + radius * sin(a), y: pivot.y - radius * cos(a))
            }
        }
    }

    /// A point moving in a straight line, drawn as a short arrow.
    nonisolated struct Shift: Hashable, Sendable {
        var point: String
        var from: CGPoint
        var to: CGPoint
    }

    var anchor: Anchor
    /// The anchor's path from frame 1 to frame 2, in the 0...100 square.
    var path: [CGPoint]
    var turns: [Turn]
    var shifts: [Shift]

    static let turnThreshold = 20.0
    static let shiftThreshold = 3.5

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }

    init(start: FigurePose, finish: FigurePose) {
        self.init(keyframes: [start, start.interpolated(to: finish, 0.5), finish])
    }

    /// `keyframes` is start, midpoint, finish; the path is sampled along the whole curve.
    init(keyframes: [FigurePose]) {
        let start = keyframes.first!, finish = keyframes.last!
        let a = start.joints, b = finish.joints
        // Hips first: when the whole body moves (a pull-up, a dip), that is the path to show.
        let candidates: [(Anchor, CGPoint, CGPoint)] = [
            (.hip, start.hip, finish.hip), (.hand, a.hand, b.hand), (.ankle, a.ankle, b.ankle),
            (.knee, a.knee, b.knee), (.shoulder, a.shoulder, b.shoulder),
        ]
        let moving: Anchor
        if start.holdsLoad || finish.holdsLoad {
            moving = .hand
        } else {
            moving = candidates.max { Self.distance($0.1, $0.2) < Self.distance($1.1, $1.2) }!.0
        }
        anchor = moving
        let steps = 24
        path = (0...steps).map { i in
            let pose = FigurePose.along(keyframes, Double(i) / Double(steps))
            let j = pose.joints
            switch moving {
            case .hand: return j.hand
            case .hip: return pose.hip
            case .ankle: return j.ankle
            case .knee: return j.knee
            case .shoulder: return j.shoulder
            }
        }
        // The shrug moves the shoulder by a prop, not an angle; make the path end where it ends.
        if moving == .hand { path[path.count - 1] = b.hand }
        if moving == .shoulder { path[path.count - 1] = b.shoulder }

        var turns: [Turn] = []
        let joints: [(String, CGPoint, Double, Double, Double)] = [
            ("torso", start.hip, start.torso, finish.torso, 12),
            ("hip", start.hip, start.thigh, finish.thigh, 9),
            ("knee", a.knee, start.shin, finish.shin, 9),
            ("shoulder", a.shoulder, start.arm, finish.arm, 9),
            ("elbow", a.elbow, start.forearm, finish.forearm, 8),
        ]
        for (joint, pivot, from, to, radius) in joints where abs(FigurePose.turn(from: from, to: to)) >= Self.turnThreshold {
            turns.append(Turn(joint: joint, pivot: pivot, from: from, to: to, radius: radius))
        }
        self.turns = turns

        var shifts: [Shift] = []
        if moving != .hip, Self.distance(start.hip, finish.hip) >= Self.shiftThreshold {
            shifts.append(Shift(point: "hips", from: start.hip, to: finish.hip))
        }
        let torsoTurns = abs(FigurePose.turn(from: start.torso, to: finish.torso)) >= Self.turnThreshold
        if moving != .shoulder, !torsoTurns, Self.distance(start.hip, finish.hip) < Self.shiftThreshold,
           Self.distance(a.shoulder, b.shoulder) >= Self.shiftThreshold {
            shifts.append(Shift(point: "shoulders", from: a.shoulder, to: b.shoulder))
        }
        self.shifts = shifts
    }
}

nonisolated extension MovementPattern {
    /// The motion between the two frames, for the arrows and the load path.
    var motion: MovementMotion {
        MovementMotion(keyframes: keyframes)
    }

    /// What the dashed line in the diagram follows.
    var pathDescription: String {
        switch motion.anchor {
        case .hand: "the path of the bar, handle or dumbbell"
        case .hip: "the path of the hips"
        case .shoulder: "the path of the shoulders"
        case .knee: "the path of the knee"
        case .ankle: "the path of the foot"
        }
    }
}
