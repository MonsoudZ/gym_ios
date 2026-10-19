import Foundation
import HealthKit
import SwiftData

/// Reads this morning's HRV (SDNN) and resting heart rate from Health and writes the reading,
/// judged against the trailing baseline (`HeartRateRule`), onto today's readiness entry
/// (DESIGN.md §2.4).
///
/// Nothing is read until the lifter turns the feature on in Settings, which is also what shows
/// the Health permission sheet. Health never says whether read access was granted: a refusal
/// simply leaves the reading empty, and the Today tab says so.
enum HealthService {
    /// Baseline window plus today.
    nonisolated static let lookbackDays = HeartRateRule.baselineDays + 1

    private static let store = HKHealthStore()

    private static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private static let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private static let hrvUnit = HKUnit.secondUnit(with: .milli)
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// False on devices without Health (iPad, Mac), where the toggle cannot be turned on.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Permission

    /// Shows the Health sheet the first time. True when the request went through; whether the
    /// lifter allowed reading is not knowable, only visible as readings arriving or not.
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [], read: [hrvType, restingHeartRateType])
            return true
        } catch {
            return false
        }
    }

    // MARK: Reading

    /// Daily averages of both metrics over the last `lookbackDays` days, today included.
    /// Days with neither reading are left out.
    static func dailySamples(now: Date = .now, calendar: Calendar = .current) async -> [DailyHeartSample] {
        guard isAvailable else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -(lookbackDays - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 1, to: today) else { return [] }
        let hrv = await dailyAverages(of: hrvType, unit: hrvUnit, from: start, to: end, calendar: calendar)
        let resting = await dailyAverages(of: restingHeartRateType, unit: beatsPerMinute, from: start, to: end, calendar: calendar)
        return Set(hrv.keys).union(resting.keys).sorted().map {
            DailyHeartSample(date: $0, hrvMs: hrv[$0], restingHeartRate: resting[$0])
        }
    }

    private static func dailyAverages(of type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date,
                                      calendar: Calendar) async -> [Date: Double] {
        let predicate = HKSamplePredicate.quantitySample(
            type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate))
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate, options: .discreteAverage, anchorDate: start, intervalComponents: DateComponents(day: 1))
        guard let collection = try? await descriptor.result(for: store) else { return [:] }
        var result: [Date: Double] = [:]
        collection.enumerateStatistics(from: start, to: end) { stats, _ in
            if let value = stats.averageQuantity()?.doubleValue(for: unit) {
                result[calendar.startOfDay(for: stats.startDate)] = value
            }
        }
        return result
    }

    // MARK: Applying to today's check-in

    /// Writes today's reading onto the day's readiness entry, or clears it when the feature is
    /// off. Called when the app becomes active and when the setting changes.
    static func refresh(context: ModelContext, now: Date = .now) async {
        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        var heart: HeartReadiness?
        if settings?.heartReadinessEnabled == true {
            heart = HeartRateRule.evaluate(samples: await dailySamples(now: now), today: now)
        }
        let entries = (try? context.fetch(FetchDescriptor<ReadinessEntry>())) ?? []
        if let entry = ReadinessEntry.entry(for: now, in: entries) {
            guard entry.heart != heart else { return }
            entry.heart = heart
        } else if let heart {
            let entry = ReadinessEntry(date: now)
            entry.heart = heart
            context.insert(entry)
        } else {
            return
        }
        context.saveOrLog()
    }
}
