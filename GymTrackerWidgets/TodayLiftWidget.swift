import SwiftUI
import WidgetKit

/// Today's program day and its headline lift on the home screen; the lift alone on the
/// lock screen. Tapping opens the Today tab.
struct TodayLiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodayLift", provider: SnapshotProvider()) { entry in
            TodayLiftView(lift: entry.snapshot.lift)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetLink.today)
        }
        .configurationDisplayName("Today's lift")
        .description("The next workout and what the headline lift calls for.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayLiftView: View {
    var lift: LiftSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let lift {
            switch family {
            case .systemMedium: medium(lift)
            case .accessoryRectangular: rectangular(lift)
            case .accessoryInline: inline(lift)
            default: small(lift)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryInline:
            Label("No plan yet", systemImage: "dumbbell")
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("No plan yet", systemImage: "dumbbell").font(.headline)
                Text("Open GymTracker to set up a program.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func small(_ lift: LiftSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            header(lift, compact: true)
            if let reason = lift.headlineReason {
                Text(reason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if let headline = lift.headline {
                Text(headline.name).font(.headline).lineLimit(2).minimumScaleFactor(0.8)
                Text(headline.detail).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                if let badge = headline.badge { Badge(text: badge) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func medium(_ lift: LiftSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            header(lift)
            ForEach(lift.lines.prefix(4)) { line in
                HStack(spacing: 6) {
                    Text(line.name).font(.subheadline.weight(.medium)).lineLimit(1)
                    if let badge = line.badge { Badge(text: badge) }
                    Spacer(minLength: 4)
                    Text(line.detail).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            if lift.lines.count > 4 {
                Text("+\(lift.lines.count - 4) more").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func rectangular(_ lift: LiftSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(lift.inProgress ? "Continue \(lift.dayName)" : lift.dayName,
                  systemImage: lift.inProgress ? "play.fill" : "dumbbell")
                .font(.headline).widgetAccentable().lineLimit(1)
            if let headline = lift.headline {
                Text(headline.name).font(.subheadline).lineLimit(1)
                Text(headline.detail).font(.caption.monospacedDigit()).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ lift: LiftSnapshot) -> some View {
        let text = lift.headline.map { "\(lift.dayName) · \($0.name) \($0.detail)" } ?? lift.dayName
        return Label(text, systemImage: "dumbbell")
    }

    /// The play icon alone says "continue" where the small widget has no room for the word.
    private func header(_ lift: LiftSnapshot, compact: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lift.inProgress ? "play.fill" : "dumbbell")
            Text(lift.inProgress && !compact ? "Continue · \(lift.dayName)" : lift.dayName)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(WidgetTheme.accent)
        .lineLimit(1)
    }
}

struct Badge: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.orange.opacity(0.2), in: Capsule())
            .foregroundStyle(.orange)
            .lineLimit(1)
    }
}

#Preview("Small", as: .systemSmall) { TodayLiftWidget() } timeline: { SnapshotEntry.sample }
#Preview("Medium", as: .systemMedium) { TodayLiftWidget() } timeline: { SnapshotEntry.sample }
#Preview("Lock screen", as: .accessoryRectangular) { TodayLiftWidget() } timeline: { SnapshotEntry.sample }
