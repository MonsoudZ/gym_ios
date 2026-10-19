import Foundation
import SwiftData

/// One applied weekly check (DESIGN.md §3.3): what the trend and goal were, what changed, and
/// where the running total landed. Kept so the trend of adjustments can be seen, not just summed.
@Model
final class AdjustmentEntry {
    var date: Date
    var kcal: Int
    var trendRatePercentPerWeek: Double
    var goalRatePercentPerWeek: Double
    /// Running total after this adjustment was applied.
    var cumulativeKcalAfter: Double
    var note: String?

    init(date: Date = .now, kcal: Int, trendRatePercentPerWeek: Double, goalRatePercentPerWeek: Double,
         cumulativeKcalAfter: Double, note: String? = nil) {
        self.date = date
        self.kcal = kcal
        self.trendRatePercentPerWeek = trendRatePercentPerWeek
        self.goalRatePercentPerWeek = goalRatePercentPerWeek
        self.cumulativeKcalAfter = cumulativeKcalAfter
        self.note = note
    }
}

extension UserSettings {
    /// Applies a weekly check: moves the running total, stamps the date, and records the entry.
    @discardableResult
    func applyAdjustment(_ adjustment: Adjustment, trendRatePercentPerWeek: Double, in context: ModelContext, on date: Date = .now) -> AdjustmentEntry {
        cumulativeAdjustmentKcal += Double(adjustment.kcal)
        lastAdjustmentDate = date
        let entry = AdjustmentEntry(date: date, kcal: adjustment.kcal,
                                    trendRatePercentPerWeek: trendRatePercentPerWeek,
                                    goalRatePercentPerWeek: goalRatePercentPerWeek,
                                    cumulativeKcalAfter: cumulativeAdjustmentKcal, note: adjustment.note)
        context.insert(entry)
        return entry
    }
}
