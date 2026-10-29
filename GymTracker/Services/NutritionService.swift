import Foundation

struct NutritionSnapshot {
    var raw: [DatedValue]
    var trend: [DatedValue]
    var latestWeightKg: Double
    var estimate: ExpenditureEstimate?
    var baseKcal: Double
    var isProvisional: Bool
    var targetKcal: Double
    var macros: Macros
    var trendRatePercentPerWeek: Double?
    var suggestedAdjustment: Adjustment?
    var eatenToday: Macros

    /// The one sentence shown wherever a provisional target appears, so Today and Nutrition agree.
    static let provisionalNote = "Provisional target from the Mifflin–St Jeor formula. It becomes adaptive after about two weeks of logged weight and intake."
}

enum NutritionService {
    /// How far back intake is fetched for the snapshot: the 14-day window plus room for gaps.
    nonisolated static let intakeLookbackDays = 60

    static func snapshot(settings: UserSettings, weights: [BodyweightEntry], intake: [IntakeEntry], asOf: Date = .now) -> NutritionSnapshot {
        let cal = Calendar.current
        let raw = weights.map { DatedValue(date: $0.date, value: $0.kg) }.sorted { $0.date < $1.date }
        let trend = NutritionEngine.trend(raw)
        let latestWeight = trend.last?.value ?? settings.assumedWeightKg

        var byDay: [Date: Double] = [:]
        for entry in intake { byDay[cal.startOfDay(for: entry.date), default: 0] += entry.kcal }
        // Exclude today: it is still being logged.
        let today = cal.startOfDay(for: asOf)
        let intakeSeries = byDay.filter { $0.key < today }.map { DatedValue(date: $0.key, value: $0.value) }

        let estimate = NutritionEngine.expenditure(intake: intakeSeries, trend: trend, asOf: asOf)
        let base: Double
        let provisional: Bool
        // Provisional until the window is full (DESIGN.md §3.2: 14 logged days), not merely past
        // the low-confidence line. The confidence label is still shown for the estimate itself.
        if let estimate, estimate.loggedDays >= NutritionEngine.windowDays {
            base = estimate.tdee
            provisional = false
        } else {
            base = NutritionEngine.mifflinStJeor(weightKg: latestWeight, heightCm: settings.heightCm, ageYears: settings.ageYears,
                                                 isMale: settings.isMale, activityFactor: settings.activityFactor)
            provisional = true
        }
        let offset = NutritionEngine.dailyGoalOffsetKcal(ratePercentPerWeek: settings.goalRatePercentPerWeek, bodyweightKg: latestWeight)
        let target = (base + offset + settings.cumulativeAdjustmentKcal).rounded(.toNearestOrEven)
        let macros = NutritionEngine.macros(kcal: target, bodyweightKg: latestWeight, proteinPerKg: settings.proteinPerKg, fatFloorPerKg: settings.fatFloorPerKg)

        let rate = NutritionEngine.trendRatePercentPerWeek(trend: trend, asOf: asOf)
        var suggestion: Adjustment?
        // A week since the last check, or since the goal was set, so the first check is not
        // offered the moment the target becomes adaptive, against a week on another target.
        // And only on a weigh-in logged since then: without one the rate is last week's, already
        // acted on, and would be applied again every week the lifter kept logging food.
        let anchor = settings.lastAdjustmentDate ?? settings.createdAt
        let dueForAdjustment = NutritionEngine.daysBetween(anchor, asOf) >= 7
        let weighedSince = raw.contains { $0.date > anchor }
        if let rate, !provisional, dueForAdjustment, weighedSince {
            suggestion = NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: rate, goalRatePercentPerWeek: settings.goalRatePercentPerWeek)
        }

        var eaten = Macros.zero
        for entry in intake where cal.isDate(entry.date, inSameDayAs: asOf) {
            eaten.kcal += entry.kcal; eaten.protein += entry.protein; eaten.carbs += entry.carbs
            eaten.fat += entry.fat; eaten.fibre += entry.fibre
        }

        return NutritionSnapshot(raw: raw, trend: trend, latestWeightKg: latestWeight, estimate: estimate,
                                 baseKcal: base, isProvisional: provisional, targetKcal: target, macros: macros,
                                 trendRatePercentPerWeek: rate, suggestedAdjustment: suggestion, eatenToday: eaten)
    }
}
