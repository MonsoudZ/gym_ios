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
