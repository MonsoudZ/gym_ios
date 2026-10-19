import Foundation

/// Strength relative to bodyweight: e1RM ÷ trend bodyweight, both in kg, so the result is a
/// unitless multiple of bodyweight ("1.5× bodyweight") and reads the same in metric and lb.
///
/// Ratio scaling is biased against heavier lifters when comparing people (Jaric 2002), so this is
/// only ever used to follow one lifter over time, e.g. to see whether strength is kept while cutting.
nonisolated enum RelativeStrength {
    /// e1RM as a multiple of bodyweight, or nil when bodyweight is not a positive number.
    static func ratio(e1RMKg: Double, bodyweightKg: Double) -> Double? {
        guard e1RMKg > 0, bodyweightKg > 0 else { return nil }
        return e1RMKg / bodyweightKg
    }

    /// One ratio per e1RM point, in the same order, using the trend bodyweight on or before that
    /// point's date. nil where no weigh-in exists yet on or before the date.
    static func ratios(e1RM: [DatedValue], trend: [DatedValue]) -> [Double?] {
        e1RM.map { point in
            NutritionEngine.value(in: trend, atOrBefore: point.date)
                .flatMap { ratio(e1RMKg: point.value, bodyweightKg: $0.value) }
        }
    }

    /// The plottable series: only the sessions that have a bodyweight, oldest first as given.
    static func series(e1RM: [DatedValue], trend: [DatedValue]) -> [DatedValue] {
        zip(e1RM, ratios(e1RM: e1RM, trend: trend)).compactMap { point, ratio in
            ratio.map { DatedValue(date: point.date, value: $0) }
        }
    }

    /// "1.52× bodyweight" style label.
    static func label(_ ratio: Double) -> String {
        "\(Units.number(ratio, maxFraction: 2))× bodyweight"
    }
}
