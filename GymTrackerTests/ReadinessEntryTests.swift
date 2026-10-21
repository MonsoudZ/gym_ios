import XCTest
@testable import GymTracker

final class ReadinessEntryTests: XCTestCase {
    private let calendar = Calendar.current

    @MainActor
    func testEntryIsKeyedToTheStartOfItsDay() {
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 15))!
        let entry = ReadinessEntry(date: afternoon, sleepHours: 7)
        XCTAssertEqual(entry.date, calendar.startOfDay(for: afternoon))
        let evening = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 22))!
        XCTAssertTrue(ReadinessEntry.entry(for: evening, in: [entry]) === entry)
        let nextDay = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 7))!
        XCTAssertNil(ReadinessEntry.entry(for: nextDay, in: [entry]))
    }

    @MainActor
    func testEmptyEntryIsNotLoggedUntilSomethingIsEntered() {
        let entry = ReadinessEntry(date: .now)
        XCTAssertFalse(entry.isLogged)
        entry.soreMuscles = [.chest]
        XCTAssertTrue(entry.isLogged)
        XCTAssertEqual(entry.readiness.soreness[.chest], Readiness.sorenessThreshold)
        XCTAssertTrue(entry.readiness.isLow(for: [MuscleWeight(muscle: .chest, weight: 1)]))
        entry.soreMuscles = []
        XCTAssertFalse(entry.isLogged)
    }

    @MainActor
    func testHealthSleepFillsTheDayButIsNotACheckInAndTypingWins() {
        let entry = ReadinessEntry(date: .now)
        XCTAssertTrue(entry.applyHealthSleep(7.26))
        XCTAssertEqual(entry.sleepHours, 7.3, "rounded to a tenth, as the field shows it")
        XCTAssertTrue(entry.sleepFromHealth)
        XCTAssertFalse(entry.isLogged, "Health filled it; the lifter has not checked in")
        XCTAssertTrue(entry.readiness.hasAnyInput, "but the plan still uses it")
        XCTAssertFalse(entry.applyHealthSleep(7.26), "same value again changes nothing")

        // Health's number moves (a late sync): a Health-filled day follows it.
        XCTAssertTrue(entry.applyHealthSleep(5.5))
        XCTAssertEqual(entry.sleepHours, 5.5)
        XCTAssertTrue(entry.readiness.isLow(for: []))

        // The lifter types over it: now it is a check-in and Health leaves it alone.
        entry.setTypedSleep(8)
        XCTAssertTrue(entry.isLogged)
        XCTAssertFalse(entry.sleepFromHealth)
        XCTAssertFalse(entry.applyHealthSleep(6))
        XCTAssertEqual(entry.sleepHours, 8)

        // Turning the feature off clears only a Health-filled value.
        XCTAssertFalse(entry.applyHealthSleep(nil))
        XCTAssertEqual(entry.sleepHours, 8)
        let healthOnly = ReadinessEntry(date: .now)
        healthOnly.applyHealthSleep(7)
        XCTAssertTrue(healthOnly.applyHealthSleep(nil))
        XCTAssertNil(healthOnly.sleepHours)
        XCTAssertFalse(healthOnly.sleepFromHealth)
    }

    @MainActor
    func testSessionCopiesTheDaysCheckIn() {
        let entry = ReadinessEntry(date: .now, sleepHours: 5.5, soreness: [.quads: 4])
        let session = WorkoutSession(templateDayName: "Lower A", readiness: entry)
        XCTAssertEqual(session.sleepHours, 5.5)
        XCTAssertEqual(session.readiness.soreness[.quads], 4)
        XCTAssertTrue(session.readiness.isLow(for: [MuscleWeight(muscle: .quads, weight: 1)]))

        let blank = WorkoutSession(templateDayName: "Lower A", readiness: nil)
        XCTAssertNil(blank.sleepHours)
        XCTAssertFalse(blank.readiness.hasAnyInput)
    }

    private let lowHeart = HeartReadiness(hrvMs: 40, restingHeartRate: 64,
                                          hrvBaseline: HeartBaseline(mean: 50, standardDeviation: 2.16, days: 7),
                                          restingHeartRateBaseline: HeartBaseline(mean: 59, standardDeviation: 1.41, days: 7))

    @MainActor
    func testHeartReadingRoundTripsAndIsNotACheckIn() {
        let entry = ReadinessEntry(date: .now)
        entry.heart = lowHeart
        XCTAssertEqual(entry.heart, lowHeart)
        XCTAssertFalse(entry.isLogged, "a Health reading alone is not something the lifter logged")
        XCTAssertTrue(entry.readiness.hasAnyInput)
        XCTAssertTrue(entry.readiness.isLow(for: [MuscleWeight(muscle: .chest, weight: 1)]))
        entry.heart = nil
        XCTAssertNil(entry.heart)
        XCTAssertFalse(entry.readiness.hasAnyInput)
    }

    @MainActor
    func testHeartReadingWithoutABaselineRoundTrips() {
        let entry = ReadinessEntry(date: .now)
        entry.heart = HeartReadiness(hrvMs: 45, restingHeartRate: nil)
        XCTAssertEqual(entry.heart?.hrvMs, 45)
        XCTAssertNil(entry.heart?.restingHeartRate)
        XCTAssertNil(entry.heart?.hrvBaseline)
        XCTAssertFalse(entry.readiness.isLow(for: [MuscleWeight(muscle: .chest, weight: 1)]))
    }

    @MainActor
    func testSessionCopiesTheDaysHeartReading() {
        let entry = ReadinessEntry(date: .now, sleepHours: 8)
        entry.heart = lowHeart
        let session = WorkoutSession(templateDayName: "Upper A", readiness: entry)
        XCTAssertEqual(session.heart, lowHeart)
        XCTAssertTrue(session.readiness.isLow(for: [MuscleWeight(muscle: .chest, weight: 1)]))
    }
}
