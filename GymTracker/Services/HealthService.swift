import Foundation
import HealthKit
import SwiftData

/// Everything the app reads from or writes to Health (DESIGN.md §2.4, §3.2, §6):
///
/// - this morning's HRV (SDNN) and resting heart rate, judged against the trailing baseline
///   (`HeartRateRule`) and written onto today's readiness entry;
/// - last night's sleep (`SleepRule`), filled onto today's readiness entry unless typed over;
/// - morning bodyweights (`BodyweightImport`), filled onto days with no typed weigh-in;
/// - finished workouts, saved as strength training.
///
/// Nothing is read until the lifter turns a feature on in Settings, which is also what shows
/// the Health permission sheet. Health never says whether read access was granted: a refusal
/// simply leaves the reading empty, and the Today tab says so.
enum HealthService {
    /// Baseline window plus today.
    nonisolated static let lookbackDays = HeartRateRule.baselineDays + 1
    /// How far back bodyweights are pulled in, so a lifter who already weighs in with a smart
    /// scale starts with a trend instead of a single point.
    nonisolated static let bodyweightLookbackDays = 60

    private static let store = HKHealthStore()

    private static let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
    private static let restingHeartRateType = HKQuantityType(.restingHeartRate)
    private static let bodyMassType = HKQuantityType(.bodyMass)
    private static let sleepType = HKCategoryType(.sleepAnalysis)
    private static let hrvUnit = HKUnit.secondUnit(with: .milli)
    private static let beatsPerMinute = HKUnit.count().unitDivided(by: .minute())

    /// False on devices without Health (iPad, Mac), where the toggles cannot be turned on.
    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Permission

    /// Shows the Health sheet for every type the settings now ask for. Types already decided
    /// are not asked again. True when the request went through; whether the lifter allowed
    /// reading is not knowable, only visible as readings arriving or not.
    static func requestAuthorization(for settings: UserSettings) async -> Bool {
        guard isAvailable else { return false }
        var read: Set<HKObjectType> = []
        var share: Set<HKSampleType> = []
        if settings.heartReadinessEnabled { read.formUnion([hrvType, restingHeartRateType]) }
        if settings.sleepFromHealthEnabled { read.insert(sleepType) }
        if settings.bodyweightFromHealthEnabled { read.insert(bodyMassType) }
        if settings.saveWorkoutsToHealthEnabled { share.insert(HKWorkoutType.workoutType()) }
        guard !read.isEmpty || !share.isEmpty else { return true }
        do {
            try await store.requestAuthorization(toShare: share, read: read)
            return true
        } catch {
            return false
        }
    }

    /// Writing is the one direction Health does report on.
    static var canSaveWorkouts: Bool {
        isAvailable && store.authorizationStatus(for: HKWorkoutType.workoutType()) == .sharingAuthorized
    }

    // MARK: Reading

    /// Only samples before this hour count toward a day's reading, so "this morning's HRV" is the
    /// morning's and does not drift all day as the watch adds samples (notably after training).
    nonisolated static let morningEndHour = 12

