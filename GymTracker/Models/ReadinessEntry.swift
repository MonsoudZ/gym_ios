import Foundation
import SwiftData

/// What one refresh learned from Health about one feature.
nonisolated enum HealthRead<Value: Hashable & Sendable>: Hashable, Sendable {
    /// Health answered. Nil means it has nothing for today, or the feature is off; either way
    /// whatever Health filled in before is cleared.
    case value(Value?)
    /// Health could not be read: an error, or the app left the foreground mid-query. The
    /// stored reading is left alone, so a transient failure never erases this morning's numbers.
    case unavailable
}

/// One day's readiness check-in (DESIGN.md §2.4), kept so it survives leaving the Today tab
/// and is asked for only once. The session started that day copies it.
@Model
final class ReadinessEntry {
    @Attribute(.unique) var date: Date   // start of day
    var sleepHours: Double?
    /// `sleepHours` came from Health (SleepRule) rather than being typed. Typing over it clears
    /// this, and Health then leaves the day alone.
    var sleepFromHealth: Bool = false
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

    /// Something the lifter typed. Health readings (heart, and sleep when it was filled from
    /// Health) arrive on their own and are not a check-in, so an entry holding only those still
    /// reads as "not logged".
    var isLogged: Bool { (sleepHours != nil && !sleepFromHealth) || !sorenessByMuscle.isEmpty }

    /// Sets the sleep the lifter typed, taking over from a Health value if there was one.
    func setTypedSleep(_ hours: Double?) {
        sleepHours = hours
        sleepFromHealth = false
    }

    /// Fills sleep from Health unless the lifter has typed a value for the day. Returns whether
    /// anything changed.
    @discardableResult
    func applyHealthSleep(_ hours: Double?) -> Bool {
        guard sleepHours == nil || sleepFromHealth else { return false }
        let newValue = hours.map { ($0 * 10).rounded() / 10 }
        guard sleepHours != newValue || sleepFromHealth != (newValue != nil) else { return false }
        sleepHours = newValue
        sleepFromHealth = newValue != nil
        return true
    }

    /// Writes a refresh's Health readings onto the day. A reading that could not be fetched
    /// leaves what is stored. Returns whether anything changed.
    @discardableResult
    func applyHealth(heart heartRead: HealthRead<HeartReadiness>, sleep sleepRead: HealthRead<Double>) -> Bool {
        var changed = false
        if case .value(let hours) = sleepRead, applyHealthSleep(hours) { changed = true }
        if case .value(let reading) = heartRead, heart != reading {
            heart = reading
            changed = true
        }
        return changed
    }

    /// The entry for the day containing `date`, if any.
    static func entry(for date: Date, in entries: [ReadinessEntry]) -> ReadinessEntry? {
        let day = Calendar.current.startOfDay(for: date)
        return entries.first { $0.date == day }
    }
}
