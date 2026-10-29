import XCTest
@testable import GymTracker

final class HeartRateRuleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    private var today: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8))! }

    private func day(_ daysAgo: Int) -> Date { calendar.date(byAdding: .day, value: -daysAgo, to: today)! }

    /// Baseline of `hrv` / `rhr` on the given past days, plus today's reading.
    private func samples(baselineDays: [Int], hrv: [Double], rhr: [Double],
                         todayHRV: Double?, todayRHR: Double?) -> [DailyHeartSample] {
        var result = zip(baselineDays, zip(hrv, rhr)).map { daysAgo, pair in
            DailyHeartSample(date: day(daysAgo), hrvMs: pair.0, restingHeartRate: pair.1)
        }
        result.append(DailyHeartSample(date: today, hrvMs: todayHRV, restingHeartRate: todayRHR))
        return result
    }

    private let steadyHRV: [Double] = [50, 52, 48, 51, 49, 53, 47]   // mean 50, SD ≈ 2.16
    private let steadyRHR: [Double] = [58, 60, 57, 59, 61, 58, 60]   // mean ≈ 59, SD ≈ 1.41

    // MARK: Morning averages

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ value: Double) -> DatedValue {
        DatedValue(date: calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!, value: value)
    }

    func testMorningAverageTakesSamplesBeforeNoonOnly() {
        let samples = [at(2026, 10, 18, 6, 50), at(2026, 10, 18, 9, 54), at(2026, 10, 18, 15, 30), at(2026, 10, 17, 14, 40)]
        let result = HeartRateRule.morningAverages(samples, endHour: 12, calendar: calendar)
        XCTAssertEqual(result.count, 1, "a day with only afternoon samples has no reading")
        XCTAssertEqual(result[calendar.startOfDay(for: at(2026, 10, 18, 0, 0).date)], 52)
    }

    func testMorningAveragesSurviveADSTChange() {
        // Denver springs forward on 8 Mar 2026 and falls back on 1 Nov 2026. Readings on the
        // transition day and the days after must key to their own calendar day.
        let spring = [at(2026, 3, 7, 7, 48), at(2026, 3, 8, 7, 50), at(2026, 3, 9, 7, 52), at(2026, 3, 9, 13, 99)]
        let springResult = HeartRateRule.morningAverages(spring, endHour: 12, calendar: calendar)
        XCTAssertEqual(springResult.count, 3)
        XCTAssertEqual(springResult[calendar.startOfDay(for: at(2026, 3, 9, 0, 0).date)], 52)
        let fall = [at(2026, 10, 31, 7, 48), at(2026, 11, 1, 7, 50), at(2026, 11, 2, 7, 52)]
        let fallResult = HeartRateRule.morningAverages(fall, endHour: 12, calendar: calendar)
        XCTAssertEqual(fallResult.count, 3)
        XCTAssertEqual(fallResult[calendar.startOfDay(for: at(2026, 11, 2, 0, 0).date)], 52)
    }

    // MARK: Baseline

    func testBaselineIsMeanAndSampleSD() {
        let b = HeartRateRule.baseline([50, 52, 48, 51, 49, 53, 47])!
        XCTAssertEqual(b.mean, 50, accuracy: 0.001)
        XCTAssertEqual(b.standardDeviation, 2.160, accuracy: 0.001)
        XCTAssertEqual(b.days, 7)
    }

    func testBaselineNeedsAtLeastFourDays() {
        XCTAssertNil(HeartRateRule.baseline([50, 52, 48]))
        XCTAssertNotNil(HeartRateRule.baseline([50, 52, 48, 51]))
    }

    // MARK: Flag

    func testNormalMorningIsNotLow() {
        let s = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 49, todayRHR: 60)
        let h = HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!
        XCTAssertFalse(h.isLow)
        XCTAssertEqual(h.hrvBaseline?.days, 7)
        XCTAssertEqual(h.restingHeartRateBaseline?.days, 7)
    }

    func testHRVMoreThanOneSDBelowMeanIsLow() {
        // Threshold ≈ 50 − 2.16 = 47.84: 47.5 is low, 48 is not.
        let low = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 47.5, todayRHR: 59)
        XCTAssertTrue(HeartRateRule.evaluate(samples: low, today: today, calendar: calendar)!.hrvIsLow)
        XCTAssertTrue(HeartRateRule.evaluate(samples: low, today: today, calendar: calendar)!.isLow)
        let fine = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 48, todayRHR: 59)
        XCTAssertFalse(HeartRateRule.evaluate(samples: fine, today: today, calendar: calendar)!.isLow)
    }

    func testRestingHRMoreThanOneSDAboveMeanIsLow() {
        // Threshold ≈ 59 + 1.41 = 60.41: 61 is high, 60 is not.
        let high = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 50, todayRHR: 61)
        let h = HeartRateRule.evaluate(samples: high, today: today, calendar: calendar)!
        XCTAssertTrue(h.restingHeartRateIsHigh)
        XCTAssertFalse(h.hrvIsLow)
        XCTAssertTrue(h.isLow)
    }

    func testHighHRVOrLowRestingHRNeverFlags() {
        let s = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 80, todayRHR: 45)
        XCTAssertFalse(HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!.isLow)
    }

    // MARK: Window and missing data

    func testFewerThanFourBaselineDaysGivesAReadingButNoFlag() {
        let s = samples(baselineDays: [1, 2, 3], hrv: [50, 52, 48], rhr: [58, 60, 57], todayHRV: 30, todayRHR: 80)
        let h = HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!
        XCTAssertEqual(h.hrvMs, 30)
        XCTAssertNil(h.hrvBaseline)
        XCTAssertNil(h.restingHeartRateBaseline)
        XCTAssertFalse(h.isLow)
    }

    func testBaselineIgnoresTodayAndDaysOlderThanSeven() {
        // Days 8 and 9 carry extreme values that would drag the baseline if counted.
        var s = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: 30, todayRHR: 59)
        s.append(DailyHeartSample(date: day(8), hrvMs: 10, restingHeartRate: 59))
        s.append(DailyHeartSample(date: day(9), hrvMs: 10, restingHeartRate: 59))
        let h = HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!
        XCTAssertEqual(h.hrvBaseline?.days, 7)
        XCTAssertEqual(h.hrvBaseline?.mean ?? 0, 50, accuracy: 0.001)
        XCTAssertTrue(h.hrvIsLow)
    }

    func testDaysWithoutAReadingAreSkippedNotZero() {
        // Only four of the seven days have HRV; resting HR is present on all seven.
        let hrv: [Double?] = [50, nil, 52, nil, 48, nil, 50]
        var s = zip(Array(1...7), zip(hrv, steadyRHR)).map { daysAgo, pair in
            DailyHeartSample(date: day(daysAgo), hrvMs: pair.0, restingHeartRate: pair.1)
        }
        s.append(DailyHeartSample(date: today, hrvMs: 49, restingHeartRate: 59))
        let h = HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!
        XCTAssertEqual(h.hrvBaseline?.days, 4)
        XCTAssertEqual(h.hrvBaseline?.mean ?? 0, 50, accuracy: 0.001)
        XCTAssertEqual(h.restingHeartRateBaseline?.days, 7)
        XCTAssertFalse(h.isLow)
    }

    func testNoReadingTodayGivesNothing() {
        let s = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: nil, todayRHR: nil)
        XCTAssertNil(HeartRateRule.evaluate(samples: s, today: today, calendar: calendar))
        XCTAssertNil(HeartRateRule.evaluate(samples: [], today: today, calendar: calendar))
    }

    func testOnlyOneMetricTodayStillEvaluates() {
        let s = samples(baselineDays: Array(1...7), hrv: steadyHRV, rhr: steadyRHR, todayHRV: nil, todayRHR: 70)
        let h = HeartRateRule.evaluate(samples: s, today: today, calendar: calendar)!
        XCTAssertNil(h.hrvMs)
        XCTAssertFalse(h.hrvIsLow)
        XCTAssertTrue(h.restingHeartRateIsHigh)
    }

    // MARK: Readiness integration

    private let chest = [MuscleWeight(muscle: .chest, weight: 1)]

    func testLowHeartReadingMakesReadinessLow() {
        let heart = HeartReadiness(hrvMs: 40, restingHeartRate: 59,
                                   hrvBaseline: HeartBaseline(mean: 50, standardDeviation: 2, days: 7),
                                   restingHeartRateBaseline: HeartBaseline(mean: 59, standardDeviation: 1.4, days: 7))
        let readiness = Readiness(sleepHours: 8, soreness: [:], heart: heart)
        XCTAssertTrue(readiness.hasAnyInput)
        XCTAssertTrue(readiness.isLow(for: chest))
    }

    func testGoodHeartReadingNeverRaisesLoads() {
        let heart = HeartReadiness(hrvMs: 70, restingHeartRate: 50,
                                   hrvBaseline: HeartBaseline(mean: 50, standardDeviation: 2, days: 7),
                                   restingHeartRateBaseline: HeartBaseline(mean: 59, standardDeviation: 1.4, days: 7))
        let config = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: 2.5, setCount: 3)
        let history = [SessionResult(date: .now, sets: [LoggedSet(weight: 80, reps: 8, rpe: 8)])]
        let plain = ProgressionEngine.prescription(history: history, config: config, muscles: chest, readiness: nil)
        let withHeart = ProgressionEngine.prescription(history: history, config: config, muscles: chest,
                                                       readiness: Readiness(sleepHours: 8, heart: heart))
        XCTAssertEqual(withHeart.weight, plain.weight)
        XCTAssertFalse(withHeart.readinessAdjusted)
    }

    func testLowHeartAndLowSleepStillOnlyFivePercent() {
        let heart = HeartReadiness(hrvMs: 40, restingHeartRate: 70,
                                   hrvBaseline: HeartBaseline(mean: 50, standardDeviation: 2, days: 7),
                                   restingHeartRateBaseline: HeartBaseline(mean: 59, standardDeviation: 1.4, days: 7))
        let config = ExerciseConfig(repRangeLow: 6, repRangeHigh: 8, increment: 2.5, setCount: 3)
        let history = [SessionResult(date: .now, sets: [LoggedSet(weight: 80, reps: 8, rpe: 8)])]
        let sleepOnly = ProgressionEngine.prescription(history: history, config: config, muscles: chest,
                                                       readiness: Readiness(sleepHours: 5))
        let both = ProgressionEngine.prescription(history: history, config: config, muscles: chest,
                                                  readiness: Readiness(sleepHours: 5, soreness: [.chest: 5], heart: heart))
        XCTAssertTrue(both.readinessAdjusted)
        XCTAssertEqual(both.weight, sleepOnly.weight)
        XCTAssertEqual(both.weight, 77.5)   // 82.5 × 0.95 = 78.4 → 77.5, same as the sleep-only case
    }
}
