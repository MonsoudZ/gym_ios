import Foundation
import SwiftUI
import WidgetKit

nonisolated struct SnapshotEntry: TimelineEntry {
    var date: Date
    var snapshot: WidgetSnapshot

    /// Sample data for the widget gallery and placeholders.
    static let sample = SnapshotEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            lift: LiftSnapshot(
                dayName: "Push",
                lines: [
                    .init(name: "Bench Press", detail: "185 lb · 3 × 5–8", badge: "Progressed"),
                    .init(name: "Overhead Press", detail: "95 lb · 3 × 6–10", badge: nil),
                    .init(name: "Incline Dumbbell Press", detail: "60 lb · 3 × 8–12", badge: nil),
                    .init(name: "Lateral Raise", detail: "20 lb · 3 × 12–15", badge: nil),
                ],
                headline: .init(name: "Bench Press", detail: "185 lb · 3 × 5–8", badge: "Progressed"),
                headlineReason: "Hit the top of the range last time, so the load goes up.",
                inProgress: false),
            nutrition: NutritionWidgetSnapshot(dayStart: Calendar.current.startOfDay(for: .now),
                                               eatenKcal: 1_420, targetKcal: 2_450,
                                               eatenProtein: 96, targetProtein: 170, isProvisional: false),
            updatedAt: .now))
}

/// Serves whatever the app last wrote. The app reloads the timelines after every save, so the
/// only scheduled entry is the one at midnight that zeroes today's intake.
nonisolated struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry { .sample }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        if context.isPreview { completion(.sample); return }
        completion(SnapshotEntry(date: .now, snapshot: WidgetStore.load() ?? .empty))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.load() ?? .empty
        var entries = [SnapshotEntry(date: now, snapshot: current(snapshot, at: now))]
        let calendar = Calendar.current
        if let midnight = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) {
            entries.append(SnapshotEntry(date: midnight, snapshot: current(snapshot, at: midnight)))
            completion(Timeline(entries: entries, policy: .after(midnight)))
        } else {
            completion(Timeline(entries: entries, policy: .never))
        }
    }

    /// The snapshot as it should read at `date`: intake written for an earlier day shows as zero.
    private func current(_ snapshot: WidgetSnapshot, at date: Date) -> WidgetSnapshot {
        var copy = snapshot
        if let nutrition = snapshot.nutrition {
            let day = Calendar.current.startOfDay(for: date)
            if nutrition.dayStart < day { copy.nutrition = nutrition.zeroed(for: day) }
        }
        return copy
    }
}

nonisolated enum WidgetFormat {
    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }
}

/// The app's accent, spelled out because `Color.accentColor` resolves to the system blue
/// inside a Live Activity.
nonisolated enum WidgetTheme {
    static let accent = Color(red: 0.1, green: 0.6, blue: 0.4)
}
