import SwiftUI
import WidgetKit

/// Calories eaten against today's target, with protein underneath where there is room.
/// Tapping opens the Nutrition tab.
struct CaloriesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Calories", provider: SnapshotProvider()) { entry in
            CaloriesView(nutrition: entry.snapshot.nutrition)
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetLink.nutrition)
        }
        .configurationDisplayName("Calories")
        .description("Today's calories and protein against your target.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct CaloriesView: View {
    var nutrition: NutritionWidgetSnapshot?
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let nutrition {
            switch family {
            case .accessoryCircular: circular(nutrition)
            case .accessoryRectangular: rectangular(nutrition)
            case .accessoryInline: inline(nutrition)
            default: small(nutrition)
            }
        } else {
            empty
        }
    }

    @ViewBuilder private var empty: some View {
        switch family {
        case .accessoryInline:
            Label("No target yet", systemImage: "fork.knife")
        case .accessoryCircular:
            Image(systemName: "fork.knife").font(.title2)
        default:
            VStack(alignment: .leading, spacing: 4) {
                Label("No target yet", systemImage: "fork.knife").font(.headline)
                Text("Open GymTracker to set one up.").font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func small(_ n: NutritionWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Calories", systemImage: "fork.knife")
                .font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
            Spacer(minLength: 0)
            Text(WidgetFormat.whole(n.eatenKcal))
                .font(.system(.title, design: .rounded).weight(.bold).monospacedDigit())
                .foregroundStyle(over(n.eatenKcal, n.targetKcal) ? .orange : .primary)
                .contentTransition(.numericText())
            Text("of \(WidgetFormat.whole(n.targetKcal)) kcal\(n.isProvisional ? " (est.)" : "")")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            bar(n.eatenKcal, n.targetKcal)
            HStack {
                Text("Protein").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(WidgetFormat.whole(n.eatenProtein)) / \(WidgetFormat.whole(n.targetProtein)) g")
                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func circular(_ n: NutritionWidgetSnapshot) -> some View {
        Gauge(value: min(n.eatenKcal, n.targetKcal), in: 0...max(n.targetKcal, 1)) {
            Text("kcal")
        } currentValueLabel: {
            Text(WidgetFormat.whole(n.eatenKcal))
                .font(.system(.body, design: .rounded).weight(.semibold).monospacedDigit())
                .minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
    }

    private func rectangular(_ n: NutritionWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Label("Calories", systemImage: "fork.knife").font(.headline).widgetAccentable()
                Spacer()
                Text("\(WidgetFormat.whole(n.eatenKcal)) / \(WidgetFormat.whole(n.targetKcal))")
                    .font(.caption.monospacedDigit())
            }
            bar(n.eatenKcal, n.targetKcal)
            HStack {
                Text("Protein").font(.caption2)
                Spacer()
                Text("\(WidgetFormat.whole(n.eatenProtein)) / \(WidgetFormat.whole(n.targetProtein)) g")
                    .font(.caption2.monospacedDigit())
            }
            bar(n.eatenProtein, n.targetProtein)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ n: NutritionWidgetSnapshot) -> some View {
        Label("\(WidgetFormat.whole(n.eatenKcal)) / \(WidgetFormat.whole(n.targetKcal)) kcal · \(WidgetFormat.whole(n.eatenProtein)) g protein",
              systemImage: "fork.knife")
    }

    private func bar(_ eaten: Double, _ target: Double) -> some View {
        ProgressView(value: min(eaten, target), total: max(target, 1))
            .tint(over(eaten, target) ? .orange : WidgetTheme.accent)
    }

    private func over(_ eaten: Double, _ target: Double) -> Bool { eaten > target * 1.05 }
}

#Preview("Small", as: .systemSmall) { CaloriesWidget() } timeline: { SnapshotEntry.sample }
#Preview("Circular", as: .accessoryCircular) { CaloriesWidget() } timeline: { SnapshotEntry.sample }
#Preview("Rectangular", as: .accessoryRectangular) { CaloriesWidget() } timeline: { SnapshotEntry.sample }
