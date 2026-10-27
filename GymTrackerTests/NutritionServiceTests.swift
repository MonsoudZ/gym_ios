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
