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
        let expected = 80.0 + (1 - pow(0.9, 7.0)) * (78.0 - 80.0)
        XCTAssertEqual(trend[1].value, expected, accuracy: 0.0001)
        XCTAssertLessThan(trend[1].value, 79.0, "more than the single 0.1 step of the per-entry rule")
    }

    func testTrendRateIsNilOnceTheLatestWeighInIsStale() {
        // Weigh-ins stopped: the rate of a week long gone must not read as this week's.
        let trend = (10...24).map { DatedValue(date: day(-$0), value: 80 - 0.1 * Double(24 - $0)) }
        XCTAssertNil(NutritionEngine.trendRatePercentPerWeek(trend: trend, asOf: .now), "latest point is 10 days old")
        XCTAssertNotNil(NutritionEngine.trendRatePercentPerWeek(trend: trend, asOf: day(-10)), "fresh as of the last weigh-in")
        XCTAssertNotNil(NutritionEngine.trendRatePercentPerWeek(trend: trend, asOf: day(-3)), "seven days old is still current")
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
        // 14 logged days (yesterday back), 0.5 kg lost from the first day's morning to this
        // morning: 14 days, as the spec's formula divides by. 7700 × 0.5 / 14 = 275 kcal.
        let intake = (1...14).map { DatedValue(date: day(-$0), value: 2000) }
        let trend = (0...15).map { DatedValue(date: day(-$0), value: 80 + 0.5 * Double($0) / 14) }
        let est = NutritionEngine.expenditure(intake: intake, trend: trend, asOf: .now)!
        XCTAssertEqual(est.weightChangeKg, -0.5, accuracy: 0.001)
        XCTAssertEqual(est.spanDays, 14)
        XCTAssertEqual(est.tdee, 2275, accuracy: 0.01)
    }

    func testWindowExtendsAcrossIntakeGapsAndOlderDaysAreLeftOut() {
        // Food logged every other day: the 14 logged days reach back 27 days. Three older,
        // heavier days are outside the window and must not move the mean.
        let logged = stride(from: 1, through: 27, by: 2).map { DatedValue(date: day(-$0), value: 2000) }
        let older = [29, 31, 33].map { DatedValue(date: day(-$0), value: 3000) }
        let trend = (0...35).map { DatedValue(date: day(-$0), value: 80) }
        let est = NutritionEngine.expenditure(intake: logged + older, trend: trend, asOf: .now)!
        XCTAssertEqual(est.loggedDays, 14)
        XCTAssertEqual(est.spanDays, 27)
        XCTAssertEqual(est.tdee, 2000, accuracy: 0.001)
        XCTAssertEqual(est.confidence, .high)
    }

    func testConfidenceBoundaries() {
        let trend = (0...20).map { DatedValue(date: day(-$0), value: 80) }
        func confidence(_ days: Int) -> Confidence? {
            NutritionEngine.expenditure(intake: (1...days).map { DatedValue(date: day(-$0), value: 2000) }, trend: trend, asOf: .now)?.confidence
        }
        XCTAssertNil(confidence(3))
        XCTAssertEqual(confidence(4), .low)
        XCTAssertEqual(confidence(9), .low)
        XCTAssertEqual(confidence(10), .medium)
        XCTAssertEqual(confidence(13), .medium)
        XCTAssertEqual(confidence(14), .high)
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

    func testAdjustmentBandEdges() {
        // Exactly 0.15 off holds; just past it steps 100. Exactly 0.5 off is still 100 with no
        // note; past it is 150 with the logging note. Both signs.
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.35, goalRatePercentPerWeek: -0.5).kcal, 0)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.65, goalRatePercentPerWeek: -0.5).kcal, 0)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.34, goalRatePercentPerWeek: -0.5).kcal, -100)
        let atHalf = NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: 0, goalRatePercentPerWeek: -0.5)
        XCTAssertEqual(atHalf.kcal, -100)
        XCTAssertNil(atHalf.note)
        let pastHalf = NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: 0.01, goalRatePercentPerWeek: -0.5)
        XCTAssertEqual(pastHalf.kcal, -150)
        XCTAssertNotNil(pastHalf.note)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: 0.4, goalRatePercentPerWeek: 0.25).kcal, 0)
        XCTAssertEqual(NutritionEngine.weeklyAdjustment(trendRatePercentPerWeek: -0.3, goalRatePercentPerWeek: 0.25).kcal, 150)
    }

    func testMacrosForACut() {
        // 2200 kcal at 80 kg: protein 2.2 × 80 = 176 g (704 kcal); fat is the larger of the
        // 0.7 g/kg floor (56 g) and 25% of calories (550 kcal = 61.1 g); carbs take the rest.
        let m = NutritionEngine.macros(kcal: 2200, bodyweightKg: 80, proteinPerKg: 2.2)
        XCTAssertEqual(m.protein, 176)
        XCTAssertEqual(m.fat, 61.11, accuracy: 0.01)
        XCTAssertEqual(m.carbs, 236.5, accuracy: 0.01)   // (2200 − 704 − 550) / 4
        XCTAssertEqual(m.fibre, 30.8, accuracy: 0.001)
    }

    func testCarbsNeverGoNegative() {
        // Protein and the fat floor alone exceed the calories: carbs clamp at zero.
        let m = NutritionEngine.macros(kcal: 1200, bodyweightKg: 100, proteinPerKg: 2.2)
        XCTAssertEqual(m.carbs, 0)
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
