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

    /// Translucent, so the illustration reads through the highlight.
    var fillOpacity: Double {
        switch self {
        case .primary: 0.6
        case .secondary: 0.62
        case .stabiliser: 0.48
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
            .fill(tier.map { $0.color.opacity($0.fillOpacity) } ?? Color.secondary.opacity(0.15))
            .overlay {
                if let dash = tier?.dash {
                    Circle().strokeBorder(Color.primary.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: dash.map { $0 * 1.5 }))
                } else if tier == nil {
                    Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 0.8)
                }
            }
            .frame(width: 10, height: 10)
            .accessibilityHidden(true)
    }
}

// MARK: - Figure

/// The two anatomical plates the map is drawn on (Julien Bouglé, 1899, public domain; see
/// Resources/ATTRIBUTIONS.md) and the muscle regions traced onto them. Regions are in each
/// plate's own pixel coordinates, so they scale with the image. The plates are not mirror
/// images (each shows a deeper dissection on one side), so every region is traced on both
/// sides by hand.
nonisolated enum BodyFigure {
    enum Side: Hashable, Sendable, CaseIterable {
        case front, back

        var assetName: String {
            switch self {
            case .front: "MuscleFront"
            case .back: "MuscleBack"
            }
        }

        /// The plate's pixel size, which is the coordinate space of its regions.
        var imageSize: CGSize {
            switch self {
            case .front: CGSize(width: 506, height: 1500)
            case .back: CGSize(width: 499, height: 1500)
            }
        }
    }

    /// One muscle's shape on one side of the body, in the plate's pixel coordinates.
    struct Region: Sendable {
        var muscle: Muscle
        var path: Path
    }

    static func regions(_ side: Side) -> [Region] {
        switch side {
        case .front: front
        case .back: back
        }
    }

    // Front plate, 506 × 1500. The figure's right side is on the image's left.
    static let front: [Region] = [
        // Upper trapezius, the sliver between the neck and each shoulder.
        Region(muscle: .upperBack, path: smoothClosed([(164, 262), (226, 236), (230, 250), (170, 276)].pts)),
        Region(muscle: .upperBack, path: smoothClosed([(276, 236), (338, 262), (332, 276), (272, 250)].pts)),
        Region(muscle: .sideDelt, path: ellipse(cx: 76, cy: 322, rx: 12, ry: 40, rotation: -12)),
        Region(muscle: .sideDelt, path: ellipse(cx: 432, cy: 322, rx: 12, ry: 40, rotation: 12)),
        Region(muscle: .frontDelt, path: ellipse(cx: 92, cy: 302, rx: 21, ry: 31, rotation: -15)),
        Region(muscle: .frontDelt, path: ellipse(cx: 418, cy: 302, rx: 21, ry: 31, rotation: 15)),
        // Pectoralis major: clavicle to the lower chest line, squared off at the sternum.
        Region(muscle: .chest, path: smoothClosed([(128, 274), (246, 264), (248, 396), (206, 406), (156, 382), (122, 326)].pts)),
        Region(muscle: .chest, path: smoothClosed([(262, 264), (386, 272), (392, 330), (384, 370), (330, 396), (262, 400)].pts)),
        Region(muscle: .biceps, path: ellipse(cx: 90, cy: 405, rx: 20, ry: 60, rotation: -8)),
        Region(muscle: .biceps, path: ellipse(cx: 418, cy: 405, rx: 20, ry: 60, rotation: 8)),
        Region(muscle: .forearms, path: ellipse(cx: 72, cy: 615, rx: 26, ry: 95, rotation: -6)),
        Region(muscle: .forearms, path: ellipse(cx: 436, cy: 615, rx: 26, ry: 95, rotation: 6)),
        // Rectus abdominis.
        Region(muscle: .abs, path: smoothClosed([(212, 420), (300, 420), (304, 540), (300, 650), (282, 700), (232, 700), (212, 650), (208, 540)].pts)),
        Region(muscle: .quads, path: smoothClosed([(112, 832), (166, 816), (222, 852), (226, 960), (206, 1040), (144, 1045), (112, 960), (104, 892)].pts)),
        Region(muscle: .quads, path: smoothClosed([(282, 852), (340, 816), (396, 832), (404, 892), (396, 960), (364, 1045), (302, 1040), (280, 960)].pts)),
        // The inner head of the calf shows from the front.
        Region(muscle: .calves, path: ellipse(cx: 200, cy: 1200, rx: 14, ry: 80, rotation: 0)),
        Region(muscle: .calves, path: ellipse(cx: 305, cy: 1200, rx: 14, ry: 80, rotation: 0)),
    ]

    // Back plate, 499 × 1500.
    static let back: [Region] = [
        // Trapezius and rhomboids: neck to the shoulder points, down to mid back.
        Region(muscle: .upperBack, path: smoothClosed([(250, 162), (190, 216), (112, 290), (142, 330), (202, 400), (250, 540), (298, 400), (358, 330), (388, 290), (310, 216)].pts)),
        Region(muscle: .sideDelt, path: ellipse(cx: 74, cy: 324, rx: 12, ry: 40, rotation: -12)),
        Region(muscle: .sideDelt, path: ellipse(cx: 426, cy: 324, rx: 12, ry: 40, rotation: 12)),
        Region(muscle: .rearDelt, path: ellipse(cx: 95, cy: 305, rx: 24, ry: 40, rotation: -15)),
        Region(muscle: .rearDelt, path: ellipse(cx: 405, cy: 305, rx: 24, ry: 40, rotation: 15)),
        Region(muscle: .triceps, path: ellipse(cx: 85, cy: 410, rx: 22, ry: 65, rotation: -6)),
        Region(muscle: .triceps, path: ellipse(cx: 415, cy: 410, rx: 22, ry: 65, rotation: 6)),
        Region(muscle: .forearms, path: ellipse(cx: 62, cy: 615, rx: 26, ry: 95, rotation: -8)),
        Region(muscle: .forearms, path: ellipse(cx: 440, cy: 615, rx: 26, ry: 95, rotation: 8)),
        // Latissimus: from under the armpit, sweeping in to the waist.
        Region(muscle: .lats, path: smoothClosed([(118, 340), (190, 380), (225, 430), (232, 560), (210, 640), (150, 600), (118, 500), (105, 400)].pts)),
        Region(muscle: .lats, path: smoothClosed([(381, 340), (394, 400), (381, 500), (349, 600), (289, 640), (267, 560), (274, 430), (309, 380)].pts)),
        // Erector spinae, either side of the spine.
        Region(muscle: .lowerBack, path: Path(roundedRect: CGRect(x: 218, y: 470, width: 28, height: 220), cornerRadius: 12)),
        Region(muscle: .lowerBack, path: Path(roundedRect: CGRect(x: 254, y: 470, width: 28, height: 220), cornerRadius: 12)),
        Region(muscle: .glutes, path: smoothClosed([(105, 690), (185, 680), (238, 720), (240, 820), (200, 860), (140, 860), (100, 800)].pts)),
        Region(muscle: .glutes, path: smoothClosed([(395, 690), (315, 680), (262, 720), (260, 820), (300, 860), (360, 860), (400, 800)].pts)),
        Region(muscle: .hamstrings, path: smoothClosed([(120, 870), (200, 880), (232, 920), (228, 1040), (200, 1090), (150, 1090), (118, 1000)].pts)),
        Region(muscle: .hamstrings, path: smoothClosed([(380, 870), (300, 880), (268, 920), (272, 1040), (300, 1090), (350, 1090), (382, 1000)].pts)),
        Region(muscle: .calves, path: ellipse(cx: 172, cy: 1210, rx: 44, ry: 105, rotation: 0)),
        Region(muscle: .calves, path: ellipse(cx: 325, cy: 1210, rx: 44, ry: 105, rotation: 0)),
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
            let image = side.imageSize
            let captionHeight = 14.0
            let scale = min(size.width / image.width, (size.height - captionHeight) / image.height)
            let fitted = CGRect(x: (size.width - image.width * scale) / 2, y: (size.height - captionHeight - image.height * scale) / 2,
                                width: image.width * scale, height: image.height * scale)
            let transform = CGAffineTransform(translationX: fitted.minX, y: fitted.minY).scaledBy(x: scale, y: scale)

            context.draw(Self.plate(side), in: fitted)

            let tiers = Dictionary(muscles.compactMap { mw in mw.involvement.map { (mw.muscle, $0) } }, uniquingKeysWith: min)
            let outline = GraphicsContext.Shading.color(Color.primary.opacity(0.65))
            for region in BodyFigure.regions(side) {
                guard let tier = tiers[region.muscle] else { continue }
                let scaled = region.path.applying(transform)
                context.fill(scaled, with: .color(tier.color.opacity(tier.fillOpacity)))
                if let dash = tier.dash {
                    context.stroke(scaled, with: outline, style: StrokeStyle(lineWidth: 1, dash: dash.map { $0 * 1.6 }))
                }
            }
            let label = Text(side == .front ? "Front" : "Back").font(.caption2).foregroundStyle(.secondary)
            context.draw(label, at: CGPoint(x: size.width / 2, y: size.height), anchor: .bottom)
        }
    }

    /// The plate from the asset catalogue. The macOS branch exists only for the offline
    /// renderer used while tracing regions; it reads the PNGs from MUSCLE_IMAGE_DIR.
    static func plate(_ side: BodyFigure.Side) -> Image {
        #if canImport(UIKit)
        return Image(side.assetName)
        #else
        let dir = ProcessInfo.processInfo.environment["MUSCLE_IMAGE_DIR"] ?? "."
        return Image(nsImage: NSImage(contentsOfFile: "\(dir)/\(side.assetName).png") ?? NSImage())
        #endif
    }
}
