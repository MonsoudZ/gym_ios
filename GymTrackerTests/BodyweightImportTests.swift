import XCTest
@testable import GymTracker

final class BodyweightImportTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    private func at(_ day: Int, _ hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }
    private func day(_ d: Int) -> Date { calendar.startOfDay(for: at(d, 12)) }

    func testEarliestSampleOfEachDayIsTheMorningWeight() {
        let samples = [
            HealthWeightSample(date: at(18, 21), kg: 81.4),   // evening, heavier
            HealthWeightSample(date: at(18, 7), kg: 80.2),
            HealthWeightSample(date: at(19, 6), kg: 80.0),
            HealthWeightSample(date: at(19, 9), kg: 80.6),
            HealthWeightSample(date: at(20, 7), kg: 0),       // a bad sample
        ]
        let morning = BodyweightImport.morningWeights(samples, calendar: calendar)
        XCTAssertEqual(morning, [day(18): 80.2, day(19): 80.0])
    }

    func testNewDaysAreInsertedTypedDaysKeptHealthDaysUpdated() {
        let morning = [day(17): 81.0, day(18): 80.2, day(19): 80.0, day(20): 79.8]
        let existing = [
            ExistingWeight(date: day(18), kg: 80.9, fromHealth: false),   // typed: left alone
            ExistingWeight(date: day(19), kg: 80.3, fromHealth: true),    // Health, now re-synced
            ExistingWeight(date: day(20), kg: 79.8, fromHealth: true),    // Health, unchanged
        ]
        let changes = BodyweightImport.changes(morning: morning, existing: existing)
        XCTAssertEqual(changes, [
            BodyweightImport.Change(date: day(17), kg: 81.0, kind: .insert),
            BodyweightImport.Change(date: day(19), kg: 80.0, kind: .update),
        ])
    }

    func testNothingToDoIsEmpty() {
        XCTAssertTrue(BodyweightImport.changes(morning: [:], existing: []).isEmpty)
        XCTAssertTrue(BodyweightImport.changes(morning: [day(1): 80], existing: [ExistingWeight(date: day(1), kg: 80, fromHealth: true)]).isEmpty)
    }

    @MainActor
    func testEntryRecordsItsSource() {
        XCTAssertFalse(BodyweightEntry(date: .now, kg: 80).fromHealth)
        XCTAssertTrue(BodyweightEntry(date: .now, kg: 80, fromHealth: true).fromHealth)
    }
}
