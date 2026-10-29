import Foundation

/// One bodyweight sample as Health reports it.
nonisolated struct HealthWeightSample: Hashable, Sendable {
    var date: Date
    var kg: Double
}

/// A stored bodyweight entry, as much of it as the import rule needs.
nonisolated struct ExistingWeight: Hashable, Sendable {
    var date: Date   // start of day
    var kg: Double
    var fromHealth: Bool
}

/// Decides which Health bodyweight samples become entries (DESIGN.md §3.2). Pure; the
/// samples and the store come from `HealthService`.
///
/// The expenditure estimate wants one morning weigh-in per day, so the earliest sample of
/// each day is used. A day the lifter typed a weight for is never touched. A day Health
/// filled earlier is updated when Health's number for it changes (a re-weigh, or a sample
/// synced late from the watch).
nonisolated enum BodyweightImport {
    nonisolated struct Change: Hashable, Sendable {
        enum Kind: Sendable { case insert, update }
        var date: Date   // start of day
        var kg: Double
        var kind: Kind
    }

    /// The first sample of each day, keyed by the start of that day.
    static func morningWeights(_ samples: [HealthWeightSample], calendar: Calendar = .current) -> [Date: Double] {
        var earliest: [Date: HealthWeightSample] = [:]
        for sample in samples where sample.kg > 0 {
            let day = calendar.startOfDay(for: sample.date)
            if let current = earliest[day], current.date <= sample.date { continue }
            earliest[day] = sample
        }
        return earliest.mapValues(\.kg)
    }

    /// `dismissed` are days whose Health-filled entry the lifter deleted; they are not filled
    /// again. A typed entry on such a day is still never touched.
    static func changes(morning: [Date: Double], existing: [ExistingWeight], dismissed: Set<Date> = []) -> [Change] {
        let byDay = Dictionary(existing.map { ($0.date, $0) }, uniquingKeysWith: { first, _ in first })
        return morning.compactMap { day, kg in
            guard let entry = byDay[day] else {
                return dismissed.contains(day) ? nil : Change(date: day, kg: kg, kind: .insert)
            }
            guard entry.fromHealth, abs(entry.kg - kg) > 0.001 else { return nil }
            return Change(date: day, kg: kg, kind: .update)
        }
        .sorted { $0.date < $1.date }
    }
}
