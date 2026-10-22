import SwiftUI

// MARK: - Guide view

/// The animated "how to do it" diagram: a solid side-view figure looping through the lift with
/// the load's path traced and coaching callouts at each phase, and the guide's cues numbered
/// underneath with the current one highlighted. With Reduce Motion on, a slider scrubs the
/// lift instead of it playing.
struct MovementGuideView: View {
    var pattern: MovementPattern
    var implement: Implement
    var cues: [String]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrub = 0.0

    var body: some View {
        let keyframes = pattern.keyframes(for: implement)
        let motion = MovementMotion(keyframes: keyframes)
        if reduceMotion {
            VStack(alignment: .leading, spacing: 10) {
                content(progress: scrub, keyframes: keyframes, motion: motion)
                Slider(value: $scrub, in: 0...1) {
                    Text("Movement phase")
                } minimumValueLabel: {
                    Text("Start").font(.caption2)
                } maximumValueLabel: {
                    Text("Start").font(.caption2)
                }
                .tint(.accentColor)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                content(progress: MovementLoop.progress(at: context.date), keyframes: keyframes, motion: motion)
            }
        }
    }

    private func content(progress: Double, keyframes: [FigurePose], motion: MovementMotion) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MovementCanvas(pattern: pattern, keyframes: keyframes, motion: motion, progress: progress)
                .frame(height: 240)
                .background(MovementCanvas.panelBackground, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Diagram: \(pattern.accessibilityDescription)")
            StepList(cues: cues, current: MovementLoop.step(at: progress, count: cues.count))
        }
    }
}

/// The numbered cues, with the one the figure is on highlighted.
private struct StepList: View {
    var cues: [String]
    var current: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(cues.enumerated()), id: \.offset) { index, cue in
                let isCurrent = index == current
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(index + 1)")
                        .font(.callout.monospacedDigit().bold())
                        .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
                    Text(cue)
                        .foregroundStyle(isCurrent ? .primary : .secondary)
                }
                .padding(.vertical, 5).padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isCurrent ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }
}

// MARK: - Canvas

