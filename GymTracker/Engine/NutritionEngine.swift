import Foundation

nonisolated struct DatedValue: Hashable, Sendable {
    var date: Date
    var value: Double
}

nonisolated enum Goal: String, Codable, CaseIterable, Sendable {
    case cut, maintain, leanGain

    var label: String {
        switch self {
        case .cut: "Cut"
        case .maintain: "Maintain"
        case .leanGain: "Lean gain"
        }
    }

    /// Percent of bodyweight per week. Negative is loss.
    var defaultRatePercentPerWeek: Double {
        switch self {
        case .cut: -0.5
        case .maintain: 0
        case .leanGain: 0.25
        }
    }

    var rateRange: ClosedRange<Double> {
        switch self {
        case .cut: -1.0 ... -0.25
        case .maintain: 0 ... 0
        case .leanGain: 0.1 ... 0.5
        }
    }

    /// Morton 2018 plateau for gain/maintain; Helms 2014 for a deficit.
    var proteinPerKg: Double {
        self == .cut ? 2.2 : 1.8
    }
}

nonisolated struct Macros: Hashable, Sendable {
    var kcal: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var fibre: Double

    static let zero = Macros(kcal: 0, protein: 0, fat: 0, carbs: 0, fibre: 0)
}

nonisolated enum Confidence: String, Sendable {
    case low, medium, high

    var label: String {
        switch self {
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }
}

nonisolated struct ExpenditureEstimate: Hashable, Sendable {
    var tdee: Double
    var loggedDays: Int
    var spanDays: Int
    var weightChangeKg: Double
    var confidence: Confidence
}

nonisolated struct Adjustment: Hashable, Sendable {
    var kcal: Int
    var note: String?
}

/// Adaptive expenditure and weekly adjustment. Rules in DESIGN.md §3.2–3.4.
nonisolated enum NutritionEngine {
    static let smoothing = 0.1
    static let kcalPerKg = 7700.0
    static let windowDays = 14
    static let minimumLoggedDays = 4
    static let mediumConfidenceDays = 10
    static let holdBandPercent = 0.15
    static let largeBandPercent = 0.5
    static let smallStepKcal = 100
    static let largeStepKcal = 150
    static let fibrePer1000Kcal = 14.0
    static let defaultFatFloorPerKg = 0.7
    static let defaultFatFraction = 0.25

    // MARK: Trend weight

    /// Exponential moving average over the series, oldest first. First value seeds the trend.
    /// The smoothing is per calendar day, not per entry: after a gap of `g` days the new
    /// weigh-in gets weight 1 − 0.9^g, what it would have had if it had been logged each of
    /// those days, so a twice-a-week weigher gets a trend that actually follows them.
    static func trend(_ weights: [DatedValue]) -> [DatedValue] {
        let sorted = weights.sorted { $0.date < $1.date }
        var result: [DatedValue] = []
        var current: Double?
        var previousDate: Date?
        for point in sorted {
            if let previous = current, let previousDate {
                let gap = max(1, daysBetween(previousDate, point.date))
                let weight = 1 - pow(1 - smoothing, Double(gap))
                current = previous + weight * (point.value - previous)
            } else {
                current = point.value
            }
            previousDate = point.date
            result.append(DatedValue(date: point.date, value: current!))
        }
        return result
    }

    /// Latest point at or before `date`. Order-independent.
    static func value(in series: [DatedValue], atOrBefore date: Date) -> DatedValue? {
        series.filter { $0.date <= date }.max { $0.date < $1.date }
    }

    /// Percent of bodyweight per week, from the trend over the most recent ≥7-day span.
    static func trendRatePercentPerWeek(trend: [DatedValue], asOf: Date) -> Double? {
        guard let end = value(in: trend, atOrBefore: asOf) else { return nil }
        let weekBefore = Calendar.current.date(byAdding: .day, value: -7, to: end.date)!
        guard let start = value(in: trend, atOrBefore: weekBefore), end.value > 0 else { return nil }
        let days = daysBetween(start.date, end.date)
        guard days >= 6 else { return nil }
        return (end.value - start.value) / end.value * 100 * (7 / Double(days))
    }

    // MARK: Expenditure

    /// TDEE ≈ mean intake − kcalPerKg × (Δtrend / days). Uses the last `windowDays` logged days.
    static func expenditure(intake: [DatedValue], trend: [DatedValue], asOf: Date) -> ExpenditureEstimate? {
        let logged = intake.filter { $0.date <= asOf }.sorted { $0.date < $1.date }.suffix(windowDays)
        guard logged.count >= minimumLoggedDays,
              let first = logged.first, let last = logged.last,
              let startTrend = value(in: trend, atOrBefore: first.date),
              let endTrend = value(in: trend, atOrBefore: last.date) else { return nil }
        let span = max(1, daysBetween(first.date, last.date))
        let meanIntake = logged.map(\.value).reduce(0, +) / Double(logged.count)
        let delta = endTrend.value - startTrend.value
        let tdee = meanIntake - kcalPerKg * delta / Double(span)
        let confidence: Confidence = logged.count >= windowDays ? .high
            : logged.count >= mediumConfidenceDays ? .medium : .low
        return ExpenditureEstimate(tdee: tdee, loggedDays: logged.count, spanDays: span,
                                   weightChangeKg: delta, confidence: confidence)
    }

    /// Provisional estimate used during the calibration period.
    static func mifflinStJeor(weightKg: Double, heightCm: Double, ageYears: Int, isMale: Bool, activityFactor: Double) -> Double {
        let bmr = 10 * weightKg + 6.25 * heightCm - 5 * Double(ageYears) + (isMale ? 5 : -161)
        return bmr * activityFactor
    }

    /// Daily calorie offset that produces the goal rate.
    static func dailyGoalOffsetKcal(ratePercentPerWeek: Double, bodyweightKg: Double) -> Double {
        ratePercentPerWeek / 100 * bodyweightKg * kcalPerKg / 7
    }

    // MARK: Weekly adjustment

    static func weeklyAdjustment(trendRatePercentPerWeek trendRate: Double, goalRatePercentPerWeek goalRate: Double) -> Adjustment {
        let diff = trendRate - goalRate   // positive: heavier than goal path
        let magnitude = abs(diff)
        if magnitude <= holdBandPercent { return Adjustment(kcal: 0, note: nil) }
        let step = magnitude > largeBandPercent ? largeStepKcal : smallStepKcal
        let note = magnitude > largeBandPercent ? "Trend is well off the goal. Check logging accuracy before trusting this." : nil
        return Adjustment(kcal: diff > 0 ? -step : step, note: note)
    }

    // MARK: Macros

    static func macros(kcal: Double, bodyweightKg: Double, proteinPerKg: Double, fatFloorPerKg: Double = defaultFatFloorPerKg) -> Macros {
        let protein = proteinPerKg * bodyweightKg
        let fat = max(fatFloorPerKg * bodyweightKg, defaultFatFraction * kcal / 9)
        let carbs = max(0, (kcal - 4 * protein - 9 * fat) / 4)
        let fibre = fibrePer1000Kcal * kcal / 1000
        return Macros(kcal: kcal, protein: protein, fat: fat, carbs: carbs, fibre: fibre)
    }

    // MARK: Helpers

    static func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: a), to: cal.startOfDay(for: b)).day ?? 0
    }
}
