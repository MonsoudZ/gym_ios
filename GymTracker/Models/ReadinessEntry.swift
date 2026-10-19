import Foundation
import SwiftData

/// One day's readiness check-in (DESIGN.md §2.4), kept so it survives leaving the Today tab
/// and is asked for only once. The session started that day copies it.
@Model
final class ReadinessEntry {
    @Attribute(.unique) var date: Date   // start of day
    var sleepHours: Double?
    var sorenessByMuscle: [String: Int]

    // This morning's Health reading and the baseline it was judged against, written by
    // `HealthService` when the feature is on. Kept so the day's flag can be explained later
    // even after Health's own numbers move.
    var hrvMs: Double?
    var restingHeartRate: Double?
    var hrvBaselineMean: Double?
    var hrvBaselineSD: Double?
    var hrvBaselineDays: Int?
    var restingHeartRateBaselineMean: Double?
    var restingHeartRateBaselineSD: Double?
    var restingHeartRateBaselineDays: Int?

    init(date: Date, sleepHours: Double? = nil, soreness: [Muscle: Int] = [:]) {
        self.date = Calendar.current.startOfDay(for: date)
        self.sleepHours = sleepHours
        sorenessByMuscle = Dictionary(uniqueKeysWithValues: soreness.map { ($0.key.rawValue, $0.value) })
    }

    var soreMuscles: Set<Muscle> {
        get { Set(sorenessByMuscle.compactMap { Muscle(rawValue: $0.key) }) }
        set { sorenessByMuscle = Dictionary(uniqueKeysWithValues: newValue.map { ($0.rawValue, Readiness.sorenessThreshold) }) }
    }

    var heart: HeartReadiness? {
        get {
            guard hrvMs != nil || restingHeartRate != nil else { return nil }
            return HeartReadiness(hrvMs: hrvMs, restingHeartRate: restingHeartRate,
                                  hrvBaseline: Self.baseline(mean: hrvBaselineMean, sd: hrvBaselineSD, days: hrvBaselineDays),
                                  restingHeartRateBaseline: Self.baseline(mean: restingHeartRateBaselineMean,
                                                                          sd: restingHeartRateBaselineSD,
                                                                          days: restingHeartRateBaselineDays))
        }
        set {
            hrvMs = newValue?.hrvMs
            restingHeartRate = newValue?.restingHeartRate
            hrvBaselineMean = newValue?.hrvBaseline?.mean
            hrvBaselineSD = newValue?.hrvBaseline?.standardDeviation
            hrvBaselineDays = newValue?.hrvBaseline?.days
            restingHeartRateBaselineMean = newValue?.restingHeartRateBaseline?.mean
            restingHeartRateBaselineSD = newValue?.restingHeartRateBaseline?.standardDeviation
            restingHeartRateBaselineDays = newValue?.restingHeartRateBaseline?.days
        }
    }

    private static func baseline(mean: Double?, sd: Double?, days: Int?) -> HeartBaseline? {
        guard let mean, let sd, let days else { return nil }
        return HeartBaseline(mean: mean, standardDeviation: sd, days: days)
    }

    var readiness: Readiness {
        var soreness: [Muscle: Int] = [:]
        for (key, value) in sorenessByMuscle {
            if let muscle = Muscle(rawValue: key) { soreness[muscle] = value }
        }
        return Readiness(sleepHours: sleepHours, soreness: soreness, heart: heart)
    }

    /// Something the lifter typed. The Health reading arrives on its own and is not a check-in,
    /// so an entry holding only that still reads as "not logged".
    var isLogged: Bool { sleepHours != nil || !sorenessByMuscle.isEmpty }

    /// The entry for the day containing `date`, if any.
    static func entry(for date: Date, in entries: [ReadinessEntry]) -> ReadinessEntry? {
        let day = Calendar.current.startOfDay(for: date)
        return entries.first { $0.date == day }
    }
}
