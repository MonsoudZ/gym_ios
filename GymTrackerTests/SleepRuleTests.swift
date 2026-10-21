import XCTest
@testable import GymTracker

final class SleepRuleTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    /// 08:00 on 19 Oct 2026.
    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 19, hour: 8))! }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testWindowRunsFromYesterdayEveningToEarlyAfternoonClippedToNow() {
        let w = SleepRule.window(now: morning, calendar: calendar)
        XCTAssertEqual(w.start, at(18, 18))
        XCTAssertEqual(w.end, morning, "clipped to now in the morning")
        let evening = at(19, 20)
        XCTAssertEqual(SleepRule.window(now: evening, calendar: calendar).end, at(19, 14))
    }

    func testOneNightSumsToItsLength() {
        let hours = SleepRule.hoursAsleep([SleepInterval(start: at(18, 23), end: at(19, 6, 30))], now: morning, calendar: calendar)
        XCTAssertEqual(hours!, 7.5, accuracy: 0.001)
    }

    func testStagesAddUpAndOverlapsAreNotDoubleCounted() {
        // Watch writes stages back to back; phone writes one blanket sample over the same night.
        let samples = [
            SleepInterval(start: at(18, 23), end: at(19, 1)),
            SleepInterval(start: at(19, 1), end: at(19, 3)),
            SleepInterval(start: at(19, 3, 30), end: at(19, 6)),   // 30 min awake gap
            SleepInterval(start: at(18, 23), end: at(19, 6)),      // phone's duplicate
        ]
        let hours = SleepRule.hoursAsleep(samples, now: morning, calendar: calendar)
        XCTAssertEqual(hours!, 6.5, accuracy: 0.001)
    }

    func testAfternoonNapAndEarlyEveningAreOutsideTheWindow() {
        let samples = [
            SleepInterval(start: at(18, 14), end: at(18, 15)),   // yesterday's nap, before 18:00
            SleepInterval(start: at(18, 17), end: at(18, 19)),   // straddles 18:00: one hour counts
            SleepInterval(start: at(18, 23), end: at(19, 7)),
        ]
        let hours = SleepRule.hoursAsleep(samples, now: morning, calendar: calendar)
        XCTAssertEqual(hours!, 9, accuracy: 0.001)
    }

    func testStillAsleepIsClippedToNow() {
        let hours = SleepRule.hoursAsleep([SleepInterval(start: at(19, 0), end: at(19, 10))], now: morning, calendar: calendar)
        XCTAssertEqual(hours!, 8, accuracy: 0.001)
    }

    func testNothingInTheWindowIsNil() {
        XCTAssertNil(SleepRule.hoursAsleep([], now: morning, calendar: calendar))
        XCTAssertNil(SleepRule.hoursAsleep([SleepInterval(start: at(17, 23), end: at(18, 7))], now: morning, calendar: calendar),
                     "the night before last")
    }
}
