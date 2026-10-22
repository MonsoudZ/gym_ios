import XCTest
@testable import GymTracker

final class PersonalRecordsTests: XCTestCase {
    private func day(_ n: Int) -> Date { Date(timeIntervalSinceReferenceDate: Double(n) * 86_400) }
    private func session(_ n: Int, _ sets: [LoggedSet]) -> SessionResult {
        SessionResult(date: day(n), sets: sets, sessionID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n)))
    }

    func testThreeRecordsComeFromTheRightSets() {
        let history = [
            session(1, [LoggedSet(weight: 80, reps: 8, rpe: 8), LoggedSet(weight: 80, reps: 8)]),
            session(2, [LoggedSet(weight: 100, reps: 3, rpe: 9), LoggedSet(weight: 90, reps: 6)]),
            session(3, [LoggedSet(weight: 100, reps: 5, rpe: 9.5), LoggedSet(weight: 85, reps: 12)]),
        ]
        let records = PersonalRecords.compute(from: history, repRangeLow: 6, repRangeHigh: 8)
        // 100 × 5 → 116.7 beats 85 × 12 (not trusted past 10 reps) and 80 × 8 → 101.3.
        XCTAssertEqual(records.bestE1RM?.weight, 100)
        XCTAssertEqual(records.bestE1RM?.reps, 5)
        XCTAssertEqual(records.bestE1RM?.date, day(3))
        XCTAssertEqual(records.bestE1RM?.e1RM ?? 0, 100 * (1 + 5.0 / 30), accuracy: 0.001)
        // Heaviest set with 6–8 reps is 90 × 6.
        XCTAssertEqual(records.bestInRepRange?.weight, 90)
        XCTAssertEqual(records.bestInRepRange?.reps, 6)
        // Top weight is 100; most reps there is 5.
        XCTAssertEqual(records.mostRepsAtTopWeight?.weight, 100)
        XCTAssertEqual(records.mostRepsAtTopWeight?.reps, 5)
        XCTAssertEqual(records.mostRepsAtTopWeight?.rpe, 9.5)
        XCTAssertEqual(records.mostRepsAtTopWeight?.sessionID, history[2].sessionID)
    }

    func testTiesGoToTheSetThatWasDoneFirst() {
        let history = [
            session(5, [LoggedSet(weight: 100, reps: 5)]),
            session(2, [LoggedSet(weight: 100, reps: 5, rpe: 8)]),
            session(9, [LoggedSet(weight: 100, reps: 5)]),
        ]
        let records = PersonalRecords.compute(from: history, repRangeLow: 3, repRangeHigh: 5)
        XCTAssertEqual(records.bestE1RM?.date, day(2), "history in any order; the earliest tie wins")
        XCTAssertEqual(records.bestInRepRange?.date, day(2))
        XCTAssertEqual(records.mostRepsAtTopWeight?.date, day(2))
        XCTAssertEqual(records.bestE1RM?.rpe, 8)
    }

    func testWarmupsAndEmptySetsNeverCount() {
        let history = [
            session(1, [LoggedSet(weight: 140, reps: 5, isWarmup: true), LoggedSet(weight: 60, reps: 0), LoggedSet(weight: 0, reps: 10),
                        LoggedSet(weight: 80, reps: 8)]),
        ]
        let records = PersonalRecords.compute(from: history, repRangeLow: 6, repRangeHigh: 8)
        XCTAssertEqual(records.bestE1RM?.weight, 80)
        XCTAssertEqual(records.mostRepsAtTopWeight?.weight, 80)
        XCTAssertEqual(records.bestInRepRange?.weight, 80)
        let onlyWarmups = PersonalRecords.compute(from: [session(1, [LoggedSet(weight: 140, reps: 5, isWarmup: true)])], repRangeLow: 6, repRangeHigh: 8)
        XCTAssertTrue(onlyWarmups.isEmpty)
        XCTAssertTrue(PersonalRecords.compute(from: [], repRangeLow: 6, repRangeHigh: 8).isEmpty)
    }

    func testCorrectingAMistypedSetRemovesThePR() {
        var history = [
            session(1, [LoggedSet(weight: 80, reps: 8)]),
            session(2, [LoggedSet(weight: 800, reps: 8)]),   // a typo: 800 for 80
        ]
        XCTAssertEqual(PersonalRecords.compute(from: history, repRangeLow: 6, repRangeHigh: 8).bestE1RM?.weight, 800)
        history[1] = session(2, [LoggedSet(weight: 80, reps: 8)])
        let fixed = PersonalRecords.compute(from: history, repRangeLow: 6, repRangeHigh: 8)
        XCTAssertEqual(fixed.bestE1RM?.weight, 80)
        XCTAssertEqual(fixed.bestE1RM?.date, day(1), "the two sets tie, so the first stands")
    }

    func testBestInRangeOnlyConsidersSetsInsideTheRange() {
        let history = [session(1, [LoggedSet(weight: 120, reps: 2), LoggedSet(weight: 70, reps: 15), LoggedSet(weight: 95, reps: 10)])]
        let records = PersonalRecords.compute(from: history, repRangeLow: 8, repRangeHigh: 12)
        XCTAssertEqual(records.bestInRepRange?.weight, 95)
        XCTAssertNil(PersonalRecords.compute(from: history, repRangeLow: 4, repRangeHigh: 6).bestInRepRange)
        XCTAssertEqual(records.mostRepsAtTopWeight?.weight, 120, "the top weight record ignores the range")
        // A set over 10 reps still counts for weight and reps, just not for e1RM.
        XCTAssertEqual(PersonalRecords.compute(from: [session(1, [LoggedSet(weight: 70, reps: 15)])], repRangeLow: 12, repRangeHigh: 15).bestE1RM, nil)
        XCTAssertEqual(PersonalRecords.compute(from: [session(1, [LoggedSet(weight: 70, reps: 15)])], repRangeLow: 12, repRangeHigh: 15).bestInRepRange?.reps, 15)
    }

    func testSetLabelFollowsTheUnitSetting() {
        let record = PersonalRecords.Record(weight: 100, reps: 5, rpe: 8, date: day(1), sessionID: nil)
        XCTAssertEqual(record.setLabel(metric: true), "100 kg × 5 @ RPE 8 · 2 left")
        XCTAssertEqual(record.setLabel(metric: false), "220.5 lb × 5 @ RPE 8 · 2 left")
        let noRPE = PersonalRecords.Record(weight: 60, reps: 12, rpe: nil, date: day(1), sessionID: nil)
        XCTAssertEqual(noRPE.setLabel(metric: true), "60 kg × 12")
        XCTAssertEqual(Units.weight(record.e1RM!, metric: false), "257.2 lb")
    }

    func testRecentSessionsAreNewestFirstAndCapped() {
        let history = (1...8).map { session($0, [LoggedSet(weight: Double($0), reps: 5)]) }.shuffled()
        let recent = PersonalRecords.recent(history)
        XCTAssertEqual(recent.map { $0.sets[0].weight }, [8, 7, 6, 5, 4])
        XCTAssertEqual(PersonalRecords.recent(history, limit: 2).map(\.date), [day(8), day(7)])
        XCTAssertEqual(PersonalRecords.recent([]).count, 0)
    }
}
