import XCTest
@testable import GymTracker

/// The snapshot the Nutrition and Today tabs show: when the target stops being provisional and
/// when a weekly check is offered.
final class NutritionServiceTests: XCTestCase {
    private let calendar = Calendar.current
    private func day(_ offset: Int, hour: Int = 8) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!)!
    }

    @MainActor
    private func history(days: Int) -> (weights: [BodyweightEntry], intake: [IntakeEntry]) {
        let weights = (0...days).map { BodyweightEntry(date: day(-$0), kg: 80) }
        let intake = (1...days).map { IntakeEntry(date: day(-$0, hour: 12), name: "Day", kcal: 2200) }
        return (weights, intake)
    }

    @MainActor
    func testTargetIsProvisionalUntilFourteenLoggedDays() {
        let settings = UserSettings()
        let short = history(days: 11)
        let snap11 = NutritionService.snapshot(settings: settings, weights: short.weights, intake: short.intake)
        XCTAssertEqual(snap11.estimate?.confidence, .medium)
        XCTAssertTrue(snap11.isProvisional, "eleven logged days is medium confidence but still calibrating")
        let full = history(days: 14)
        let snap14 = NutritionService.snapshot(settings: settings, weights: full.weights, intake: full.intake)
        XCTAssertFalse(snap14.isProvisional)
        XCTAssertEqual(snap14.baseKcal, 2200, accuracy: 0.001)
    }

    @MainActor
    func testNoWeeklyCheckWhileTheTargetIsProvisional() {
        // Eleven logged days, a month old install: due by the calendar, but the target is still
        // the formula's, so there is no adaptive rate to adjust yet.
        let settings = UserSettings()
        settings.createdAt = day(-30)
        let short = history(days: 11)
        let snap = NutritionService.snapshot(settings: settings, weights: short.weights, intake: short.intake)
        XCTAssertTrue(snap.isProvisional)
        XCTAssertNil(snap.suggestedAdjustment)
    }

    @MainActor
    func testWeeklyCheckNeedsAWeighInSinceTheLastOne() {
        // Food logged every day; the last weigh-in was the morning of the last check, seven days
        // ago, so the rate is still fresh enough to exist but it is the one already acted on.
        let settings = UserSettings()
        settings.createdAt = day(-40)
        let intake = (1...30).map { IntakeEntry(date: day(-$0, hour: 12), name: "Day", kcal: 2200) }
        let weights = (7...30).map { BodyweightEntry(date: day(-$0), kg: 80 - 0.05 * Double(30 - $0)) }
        settings.lastAdjustmentDate = day(-7, hour: 10)
        let snap = NutritionService.snapshot(settings: settings, weights: weights, intake: intake)
        XCTAssertNotNil(snap.trendRatePercentPerWeek, "a week-old weigh-in still gives a rate")
        XCTAssertNil(snap.suggestedAdjustment, "but no weigh-in since the check, so nothing to act on")
        let weighedToday = weights + [BodyweightEntry(date: day(0), kg: 79)]
        XCTAssertNotNil(NutritionService.snapshot(settings: settings, weights: weighedToday, intake: intake).suggestedAdjustment)
    }

    @MainActor
    func testWeeklyCheckWaitsAWeekFromTheGoalBeingSet() {
        let settings = UserSettings()
        let full = history(days: 20)
        settings.createdAt = day(-2)
        XCTAssertNil(NutritionService.snapshot(settings: settings, weights: full.weights, intake: full.intake).suggestedAdjustment,
                     "two days in, no check yet")
        settings.createdAt = day(-30)
        settings.lastAdjustmentDate = day(-3)
        XCTAssertNil(NutritionService.snapshot(settings: settings, weights: full.weights, intake: full.intake).suggestedAdjustment)
        settings.lastAdjustmentDate = day(-7)
        XCTAssertNotNil(NutritionService.snapshot(settings: settings, weights: full.weights, intake: full.intake).suggestedAdjustment)
        settings.lastAdjustmentDate = nil
        XCTAssertNotNil(NutritionService.snapshot(settings: settings, weights: full.weights, intake: full.intake).suggestedAdjustment,
                        "never checked, created a month ago: due")
    }
}
