import Foundation

/// One day's heart readings as Health reports them: the day's average HRV (SDNN, ms) and
/// resting heart rate (beats/min). Either can be missing.
nonisolated struct DailyHeartSample: Hashable, Sendable {
    var date: Date   // start of day
    var hrvMs: Double? = nil
    var restingHeartRate: Double? = nil
}

/// Mean and sample standard deviation of a metric over the baseline window.
nonisolated struct HeartBaseline: Hashable, Sendable {
    var mean: Double
    var standardDeviation: Double
    var days: Int
}

/// Today's heart readings against the lifter's recent baseline (DESIGN.md §2.4). Carried on the
/// readiness entry and the session so history keeps what the lifter saw that morning.
nonisolated struct HeartReadiness: Hashable, Sendable {
    var hrvMs: Double? = nil
    var restingHeartRate: Double? = nil
    var hrvBaseline: HeartBaseline? = nil
    var restingHeartRateBaseline: HeartBaseline? = nil

    var hasReading: Bool { hrvMs != nil || restingHeartRate != nil }

    /// HRV more than one SD below its baseline mean.
    var hrvIsLow: Bool {
        guard let hrvMs, let hrvBaseline else { return false }
        return HeartRateRule.isBelow(hrvMs, baseline: hrvBaseline)
    }

    /// Resting heart rate more than one SD above its baseline mean.
    var restingHeartRateIsHigh: Bool {
        guard let restingHeartRate, let restingHeartRateBaseline else { return false }
        return HeartRateRule.isAbove(restingHeartRate, baseline: restingHeartRateBaseline)
    }

    /// Either signal is clearly off its baseline. The readiness flag for the day.
    var isLow: Bool { hrvIsLow || restingHeartRateIsHigh }
}

/// Flags a morning whose HRV or resting heart rate is clearly off the lifter's own trailing
/// baseline. Pure; the Health reading comes from `HealthService`.
///
/// Rule (DESIGN.md §2.4): baseline is the mean and sample SD of each metric over the
/// `baselineDays` days before today, needing at least `minimumBaselineDays` of readings.
/// Low when today's HRV is more than one SD below its mean or resting HR more than one SD
/// above its mean. Days without a reading are skipped, not treated as zero.
nonisolated enum HeartRateRule {
    static let baselineDays = 7
    static let minimumBaselineDays = 4
    static let thresholdSDs = 1.0

    /// Mean and sample SD of `values`, or nil below the minimum baseline size.
    static func baseline(_ values: [Double]) -> HeartBaseline? {
        guard values.count >= minimumBaselineDays else { return nil }
        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        return HeartBaseline(mean: mean, standardDeviation: variance.squareRoot(), days: values.count)
    }

    static func isBelow(_ value: Double, baseline: HeartBaseline) -> Bool {
        value < baseline.mean - thresholdSDs * baseline.standardDeviation
    }

    static func isAbove(_ value: Double, baseline: HeartBaseline) -> Bool {
        value > baseline.mean + thresholdSDs * baseline.standardDeviation
    }

    /// Today's reading against the baseline built from the `baselineDays` days before it.
    /// Today's own reading is never part of its baseline. Returns nil when there is no
    /// reading for today at all.
    static func evaluate(samples: [DailyHeartSample], today: Date, calendar: Calendar = .current) -> HeartReadiness? {
        let day = calendar.startOfDay(for: today)
        guard let todays = samples.first(where: { calendar.startOfDay(for: $0.date) == day }),
              todays.hrvMs != nil || todays.restingHeartRate != nil else { return nil }
        guard let windowStart = calendar.date(byAdding: .day, value: -baselineDays, to: day) else { return nil }
        let window = samples.filter {
            let d = calendar.startOfDay(for: $0.date)
            return d >= windowStart && d < day
        }
        return HeartReadiness(hrvMs: todays.hrvMs,
                              restingHeartRate: todays.restingHeartRate,
                              hrvBaseline: baseline(window.compactMap(\.hrvMs)),
                              restingHeartRateBaseline: baseline(window.compactMap(\.restingHeartRate)))
    }
}
