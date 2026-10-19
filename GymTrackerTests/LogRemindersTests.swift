import XCTest
@testable import GymTracker

final class LogRemindersTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()

    private func october(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func plan(at now: Date, weight: Bool = false, intake: Bool = false, minutes: Int = 600) -> [PlannedReminder] {
        LogReminders.plan(now: now, minutesAfterMidnight: minutes, hasWeightToday: weight, hasIntakeToday: intake, calendar: calendar)
    }

    func testBeforeTheReminderTimeTodayIsIncludedAndTheHorizonIsFull() {
        let planned = plan(at: october(19, hour: 7))
        XCTAssertEqual(planned.count, LogReminders.horizonDays)
        XCTAssertEqual(planned.first?.date, october(19, hour: 10))
        XCTAssertEqual(planned.last?.date, october(19, hour: 10).addingTimeInterval(13 * 86_400))
    }

    func testAfterTheReminderTimeTodayIsSkipped() {
        let planned = plan(at: october(19, hour: 11))
        XCTAssertEqual(planned.first?.date, october(20, hour: 10))
        XCTAssertEqual(planned.count, LogReminders.horizonDays - 1)
    }

    func testTodayDropsOutOnceBothAreLoggedButTomorrowStays() {
        let planned = plan(at: october(19, hour: 7), weight: true, intake: true)
        XCTAssertEqual(planned.first?.date, october(20, hour: 10))
    }

    func testTodaysMessageNamesWhatIsMissing() {
        XCTAssertTrue(plan(at: october(19, hour: 7), weight: true).first!.body.contains("eaten"))
        XCTAssertTrue(plan(at: october(19, hour: 7), intake: true).first!.body.contains("weight"))
        let both = plan(at: october(19, hour: 7)).first!.body
        XCTAssertTrue(both.contains("weight") && both.contains("eat"))
    }

    func testLaterDaysGetTheGeneralMessage() {
        let planned = plan(at: october(19, hour: 7), weight: true)
        XCTAssertEqual(planned[1].body, plan(at: october(19, hour: 7))[1].body)
    }

    func testCustomTimeIsHonoured() {
        let planned = plan(at: october(19, hour: 7), minutes: 8 * 60 + 30)
        XCTAssertEqual(planned.first?.date, october(19, hour: 8, minute: 30))
    }

    func testIdentifiersAreOnePerDay() {
        XCTAssertEqual(LogReminders.identifier(for: october(9, hour: 10), calendar: calendar), "log-reminder-2026-10-09")
        let ids = Set(plan(at: october(19, hour: 7)).map { LogReminders.identifier(for: $0.date, calendar: calendar) })
        XCTAssertEqual(ids.count, LogReminders.horizonDays)
    }
}
