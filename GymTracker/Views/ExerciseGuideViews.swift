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
