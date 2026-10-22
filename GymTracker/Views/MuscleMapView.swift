import SwiftUI

// MARK: - Tier colours

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

    /// Translucent, so the body reads through the highlight.
    var fillOpacity: Double {
        switch self {
        case .primary: 0.8
        case .secondary: 0.85
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

// MARK: - Map

/// Front and back body figures with the exercise's muscles coloured by tier, and a legend.
struct MuscleMap: View {
    var muscles: [MuscleWeight]

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 24) {
                BodyCanvas(side: .front, muscles: muscles)
                BodyCanvas(side: .back, muscles: muscles)
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
            .fill(tier.map { $0.color.opacity($0.fillOpacity) } ?? BodyFigure.silhouetteFill)
            .overlay {
                if let dash = tier?.dash {
                    Circle().strokeBorder(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: dash.map { $0 * 1.5 }))
                } else if tier == nil {
                    Circle().strokeBorder(BodyFigure.silhouetteStroke, lineWidth: 0.8)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - Figure geometry

/// A standing figure in a 0...100 × 0...170 box (the body spans y 2...161, the caption sits
/// under the feet), traced as one smooth outline, and the muscle regions placed on it. The
/// left half is drawn and mirrored, so the figure is symmetric. Proportions follow a 7½-head
/// body: shoulders wider than the hips, a tapered torso, arms held a little away from the sides.
nonisolated enum BodyFigure {
    enum Side: Hashable, Sendable { case front, back }

    static let silhouetteFill = Color.secondary.opacity(0.17)
    static let silhouetteStroke = Color.secondary.opacity(0.55)

    /// The left half of the outline, top of the head to the crotch, in order. Mirrored and
    /// reversed for the right half, then smoothed into a closed curve.
    private static let leftOutline: [CGPoint] = [
        // Head, jaw, neck.
        (50, 2.5), (45.8, 3.6), (43.0, 7.5), (42.6, 12.5), (43.8, 17.5), (46.4, 21.0), (47.0, 24.5), (46.4, 27.0),
        // Trapezius slope and shoulder cap.
        (41.0, 29.0), (34.0, 31.0), (28.8, 32.8), (25.6, 35.8), (24.2, 40.0),
        // Upper arm, outside.
        (23.2, 47.0), (22.2, 54.0), (21.3, 61.0),
        // Forearm, outside, to the wrist.
        (20.0, 69.0), (18.8, 77.0), (17.9, 84.0), (17.4, 89.0),
        // Hand.
        (16.7, 93.0), (17.3, 97.5), (19.8, 98.6), (22.3, 95.6), (23.5, 90.0),
        // Forearm, inside.
        (25.0, 83.0), (26.6, 75.0), (27.7, 67.0), (28.5, 61.0),
        // Upper arm, inside, up to the armpit.
        (29.5, 53.0), (30.4, 46.0), (31.8, 40.6),
        // Torso side: chest, waist, hip.
        (33.6, 46.0), (34.8, 54.0), (36.2, 62.0), (35.6, 70.0), (34.4, 78.0),
        // Outer thigh, knee, calf, ankle.
        (35.0, 86.0), (36.0, 94.0), (36.9, 102.0), (37.3, 110.0), (37.7, 118.0), (37.6, 125.0), (36.7, 133.0), (37.3, 141.0), (39.0, 148.0), (40.4, 153.0),
        // Foot.
        (38.4, 156.5), (39.4, 160.5), (46.0, 161.0), (47.4, 156.0), (47.0, 151.0),
        // Inner calf, knee, thigh, up to the crotch.
        (46.4, 144.0), (45.6, 136.0), (45.4, 128.0), (46.0, 121.0), (46.3, 112.0), (46.0, 103.0), (46.5, 95.0), (48.2, 89.0), (50, 86.5),
    ].map { CGPoint(x: $0.0, y: $0.1) }

    /// The whole outline, closed and smoothed, in box coordinates.
    static let silhouette: Path = {
        let left = leftOutline
        let right = left.dropFirst().dropLast().reversed().map { CGPoint(x: 100 - $0.x, y: $0.y) }
        return smoothClosed(left + right)
    }()

    /// One muscle's shape on one side of the body, in box coordinates. Regions on the left
    /// are mirrored to the right unless they sit on the midline.
    struct Region: Sendable {
        var muscle: Muscle
        var path: Path
        var mirrored: Bool

        /// Both copies, left and right.
        var paths: [Path] {
            mirrored ? [path, path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: 100, ty: 0))] : [path]
        }
    }

    static func regions(_ side: Side) -> [Region] {
        switch side {
        case .front: front
        case .back: back
        }
    }

    // Upper arm runs from the shoulder (27.5, 38) to the elbow (25, 61); forearm from there to
    // the wrist (20.5, 89). Thigh from the hip (41, 84) to the knee (41.7, 120); calf to the
    // ankle (43.5, 152).
    private static let armTilt = 6.0
    private static let forearmTilt = 10.0

    static let front: [Region] = [
        // Upper traps, the sliver visible beside the neck from the front.
        Region(muscle: .upperBack, path: smoothClosed([(45.8, 26.6), (46.0, 29.2), (39.0, 31.6), (38.4, 30.8), (42.2, 29.0)].pts), mirrored: true),
        Region(muscle: .sideDelt, path: ellipse(cx: 27.6, cy: 38.6, rx: 2.1, ry: 4.8, rotation: 12), mirrored: true),
        Region(muscle: .frontDelt, path: ellipse(cx: 31.6, cy: 36.6, rx: 2.8, ry: 4.6, rotation: 4), mirrored: true),
        // Pec: from the collarbone down to the lower chest line, squared off at the sternum.
        Region(muscle: .chest, path: smoothClosed([(35.0, 36.8), (48.8, 34.6), (49.0, 46.6), (44.4, 50.0), (37.6, 48.6), (33.8, 43.0)].pts), mirrored: true),
        Region(muscle: .biceps, path: ellipse(cx: 26.9, cy: 49.5, rx: 2.5, ry: 7.4, rotation: armTilt), mirrored: true),
        Region(muscle: .forearms, path: ellipse(cx: 23.2, cy: 75.0, rx: 2.7, ry: 10.5, rotation: forearmTilt), mirrored: true),
        // Rectus abdominis: a tapered block from under the chest to the belt line.
        Region(muscle: .abs, path: smoothClosed([(44.2, 51.2), (55.8, 51.2), (56.0, 60.0), (55.0, 71.0), (52.0, 75.5), (48.0, 75.5), (45.0, 71.0), (44.0, 60.0)].pts), mirrored: false),
        Region(muscle: .quads, path: ellipse(cx: 41.0, cy: 101.0, rx: 4.6, ry: 15.0, rotation: -2), mirrored: true),
        // The inner head of the calf shows from the front.
        Region(muscle: .calves, path: ellipse(cx: 43.6, cy: 134.0, rx: 1.9, ry: 8.0, rotation: -3), mirrored: true),
    ]

    static let back: [Region] = [
        // Traps and rhomboids: a kite from the neck to the shoulders and down the spine.
        Region(muscle: .upperBack, path: smoothClosed([(50, 25.6), (36.0, 31.0), (42.4, 42.0), (50, 55.0), (57.6, 42.0), (64.0, 31.0)].pts), mirrored: false),
        Region(muscle: .sideDelt, path: ellipse(cx: 27.6, cy: 38.6, rx: 2.1, ry: 4.8, rotation: 12), mirrored: true),
        Region(muscle: .rearDelt, path: ellipse(cx: 31.4, cy: 36.8, rx: 2.8, ry: 4.6, rotation: 4), mirrored: true),
        Region(muscle: .triceps, path: ellipse(cx: 26.6, cy: 50.0, rx: 2.5, ry: 8.0, rotation: armTilt), mirrored: true),
        Region(muscle: .forearms, path: ellipse(cx: 23.2, cy: 75.0, rx: 2.7, ry: 10.5, rotation: forearmTilt), mirrored: true),
        // Lats: from under the armpit, sweeping in toward the waist.
        Region(muscle: .lats, path: smoothClosed([(33.6, 43.6), (40.6, 47.0), (44.0, 59.0), (43.0, 70.0), (38.6, 67.0), (34.6, 57.0)].pts), mirrored: true),
        // Erectors: two columns either side of the spine.
        Region(muscle: .lowerBack, path: Path(roundedRect: CGRect(x: 45.4, y: 59.0, width: 3.6, height: 19.0), cornerRadius: 1.6), mirrored: true),
        Region(muscle: .glutes, path: ellipse(cx: 42.4, cy: 85.0, rx: 5.6, ry: 6.4, rotation: 14), mirrored: true),
        Region(muscle: .hamstrings, path: ellipse(cx: 41.6, cy: 105.0, rx: 4.3, ry: 13.0, rotation: -1), mirrored: true),
        Region(muscle: .calves, path: ellipse(cx: 42.4, cy: 133.5, rx: 3.6, ry: 10.0, rotation: -3), mirrored: true),
    ]

    // MARK: Shape helpers

    static func ellipse(cx: Double, cy: Double, rx: Double, ry: Double, rotation degrees: Double) -> Path {
        let transform = CGAffineTransform(translationX: cx, y: cy).rotated(by: degrees * .pi / 180)
        return Path(ellipseIn: CGRect(x: -rx, y: -ry, width: 2 * rx, height: 2 * ry)).applying(transform)
    }

    /// A closed Catmull-Rom spline through the points, as cubic Béziers.
    static func smoothClosed(_ points: [CGPoint]) -> Path {
        var path = Path()
        let n = points.count
        guard n > 2 else { return path }
        path.move(to: points[0])
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }
}

nonisolated private extension Array where Element == (Double, Double) {
    var pts: [CGPoint] { map { CGPoint(x: $0.0, y: $0.1) } }
}

// MARK: - Canvas

private struct BodyCanvas: View {
    var side: BodyFigure.Side
    var muscles: [MuscleWeight]

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 100, size.height / 170)
            let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 170 * scale) / 2)
            let transform = CGAffineTransform(translationX: offset.x, y: offset.y).scaledBy(x: scale, y: scale)

            let silhouette = BodyFigure.silhouette.applying(transform)
            context.fill(silhouette, with: .color(BodyFigure.silhouetteFill))
            context.stroke(silhouette, with: .color(BodyFigure.silhouetteStroke),
                           style: StrokeStyle(lineWidth: 0.7 * scale, lineJoin: .round))

            let tiers = Dictionary(muscles.compactMap { mw in mw.involvement.map { (mw.muscle, $0) } }, uniquingKeysWith: min)
            let outline = GraphicsContext.Shading.color(Color.primary.opacity(0.5))
            for region in BodyFigure.regions(side) {
                guard let tier = tiers[region.muscle] else { continue }
                for path in region.paths {
                    let scaled = path.applying(transform)
                    context.fill(scaled, with: .color(tier.color.opacity(tier.fillOpacity)))
                    if let dash = tier.dash {
                        context.stroke(scaled, with: outline, style: StrokeStyle(lineWidth: 0.7 * scale, dash: dash.map { $0 * scale }))
                    }
                }
            }
            let label = Text(side == .front ? "Front" : "Back").font(.caption2).foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: size.width / 2, y: offset.y + 170 * scale), anchor: .bottom)
        }
    }
}
