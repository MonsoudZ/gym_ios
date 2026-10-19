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
}

enum NutritionService {
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
        if let estimate, estimate.confidence != .low {
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
        let dueForAdjustment = settings.lastAdjustmentDate.map { NutritionEngine.daysBetween($0, asOf) >= 7 } ?? true
        if let rate, !provisional, dueForAdjustment {
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
