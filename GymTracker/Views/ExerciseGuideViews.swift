import SwiftUI
import SwiftData

// MARK: - Detail

/// What an exercise is, how to do it, and what it trains: the guide text and movement diagram
/// for library exercises, the muscle map and targets for every exercise. Reached from a program
/// day, the picker, the workout menu and a lift's progress screen.
struct ExerciseDetailView: View {
    var exercise: Exercise

    @Query private var settingsList: [UserSettings]
    private var metric: Bool { settingsList.first?.usesMetric ?? false }
    private var guide: ExerciseGuide? { ExerciseGuides.guide(for: exercise.name) }

    var body: some View {
        List {
            if let guide {
                Section {
                    MovementDiagram(pattern: guide.pattern)
                        .frame(height: 190)
                        .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                        .accessibilityLabel("Diagram: \(guide.pattern.accessibilityDescription)")
                    Text(guide.summary)
                    LabeledContent("Equipment", value: guide.equipment)
                        .font(.subheadline)
                } footer: {
                    Text("Start to finish is the lifting phase. Arrows show which joints move and which way; the dashed line is \(guide.pattern.pathDescription); the faint figure is the start position. The figure is schematic, not to scale.")
                }
                Section("How to do it") {
                    ForEach(Array(guide.cues.enumerated()), id: \.offset) { index, cue in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(index + 1)").font(.callout.monospacedDigit().bold()).foregroundStyle(.secondary)
                            Text(cue)
                        }
                    }
                }
            } else {
                Section {
                    Text("A custom exercise. The muscle map and targets below are what you set for it; there is no guide text or diagram.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                MuscleMap(muscles: exercise.muscles)
                    .frame(height: 230)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                    .accessibilityLabel(exercise.muscles.involvementSummary)
                if exercise.muscles.isEmpty {
                    Text("No muscles set. Edit the exercise to add them, so its sets count toward weekly volume.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    let tiers = exercise.muscles.byInvolvement
                    ForEach(MuscleInvolvement.allCases) { tier in
                        if let muscles = tiers[tier], !muscles.isEmpty {
                            HStack(spacing: 8) {
                                MuscleSwatch(tier: tier)
                                LabeledContent(tier.pluralName, value: muscles.map(\.displayName).joined(separator: ", "))
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text("Each set counts as a full hard set for a primary mover, half for a secondary, a quarter for a stabiliser.")
            }

            Section {
                LabeledContent("Sets", value: "\(exercise.setCount)")
                LabeledContent("Reps", value: "\(exercise.repRangeLow)–\(exercise.repRangeHigh)")
                LabeledContent("RPE cap", value: Units.number(exercise.rpeCap))
                LabeledContent("Add when progressing", value: Units.weight(exercise.increment, metric: metric))
                LabeledContent("Rest between sets", value: RestRule.label(exercise.restSeconds))
            } header: {
                Text("Targets")
            } footer: {
                Text("Progress when every set hits the top of the rep range at or under the RPE cap.")
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink("Edit") { ExerciseEditorView(exercise: exercise) }
            }
        }
    }

}

/// The detail view in a sheet of its own, for places that are not inside a navigation stack
/// that can push it (the picker, the workout, a lift's progress screen).
struct ExerciseGuideSheet: View {
    var exercise: Exercise
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ExerciseDetailView(exercise: exercise)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Movement diagram

/// Two stick-figure frames of a movement pattern, side by side. The start frame carries arrows
/// at the joints that move; the finish frame carries the start pose as a ghost and the dashed
/// path of the load (or of the limb that moves, when nothing is held) from there to here.
struct MovementDiagram: View {
    var pattern: MovementPattern

    var body: some View {
        let frames = pattern.frames
        let motion = pattern.motion
        HStack(spacing: 4) {
            figure(FigureCanvas(pose: frames.start, motion: motion, showsTurns: true), label: "Start")
            Image(systemName: "arrow.right").foregroundStyle(.secondary).font(.title3)
            figure(FigureCanvas(pose: frames.finish, ghost: frames.start, motion: motion, showsTurns: false), label: "Finish")
        }
    }

    private func figure(_ canvas: FigureCanvas, label: String) -> some View {
        canvas
            .aspectRatio(1, contentMode: .fit)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topLeading) {
                Text(label).font(.caption.bold()).foregroundStyle(.secondary).padding(6)
            }
    }
}

/// Draws one pose, with the motion marks that belong on it. The pose is in a 0...100 square and
/// is scaled to the view.
private struct FigureCanvas: View {
    var pose: FigurePose
    var ghost: FigurePose? = nil
    var motion: MovementMotion
    var showsTurns: Bool

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: offset.x + x * scale, y: offset.y + y * scale) }
            func pt(_ p: CGPoint) -> CGPoint { pt(p.x, p.y) }
            let joints = pose.joints
            let gear = GraphicsContext.Shading.color(Color.accentColor)
            let prop = GraphicsContext.Shading.color(Color.secondary.opacity(0.45))
            let body = GraphicsContext.Shading.color(Color.primary)
            let faint = GraphicsContext.Shading.color(Color.primary.opacity(0.22))
            let mark = GraphicsContext.Shading.color(Color.accentColor)
            let bodyWidth = 2.4 * scale

            // Props behind the figure.
            for item in pose.props {
                switch item {
                case .floor(let y):
                    context.stroke(Path { $0.move(to: pt(4, y)); $0.addLine(to: pt(96, y)) }, with: prop, lineWidth: 1.2 * scale)
                case .bench(let x1, let x2, let y):
                    context.fill(Path(CGRect(x: pt(x1, y).x, y: pt(x1, y).y, width: (x2 - x1) * scale, height: 5 * scale)), with: prop)
                case .support(let x1, let y1, let x2, let y2):
                    context.stroke(Path { $0.move(to: pt(x1, y1)); $0.addLine(to: pt(x2, y2)) }, with: prop, lineWidth: 4 * scale)
                case .box(let x, let y, let w, let h):
                    context.fill(Path(CGRect(x: pt(x, y).x, y: pt(x, y).y, width: w * scale, height: h * scale)), with: prop)
                case .cable(let x, let y):
                    context.stroke(Path { $0.move(to: pt(x, y)); $0.addLine(to: pt(joints.hand)) }, with: gear, lineWidth: 1 * scale)
                case .barOverhead(let y):
                    context.stroke(Path { $0.move(to: pt(20, y)); $0.addLine(to: pt(80, y)) }, with: prop, lineWidth: 2.5 * scale)
                case .post:
                    context.stroke(Path { $0.move(to: pt(joints.hand)); $0.addLine(to: pt(joints.hand.x, 92)) }, with: prop, lineWidth: 2.5 * scale)
                case .plate, .plateSmall, .dumbbell, .wheel, .shrugUp:
                    break
                }
            }

            // The other frame, as a ghost behind this one.
            if let ghost {
                drawFigure(ghost, in: &context, pt: pt, scale: scale, shading: faint, lineWidth: bodyWidth)
                drawHeld(ghost, in: &context, pt: pt, scale: scale, shading: faint)
            }

            // The figure.
            drawFigure(pose, in: &context, pt: pt, scale: scale, shading: body, lineWidth: bodyWidth)

            // Arrows at the joints that move, and the straight shifts the arcs do not show.
            if showsTurns {
                for turn in motion.turns {
                    let points = turn.points
                    var arc = Path()
                    arc.move(to: pt(points[0]))
                    for p in points.dropFirst() { arc.addLine(to: pt(p)) }
                    context.stroke(arc, with: mark, style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
                    drawArrowhead(from: pt(points[points.count - 2]), to: pt(points[points.count - 1]), in: &context, scale: scale, shading: mark)
                }
                for shift in motion.shifts {
                    context.stroke(Path { $0.move(to: pt(shift.from)); $0.addLine(to: pt(shift.to)) }, with: mark,
                                   style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
                    drawArrowhead(from: pt(shift.from), to: pt(shift.to), in: &context, scale: scale, shading: mark)
                }
            }

            // What it holds, in front.
            drawHeld(pose, in: &context, pt: pt, scale: scale, shading: gear)

            // The load path: dashed, with an arrowhead at the finish. Drawn on the finish frame,
            // where the ghost shows where it started. Drawn last so a short path is not hidden by the bar.
            let path = motion.path
            if !showsTurns, let first = path.first, let last = path.last, MovementMotion.distance(first, last) >= 1 {
                var line = Path()
                line.move(to: pt(first))
                for p in path.dropFirst() { line.addLine(to: pt(p)) }
                context.stroke(line, with: mark, style: StrokeStyle(lineWidth: 1.3 * scale, lineCap: .round, lineJoin: .round, dash: [2.6 * scale, 2.4 * scale]))
                let r = 1.6 * scale
                context.fill(Path(ellipseIn: CGRect(x: pt(first).x - r, y: pt(first).y - r, width: 2 * r, height: 2 * r)), with: mark)
                drawArrowhead(from: pt(path[path.count - 2]), to: pt(last), in: &context, scale: scale, shading: mark)
            }

        }
    }

    private func drawFigure(_ pose: FigurePose, in context: inout GraphicsContext, pt: (CGPoint) -> CGPoint, scale: Double,
                            shading: GraphicsContext.Shading, lineWidth: Double) {
        let joints = pose.joints
        var limbs = Path()
        for (a, b) in [(pose.hip, joints.shoulder), (pose.hip, joints.knee), (joints.knee, joints.ankle),
                       (joints.shoulder, joints.elbow), (joints.elbow, joints.hand)] {
            limbs.move(to: pt(a)); limbs.addLine(to: pt(b))
        }
        context.stroke(limbs, with: shading, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
        let r = FigurePose.headRadius * scale
        let head = pt(joints.head)
        context.fill(Path(ellipseIn: CGRect(x: head.x - r, y: head.y - r, width: 2 * r, height: 2 * r)), with: shading)
    }

    private func drawHeld(_ pose: FigurePose, in context: inout GraphicsContext, pt: (CGPoint) -> CGPoint, scale: Double,
                          shading: GraphicsContext.Shading) {
        let hand = pt(pose.joints.hand)
        for item in pose.props {
            switch item {
            case .plate:
                let r = 4 * scale
                context.stroke(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading, lineWidth: 1.8 * scale)
            case .plateSmall:
                let r = 2 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading)
            case .dumbbell:
                context.fill(Path(roundedRect: CGRect(x: hand.x - 3.5 * scale, y: hand.y - 1.5 * scale, width: 7 * scale, height: 3 * scale), cornerRadius: scale), with: shading)
            case .wheel:
                let r = 4 * scale
                context.stroke(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading, lineWidth: 1.8 * scale)
            default:
                break
            }
        }
    }

    /// A filled arrowhead at `to`, pointing along the line from `from`.
    private func drawArrowhead(from: CGPoint, to: CGPoint, in context: inout GraphicsContext, scale: Double,
                               shading: GraphicsContext.Shading) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = hypot(dx, dy)
        guard length > 0.01 else { return }
        let ux = dx / length, uy = dy / length
        let size = 3.8 * scale, half = 2.1 * scale
        let base = CGPoint(x: to.x - ux * size, y: to.y - uy * size)
        var head = Path()
        head.move(to: to)
        head.addLine(to: CGPoint(x: base.x - uy * half, y: base.y + ux * half))
        head.addLine(to: CGPoint(x: base.x + uy * half, y: base.y - ux * half))
        head.closeSubpath()
        context.fill(head, with: shading)
    }
}

// MARK: - Muscle map

extension MuscleInvolvement {
    /// Green for the primary movers, yellow for the secondary, grey for stabilisers. System
    /// colours, so they adapt to dark mode; the outline style and the tier list carry the
    /// same information without colour.
    var color: Color {
        switch self {
        case .primary: .green
        case .secondary: .yellow
        case .stabiliser: .gray
        }
    }

    var fillOpacity: Double {
        switch self {
        case .primary: 0.95
        case .secondary: 0.9
        case .stabiliser: 0.5
        }
    }

    /// Primary regions get a solid outline, stabilisers a dashed one, secondary none.
    var dash: [CGFloat]? {
        switch self {
        case .primary: []
        case .secondary: nil
        case .stabiliser: [2, 1.6]
        }
    }
}

/// Front and back body outlines with the exercise's muscles coloured by tier, and a legend.
struct MuscleMap: View {
    var muscles: [MuscleWeight]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 24) {
                BodyCanvas(view: .front, muscles: muscles)
                BodyCanvas(view: .back, muscles: muscles)
            }
            HStack(spacing: 12) {
                ForEach(MuscleInvolvement.allCases) { tier in
                    HStack(spacing: 4) {
                        MuscleSwatch(tier: tier)
                        Text(tier.displayName)
                    }
                }
                HStack(spacing: 4) {
                    MuscleSwatch(tier: nil)
                    Text("Not worked")
                }
            }
            .font(.caption2).foregroundStyle(.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// The legend's and the tier list's sample of how a tier is drawn on the map.
struct MuscleSwatch: View {
    var tier: MuscleInvolvement?

    var body: some View {
        Circle()
            .fill(tier.map { $0.color.opacity($0.fillOpacity) } ?? Color.secondary.opacity(0.15))
            .overlay {
                if let dash = tier?.dash {
                    Circle().strokeBorder(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: dash.map { $0 * 1.5 }))
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

private struct BodyCanvas: View {
    enum Side { case front, back }
    var view: Side
    var muscles: [MuscleWeight]

    /// Regions in a 0...100 × 0...160 box (the canvas is 170 tall, leaving room for the caption
    /// under the feet), as (x, y, w, h) ellipses or rounded rects; `mirror` draws the same region
    /// on the other side of the body.
    private struct Region { var muscle: Muscle; var rect: CGRect; var mirror = true; var ellipse = true }

    private static let front: [Region] = [
        Region(muscle: .chest, rect: CGRect(x: 36, y: 26, width: 14, height: 14)),
        Region(muscle: .frontDelt, rect: CGRect(x: 27, y: 23, width: 9, height: 9)),
        Region(muscle: .sideDelt, rect: CGRect(x: 23, y: 25, width: 6, height: 10)),
        Region(muscle: .biceps, rect: CGRect(x: 26, y: 35, width: 7, height: 18)),
        Region(muscle: .forearms, rect: CGRect(x: 22, y: 55, width: 8, height: 24)),
        Region(muscle: .abs, rect: CGRect(x: 42, y: 42, width: 16, height: 32), mirror: false, ellipse: false),
        Region(muscle: .quads, rect: CGRect(x: 36, y: 84, width: 13, height: 38)),
        Region(muscle: .calves, rect: CGRect(x: 38, y: 128, width: 9, height: 24)),
    ]
    private static let back: [Region] = [
        Region(muscle: .upperBack, rect: CGRect(x: 38, y: 24, width: 24, height: 22), mirror: false),
        Region(muscle: .rearDelt, rect: CGRect(x: 27, y: 23, width: 9, height: 9)),
        Region(muscle: .sideDelt, rect: CGRect(x: 23, y: 25, width: 6, height: 10)),
        Region(muscle: .triceps, rect: CGRect(x: 26, y: 35, width: 7, height: 20)),
        Region(muscle: .forearms, rect: CGRect(x: 22, y: 55, width: 8, height: 24)),
        Region(muscle: .lats, rect: CGRect(x: 33, y: 40, width: 14, height: 28)),
        Region(muscle: .lowerBack, rect: CGRect(x: 42, y: 60, width: 16, height: 18), mirror: false),
        Region(muscle: .glutes, rect: CGRect(x: 36, y: 76, width: 14, height: 18)),
        Region(muscle: .hamstrings, rect: CGRect(x: 36, y: 96, width: 13, height: 30)),
        Region(muscle: .calves, rect: CGRect(x: 37, y: 128, width: 11, height: 26)),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 170)
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 170 * scale) / 2)
            func r(_ rect: CGRect) -> CGRect {
                CGRect(x: offset.x + rect.minX * scale, y: offset.y + rect.minY * scale, width: rect.width * scale, height: rect.height * scale)
            }
            func mirrored(_ rect: CGRect) -> CGRect { CGRect(x: 100 - rect.maxX, y: rect.minY, width: rect.width, height: rect.height) }

            // Outline: head, neck, torso, arms, legs.
            var outline = Path()
            outline.addEllipse(in: r(CGRect(x: 41, y: 2, width: 18, height: 18)))
            outline.addRect(r(CGRect(x: 46, y: 19, width: 8, height: 6)))
            outline.addRoundedRect(in: r(CGRect(x: 32, y: 23, width: 36, height: 58)), cornerSize: CGSize(width: 8 * scale, height: 8 * scale))
            for rect in [CGRect(x: 22, y: 24, width: 11, height: 56), CGRect(x: 67, y: 24, width: 11, height: 56),
                         CGRect(x: 35, y: 80, width: 14, height: 78), CGRect(x: 51, y: 80, width: 14, height: 78)] {
                outline.addRoundedRect(in: r(rect), cornerSize: CGSize(width: 5 * scale, height: 5 * scale))
            }
            context.fill(outline, with: .color(Color.secondary.opacity(0.15)))

            let tiers = Dictionary(muscles.compactMap { mw in mw.involvement.map { (mw.muscle, $0) } }, uniquingKeysWith: min)
            let outlineColor = GraphicsContext.Shading.color(Color.primary.opacity(0.55))
            for region in (view == .front ? Self.front : Self.back) {
                guard let tier = tiers[region.muscle] else { continue }
                var rects = [region.rect]
                if region.mirror { rects.append(mirrored(region.rect)) }
                for rect in rects {
                    let path = region.ellipse ? Path(ellipseIn: r(rect)) : Path(roundedRect: r(rect), cornerRadius: 3 * scale)
                    context.fill(path, with: .color(tier.color.opacity(tier.fillOpacity)))
                    if let dash = tier.dash {
                        context.stroke(path, with: outlineColor,
                                       style: StrokeStyle(lineWidth: 0.9 * scale, dash: dash.map { $0 * scale }))
                    }
                }
            }
            let label = Text(view == .front ? "Front" : "Back").font(.caption2).foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: size.width / 2, y: offset.y + 170 * scale), anchor: .bottom)
        }
    }
}

extension MovementPattern {
    /// Read out in place of the diagram.
    var accessibilityDescription: String {
        switch self {
        case .benchPress, .inclinePress: "lying on a bench, pressing a bar from the chest to straight arms"
        case .overheadPress: "standing, pressing a bar from the shoulders to overhead"
        case .dip: "on parallel bars, lowering until the upper arms are level and pressing back up"
        case .pushUp: "face down, lowering the chest to the floor and pressing back up"
        case .fly: "arms sweeping together in front of the chest with slightly bent elbows"
        case .bentRow: "bent over, pulling a weight from arm's length to the torso"
        case .supportedRow: "chest on a pad, pulling the elbows back"
        case .verticalPull: "hanging from a bar, pulling the chest up to it"
        case .straightArmPulldown: "straight arms sweeping from overhead down to the thighs"
        case .deadlift: "lifting a bar from the floor to standing"
        case .hinge: "standing, pushing the hips back and lowering the weight down the legs, then standing"
        case .backExtension: "hips on a pad, lowering the torso and raising it to level"
        case .shrug: "shoulders rising toward the ears"
        case .lateralRaise: "arms raising out to the sides to shoulder height"
        case .frontRaise: "arms raising in front to shoulder height"
        case .rearDeltFly: "bent over, arms raising out to the sides"
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