/// One frame of the figure at `progress` through the loop: equipment, the far limbs, the body,
/// the near limbs, the load, the traced path and the callouts that apply. The pose is in a
/// 0...100 square scaled to the view's height; the margins either side carry the callouts.
struct MovementCanvas: View {
    var pattern: MovementPattern
    var keyframes: [FigurePose]
    var motion: MovementMotion
    var progress: Double

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) / 100
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 100 * scale) / 2)
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: offset.x + p.x * scale, y: offset.y + p.y * scale) }
            func pt(_ x: Double, _ y: Double) -> CGPoint { pt(CGPoint(x: x, y: y)) }

            let lift = MovementLoop.liftFraction(at: progress)
            let pose = FigurePose.along(keyframes, lift)
            let j = pose.joints
            let near = GraphicsContext.Shading.color(Color.primary.opacity(0.9))
            let far = GraphicsContext.Shading.color(Color.primary.opacity(0.36))
            let prop = GraphicsContext.Shading.color(Color.secondary.opacity(0.5))
            let gear = GraphicsContext.Shading.color(Color.accentColor)
            let mark = GraphicsContext.Shading.color(Color.accentColor.opacity(0.9))

            // Equipment behind the figure.
            for item in pose.props {
                switch item {
                case .floor(let y):
                    context.stroke(Path { $0.move(to: pt(2, y)); $0.addLine(to: pt(98, y)) }, with: prop, lineWidth: 1.2 * scale)
                case .bench(let x1, let x2, let y):
                    context.fill(Path(roundedRect: CGRect(x: pt(x1, y).x, y: pt(x1, y).y, width: (x2 - x1) * scale, height: 4.5 * scale), cornerRadius: 1.5 * scale), with: prop)
                    for x in [x1 + 6, x2 - 6] {
                        context.stroke(Path { $0.move(to: pt(x, y + 4)); $0.addLine(to: pt(x, 92)) }, with: prop, lineWidth: 2.2 * scale)
                    }
                case .support(let x1, let y1, let x2, let y2):
                    context.stroke(Path { $0.move(to: pt(x1, y1)); $0.addLine(to: pt(x2, y2)) }, with: prop, style: StrokeStyle(lineWidth: 4 * scale, lineCap: .round))
                case .box(let x, let y, let w, let h):
                    context.fill(Path(roundedRect: CGRect(x: pt(x, y).x, y: pt(x, y).y, width: w * scale, height: h * scale), cornerRadius: 1.5 * scale), with: prop)
                case .rack(let x, let y):
                    let toward = x < 50 ? 1.0 : -1.0
                    context.stroke(Path { $0.move(to: pt(x, y - 8)); $0.addLine(to: pt(x, 92)) }, with: prop, lineWidth: 2.6 * scale)
                    context.stroke(Path { $0.move(to: pt(x, y)); $0.addLine(to: pt(x + 4.5 * toward, y)); $0.addLine(to: pt(x + 4.5 * toward, y - 3)) }, with: prop, style: StrokeStyle(lineWidth: 1.6 * scale, lineCap: .round, lineJoin: .round))
                case .rails:
                    for dx in [-2.2, 2.2] {
                        context.stroke(Path { $0.move(to: pt(j.hand.x + dx, 4)); $0.addLine(to: pt(j.hand.x + dx, 92)) }, with: prop, lineWidth: 1 * scale)
                    }
                case .cable(let x, let y):
                    context.stroke(Path { $0.move(to: pt(x, y)); $0.addLine(to: pt(j.hand)) }, with: gear, lineWidth: 0.9 * scale)
                    let r = 2.4 * scale
                    context.fill(Path(ellipseIn: CGRect(x: pt(x, y).x - r, y: pt(x, y).y - r, width: 2 * r, height: 2 * r)), with: prop)
                case .barOverhead(let y):
                    context.stroke(Path { $0.move(to: pt(18, y)); $0.addLine(to: pt(82, y)) }, with: prop, lineWidth: 2.5 * scale)
                case .post:
                    context.stroke(Path { $0.move(to: pt(j.hand)); $0.addLine(to: pt(j.hand.x, 92)) }, with: prop, lineWidth: 2.5 * scale)
                case .anklePad:
                    let c = pt(j.ankle)
                    context.fill(Path(roundedRect: CGRect(x: c.x - 2.2 * scale, y: c.y - 3.4 * scale, width: 4.4 * scale, height: 6.8 * scale), cornerRadius: 2 * scale), with: prop)
                case .plate, .plateSmall, .dumbbell, .kettlebell, .handle, .wheel:
                    break
                }
            }

            // The far arm and leg, a little behind and lighter, then the body, then the near limbs.
            let back = CGPoint(x: -1.4 * scale, y: 0.5 * scale)
            Self.drawLeg(pose, j, in: &context, pt: pt, scale: scale, shading: far, shift: back)
            Self.drawArm(pose, j, in: &context, pt: pt, scale: scale, shading: far, shift: back)
            Self.drawTorso(pose, j, in: &context, pt: pt, scale: scale, shading: near)
            Self.drawLeg(pose, j, in: &context, pt: pt, scale: scale, shading: near, shift: .zero)
            Self.drawArm(pose, j, in: &context, pt: pt, scale: scale, shading: near, shift: .zero)

            // What it holds.
            Self.drawLoad(pose, j, in: &context, pt: pt, scale: scale, shading: gear)

            // The load path: the whole arc faint and dashed, the part covered so far solid.
            let path = motion.path
            if path.count > 1, MovementMotion.distance(path[0], path[path.count - 1]) >= 1 {
                var whole = Path()
                whole.move(to: pt(path[0]))
                for p in path.dropFirst() { whole.addLine(to: pt(p)) }
                context.stroke(whole, with: .color(Color.accentColor.opacity(0.35)), style: StrokeStyle(lineWidth: 1.2 * scale, lineCap: .round, dash: [2 * scale, 2.2 * scale]))
                let covered = Int((Double(path.count - 1) * lift).rounded(.down))
                if covered >= 1 {
                    var done = Path()
                    done.move(to: pt(path[0]))
                    for p in path[1...covered] { done.addLine(to: pt(p)) }
                    context.stroke(done, with: mark, style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round, lineJoin: .round))
                }
                let r = 1.5 * scale
                context.fill(Path(ellipseIn: CGRect(x: pt(path[0]).x - r, y: pt(path[0]).y - r, width: 2 * r, height: 2 * r)), with: mark)
            }

            // Callouts for this phase.
            for callout in pattern.callouts {
                let opacity = callout.phase.opacity(at: progress)
                guard opacity > 0.01 else { continue }
                var layer = context
                layer.opacity = opacity
                Self.drawCallout(callout, anchor: pt(callout.point(in: pose)), in: &layer, canvas: size, scale: scale)
            }
        }
    }

    /// System backgrounds; the macOS branch only serves the offline renderer used while
    /// tuning the figure.
    static var panelBackground: Color {
        #if canImport(UIKit)
        Color(.secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }

    private static var bubbleBackground: Color {
        #if canImport(UIKit)
        Color(.systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    // MARK: Body parts

    /// A limb segment: a rounded shape from `a` to `b`, `wa` wide at `a` and `wb` at `b`.
    private static func segment(_ a: CGPoint, _ b: CGPoint, _ wa: Double, _ wb: Double) -> Path {
        let dx = b.x - a.x, dy = b.y - a.y
        let length = max(hypot(dx, dy), 0.001)
        let ux = dx / length, uy = dy / length
        let nx = -uy, ny = ux
        var path = Path()
        path.move(to: CGPoint(x: a.x + nx * wa / 2, y: a.y + ny * wa / 2))
        path.addLine(to: CGPoint(x: b.x + nx * wb / 2, y: b.y + ny * wb / 2))
        path.addQuadCurve(to: CGPoint(x: b.x - nx * wb / 2, y: b.y - ny * wb / 2), control: CGPoint(x: b.x + ux * wb, y: b.y + uy * wb))
        path.addLine(to: CGPoint(x: a.x - nx * wa / 2, y: a.y - ny * wa / 2))
        path.addQuadCurve(to: CGPoint(x: a.x + nx * wa / 2, y: a.y + ny * wa / 2), control: CGPoint(x: a.x - ux * wa, y: a.y - uy * wa))
        path.closeSubpath()
        return path
    }

    private static func shifted(_ p: CGPoint, _ by: CGPoint) -> CGPoint { CGPoint(x: p.x + by.x, y: p.y + by.y) }

    private static func drawTorso(_ pose: FigurePose, _ j: FigurePose.Joints, in context: inout GraphicsContext,
                                  pt: (CGPoint) -> CGPoint, scale: Double, shading: GraphicsContext.Shading) {
        // Pelvis to chest, the chest a little deeper than the hips; then the neck and head.
        context.fill(segment(pt(pose.hip), pt(j.shoulder), 8.6 * scale, 10 * scale), with: shading)
        context.fill(segment(pt(j.shoulder), pt(j.neck), 4.2 * scale, 3.6 * scale), with: shading)
        let head = pt(j.head)
        let rx = 4.5 * scale, ry = 5.1 * scale
        var skull = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry))
        skull = skull.applying(CGAffineTransform(translationX: head.x, y: head.y).rotated(by: pose.torso * .pi / 180))
        context.fill(skull, with: shading)
    }

    private static func drawLeg(_ pose: FigurePose, _ j: FigurePose.Joints, in context: inout GraphicsContext,
                                pt: (CGPoint) -> CGPoint, scale: Double, shading: GraphicsContext.Shading, shift: CGPoint) {
        let hip = shifted(pt(pose.hip), shift), knee = shifted(pt(j.knee), shift), ankle = shifted(pt(j.ankle), shift)
        let heel = shifted(pt(j.heel), shift), toe = shifted(pt(j.toe), shift)
        context.fill(segment(hip, knee, 7.2 * scale, 5.2 * scale), with: shading)
        context.fill(segment(knee, ankle, 5 * scale, 3.4 * scale), with: shading)
        context.fill(segment(heel, toe, 3 * scale, 1.8 * scale), with: shading)
    }

    private static func drawArm(_ pose: FigurePose, _ j: FigurePose.Joints, in context: inout GraphicsContext,
                                pt: (CGPoint) -> CGPoint, scale: Double, shading: GraphicsContext.Shading, shift: CGPoint) {
        let shoulder = shifted(pt(j.shoulder), shift), elbow = shifted(pt(j.elbow), shift), hand = shifted(pt(j.hand), shift)
        context.fill(segment(shoulder, elbow, 4.6 * scale, 3.8 * scale), with: shading)
        context.fill(segment(elbow, hand, 3.6 * scale, 2.6 * scale), with: shading)
        let r = 1.9 * scale
        context.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading)
    }

    private static func drawLoad(_ pose: FigurePose, _ j: FigurePose.Joints, in context: inout GraphicsContext,
                                 pt: (CGPoint) -> CGPoint, scale: Double, shading: GraphicsContext.Shading) {
        let hand = pt(j.hand)
        let faint = GraphicsContext.Shading.color(Color.accentColor.opacity(0.25))
        for item in pose.props {
            switch item {
            case .plate:
                // A bar seen end-on: the plate, the collar, the bar.
                let r = 5 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: faint)
                context.stroke(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading, lineWidth: 1.6 * scale)
                let c = 2 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - c, y: hand.y - c, width: 2 * c, height: 2 * c)), with: shading)
            case .plateSmall, .handle:
                let r = 2.1 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading)
            case .dumbbell:
                // Handle across the forearm, a plate at each end.
                let a = (pose.forearm + 90) * .pi / 180
                let ux = sin(a), uy = -cos(a)
                let vx = -uy, vy = ux
                let half = 3.4 * scale
                context.stroke(Path { $0.move(to: CGPoint(x: hand.x - ux * half, y: hand.y - uy * half)); $0.addLine(to: CGPoint(x: hand.x + ux * half, y: hand.y + uy * half)) },
                               with: shading, style: StrokeStyle(lineWidth: 1.8 * scale, lineCap: .round))
                for side in [-1.0, 1.0] {
                    let c = CGPoint(x: hand.x + ux * half * side, y: hand.y + uy * half * side)
                    let plate = 2.6 * scale
                    context.stroke(Path { $0.move(to: CGPoint(x: c.x - vx * plate, y: c.y - vy * plate)); $0.addLine(to: CGPoint(x: c.x + vx * plate, y: c.y + vy * plate)) },
                                   with: shading, style: StrokeStyle(lineWidth: 2.4 * scale, lineCap: .round))
                }
            case .kettlebell:
                let ring = 2.3 * scale
                context.stroke(Path(ellipseIn: CGRect(x: hand.x - ring, y: hand.y - ring, width: 2 * ring, height: 2 * ring)), with: shading, lineWidth: 1.2 * scale)
                let r = 3.8 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y + 2.2 * scale, width: 2 * r, height: 2 * r)), with: shading)
            case .wheel:
                let r = 4 * scale
                context.stroke(Path(ellipseIn: CGRect(x: hand.x - r, y: hand.y - r, width: 2 * r, height: 2 * r)), with: shading, lineWidth: 1.8 * scale)
                let c = 1.2 * scale
                context.fill(Path(ellipseIn: CGRect(x: hand.x - c, y: hand.y - c, width: 2 * c, height: 2 * c)), with: shading)
            default:
                break
            }
        }
    }

    // MARK: Callouts

    private static func drawCallout(_ callout: Callout, anchor: CGPoint, in context: inout GraphicsContext, canvas: CGSize, scale: Double) {
        let text = context.resolve(Text(callout.text).font(.caption2.weight(.medium)).foregroundStyle(Color.primary))
        let textSize = text.measure(in: CGSize(width: 118, height: 60))
        let padding = 5.0
        let box = CGSize(width: textSize.width + 2 * padding, height: textSize.height + 2 * padding)
        let gap = 12 * scale
        var centre: CGPoint
        switch callout.placement {
        case .left: centre = CGPoint(x: anchor.x - gap - box.width / 2, y: anchor.y)
        case .right: centre = CGPoint(x: anchor.x + gap + box.width / 2, y: anchor.y)
        case .above: centre = CGPoint(x: anchor.x, y: anchor.y - gap - box.height / 2)
        case .below: centre = CGPoint(x: anchor.x, y: anchor.y + gap + box.height / 2)
        }
        centre.x = min(max(centre.x, box.width / 2 + 2), canvas.width - box.width / 2 - 2)
        centre.y = min(max(centre.y, box.height / 2 + 2), canvas.height - box.height / 2 - 2)
        let rect = CGRect(x: centre.x - box.width / 2, y: centre.y - box.height / 2, width: box.width, height: box.height)

        // Leader from the nearest edge of the bubble to the joint, with a dot on the joint.
        let edge = CGPoint(x: min(max(anchor.x, rect.minX), rect.maxX), y: min(max(anchor.y, rect.minY), rect.maxY))
        let leader = GraphicsContext.Shading.color(Color.accentColor.opacity(0.8))
        context.stroke(Path { $0.move(to: edge); $0.addLine(to: anchor) }, with: leader, lineWidth: 1)
        let r = 2.2
        context.fill(Path(ellipseIn: CGRect(x: anchor.x - r, y: anchor.y - r, width: 2 * r, height: 2 * r)), with: leader)
        let bubble = Path(roundedRect: rect, cornerRadius: 6)
        context.fill(bubble, with: .color(bubbleBackground.opacity(0.92)))
        context.stroke(bubble, with: .color(Color.accentColor.opacity(0.5)), lineWidth: 0.8)
        context.draw(text, at: centre, anchor: .center)
    }
}