    /// Morning averages of both heart metrics over the last `lookbackDays` days, today included.
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
        // The samples themselves, averaged per calendar morning by `HeartRateRule`. A statistics
        // collection with 12-hour buckets was used before; its buckets are fixed hours from the
        // anchor, so after a DST change every "midnight" bucket started at 01:00 or 23:00 and
        // the morning filter dropped a week of readings.
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [:] }
        let values = samples.map { DatedValue(date: $0.startDate, value: $0.quantity.doubleValue(for: unit)) }
        return HeartRateRule.morningAverages(values, endHour: morningEndHour, calendar: calendar)
    }

    /// Asleep stretches overlapping last night's window. In-bed and awake samples are dropped.
    static func sleepSamples(now: Date = .now, calendar: Calendar = .current) async -> [SleepInterval] {
        guard isAvailable else { return [] }
        let (start, end) = SleepRule.window(now: now, calendar: calendar)
        let predicate = HKSamplePredicate.categorySample(
            type: sleepType, predicate: HKQuery.predicateForSamples(withStart: start, end: end, options: []))
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues.map(\.rawValue)
        return samples
            .filter { asleep.contains($0.value) }
            .map { SleepInterval(start: $0.startDate, end: $0.endDate) }
    }

    /// Every bodyweight sample in the last `bodyweightLookbackDays` days, oldest first.
    static func weightSamples(now: Date = .now, calendar: Calendar = .current) async -> [HealthWeightSample] {
        guard isAvailable else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -bodyweightLookbackDays, to: today) else { return [] }
        let predicate = HKSamplePredicate.quantitySample(
            type: bodyMassType, predicate: HKQuery.predicateForSamples(withStart: start, end: nil, options: []))
        let descriptor = HKSampleQueryDescriptor(predicates: [predicate], sortDescriptors: [SortDescriptor(\.startDate)])
        guard let samples = try? await descriptor.result(for: store) else { return [] }
        return samples.map { HealthWeightSample(date: $0.startDate, kg: $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    // MARK: Applying to the store

    /// Brings the store up to date with Health for every feature that is on, and clears what
    /// Health had filled in for features that are now off. Called when the app becomes active
    /// and when a setting changes.
    static func refresh(context: ModelContext, now: Date = .now) async {
        let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first
        await refreshReadiness(context: context, settings: settings, now: now)
        await refreshBodyweight(context: context, settings: settings, now: now)
    }

    private static func refreshReadiness(context: ModelContext, settings: UserSettings?, now: Date) async {
        var heart: HeartReadiness?
        if settings?.heartReadinessEnabled == true {
            heart = HeartRateRule.evaluate(samples: await dailySamples(now: now), today: now)
        }
        var sleep: Double?
        if settings?.sleepFromHealthEnabled == true {
            sleep = SleepRule.hoursAsleep(await sleepSamples(now: now), now: now)
        }
        let entries = (try? context.fetch(FetchDescriptor<ReadinessEntry>())) ?? []
        if let entry = ReadinessEntry.entry(for: now, in: entries) {
            var changed = entry.applyHealthSleep(sleep)
            if entry.heart != heart {
                entry.heart = heart
                changed = true
            }
            guard changed else { return }
        } else if heart != nil || sleep != nil {
            let entry = ReadinessEntry(date: now)
            entry.heart = heart
            entry.applyHealthSleep(sleep)
            context.insert(entry)
        } else {
            return
        }
        context.saveOrLog()
    }

    private static func refreshBodyweight(context: ModelContext, settings: UserSettings?, now: Date) async {
        guard settings?.bodyweightFromHealthEnabled == true else { return }
        let morning = BodyweightImport.morningWeights(await weightSamples(now: now))
        guard !morning.isEmpty else { return }
        let entries = (try? context.fetch(FetchDescriptor<BodyweightEntry>())) ?? []
        let existing = entries.map { ExistingWeight(date: $0.date, kg: $0.kg, fromHealth: $0.fromHealth) }
        let changes = BodyweightImport.changes(morning: morning, existing: existing)
        guard !changes.isEmpty else { return }
        for change in changes {
            switch change.kind {
            case .insert:
                context.insert(BodyweightEntry(date: change.date, kg: change.kg, fromHealth: true))
            case .update:
                entries.first { $0.date == change.date }?.kg = change.kg
            }
        }
        context.saveOrLog()
        LogReminders.refresh(context: context, now: now)
    }

    // MARK: Writing workouts

    /// Saves a finished session to Health as strength training, from the session's start to its
    /// last logged set. Returns the saved workout's id, or nil when writing is off or refused.
    static func saveWorkout(_ session: WorkoutSession, now: Date = .now) async -> UUID? {
        guard canSaveWorkouts else { return nil }
        let start = session.date
        let lastSet = session.sets.compactMap(\.completedAt).max() ?? now
        let end = max(lastSet, start.addingTimeInterval(60))
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.endCollection(at: end)
            return try await builder.finishWorkout()?.uuid
        } catch {
            return nil
        }
    }

    /// Removes a workout this app saved, when its session is deleted.
    static func deleteWorkout(id: UUID) async {
        guard isAvailable else { return }
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(HKQuery.predicateForObject(with: id))], sortDescriptors: [])
        guard let workouts = try? await descriptor.result(for: store), !workouts.isEmpty else { return }
        try? await store.delete(workouts)
    }
}
