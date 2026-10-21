import Foundation

/// One stretch of sleep as Health records it. Only asleep stages are passed in; in-bed and
/// awake samples are filtered out by `HealthService`.
nonisolated struct SleepInterval: Hashable, Sendable {
    var start: Date
    var end: Date
}

/// Turns Health's sleep samples into "hours slept last night" for the readiness check-in
/// (DESIGN.md §2.4). Pure; the samples come from `HealthService`.
///
/// Last night is the window from `nightStartHour` yesterday to `nightEndHour` today, clipped to
/// now. Samples are clipped to the window and overlapping ones merged, because a watch and a
/// phone, or two apps, can both write the same night and would otherwise count it twice.
nonisolated enum SleepRule {
    /// 18:00 the evening before: early enough for any bedtime, late enough to miss an afternoon nap.
    static let nightStartHour = 18
    /// 14:00 today: a late lie-in still counts, an afternoon nap does not.
    static let nightEndHour = 14

    static func window(now: Date, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .hour, value: nightStartHour - 24, to: today) ?? today
        let end = calendar.date(byAdding: .hour, value: nightEndHour, to: today) ?? today
        return (start, min(end, now))
    }

    /// Hours asleep in last night's window, or nil when Health has nothing for it.
    static func hoursAsleep(_ samples: [SleepInterval], now: Date, calendar: Calendar = .current) -> Double? {
        let (start, end) = window(now: now, calendar: calendar)
        let clipped = samples
            .map { SleepInterval(start: max($0.start, start), end: min($0.end, end)) }
            .filter { $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !clipped.isEmpty else { return nil }
        var merged: [SleepInterval] = []
        for interval in clipped {
            if let last = merged.last, interval.start <= last.end {
                merged[merged.count - 1].end = max(last.end, interval.end)
            } else {
                merged.append(interval)
            }
        }
        let seconds = merged.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        return seconds / 3600
    }
}
