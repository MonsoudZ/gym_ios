import XCTest
@testable import GymTracker

final class NutritionEngineTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: .now) }
    private func day(_ offset: Int) -> Date { cal.date(byAdding: .day, value: offset, to: today)! }

    func testTrendSeedsWithFirstValueThenSmooths() {
        let trend = NutritionEngine.trend([DatedValue(date: day(-2), value: 80), DatedValue(date: day(-1), value: 82)])
        XCTAssertEqual(trend[0].value, 80)
        XCTAssertEqual(trend[1].value, 80.2, accuracy: 0.0001)
    }

    func testTrendSmoothsPerCalendarDayAcrossGaps() {
        // Two weigh-ins seven days apart: the second carries the weight of seven daily steps.
        let trend = NutritionEngine.trend([DatedValue(date: day(-7), value: 80), DatedValue(date: day(0), value: 78)])
        let expected = 80 + (1 - pow(0.9, 7)) * (78 - 80)
        XCTAssertEqual(trend[1].value, expected, accuracy: 0.0001)
        XCTAssertLessThan(trend[1].value, 79.0, "more than the single 0.1 step of the per-entry rule")
    }

    func testConstantWeightGivesTdeeEqualToMeanIntake() {
        let intake = (1...14).map { DatedValue(date: day(-$0), value: 2000) }
        let trend = (0...15).map { DatedValue(date: day(-$0), value: 80) }
        let est = NutritionEngine.expenditure(intake: intake, trend: trend, asOf: .now)!
        XCTAssertEqual(est.tdee, 2000, accuracy: 0.001)
        XCTAssertEqual(est.confidence, .high)
        XCTAssertEqual(est.loggedDays, 14)
    }

    func testWeightLossRaisesTdeeAboveIntake() {
        // 0.5 kg lost across the 13-day span between the first and last logged day.
        let intake = (1...14).map { DatedValue(date: day(-$0), value: 2000) }
        let trend = (0...15).map { DatedValue(date: day(-$0), value: 80 + 0.5 * Double($0) / 13) }
        let est = NutritionEngine.expenditure(intake: intake, trend: trend, asOf: .now)!
        XCTAssertEqual(est.weightChangeKg, -0.5, accuracy: 0.001)
        XCTAssertEqual(est.tdee, 2000 + 7700 * 0.5 / 13, accuracy: 0.01)
    }

    func testConfidenceBands() {
        let trend = (0...15).map { DatedValue(date: day(-$0), value: 80) }
        let few = (1...6).map { DatedValue(date: day(-$0), value: 2000) }
        XCTAssertEqual(NutritionEngine.expenditure(intake: few, trend: trend, asOf: .now)?.confidence, .low)
        let some = (1...11).map { DatedValue(date: day(-$0), value: 2000) }
        XCTAssertEqual(NutritionEngine.expenditure(intake: some, trend: trend, asOf: .now)?.confidence, .medium)
        let tooFew = (1...3).map { DatedValue(date: day(-$0), value: 2000) }
        XCTAssertNil(NutritionEngine.expenditure(intake: tooFew, trend: trend, asOf: .now))
    }

    func testMifflinStJeorKnownValue() {
        // Male, 80 kg, 180 cm, 30 y: 800 + 1125 − 150 + 5 = 1780 × 1.5
        let value = NutritionEngine.mifflinStJeor(weightKg: 80, heightCm: 180, ageYears: 30, isMale: true, activityFactor: 1.5)
        XCTAssertEqual(value, 1780 * 1.5, accuracy: 0.001)
    }

    func testWeeklyAdjustmentTable() {
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.4, goalRatePercentPerWeek: -0.5).kcal, 0)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.2, goalRatePercentPerWeek: -0.5).kcal, -100)  // losing too slowly
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.8, goalRatePercentPerWeek: -0.5).kcal, 100)   // losing too fast
        let large = NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: 0.3, goalRatePercentPerWeek: -0.5)
        XCTAssertEqual(large.kcal, -150)
        XCTAssertNotNil(large.note)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: 0.6, goalRatePercentPerWeek: 0.25).kcal, -100)   // gaining too fast
    }

    func testMacrosForACut() {
        let m = NutritionEngine.macros(kcal: 2200, bodyweightKg: 80, proteinPerKg: 2.2)
        XCTAssertEqual(m.protein, 176)
        XCTAssertEqual(m.fat, max(0.7 * 80, 0.25 * 2200 / 9), accuracy: 0.001)   // floor 56 vs 61.1 → 61.1
        XCTAssertEqual(m.carbs, (2200 - 4 * 176 - 9 * m.fat) / 4, accuracy: 0.001)
        XCTAssertEqual(m.fibre, 30.8, accuracy: 0.001)
    }

    func testFatFloorWins() {
        let m = NutritionEngine.macros(kcal: 1500, bodyweightKg: 90, proteinPerKg: 2.2)
        XCTAssertEqual(m.fat, 63, accuracy: 0.001)   // 0.7 × 90 beats 25% of 1500 / 9 = 41.7
    }

    func testTrendRateOverSevenDays() {
        let trend = (0...8).map { DatedValue(date: day(-$0), value: 80 + 0.05 * Double($0)) }   // −0.35 kg over 7 days
        let rate = NutritionEngine.trendRatePercentPerWeek(trend: trend, asOf: .now)!
        XCTAssertEqual(rate, -0.35 / 80 * 100, accuracy: 0.001)
    }

    func testDailyGoalOffset() {
        // −0.5%/week of 80 kg = −0.4 kg/week = −3080 kcal/week = −440 kcal/day
        XCTAssertEqual(NutritionEngine.dailyGoalOffsetKcal(ratePercentPerWeek: -0.5, bodyweightKg: 80), -440, accuracy: 0.001)
    }
}
