import XCTest
@testable import GymTracker

final class RelativeStrengthTests: XCTestCase {
    private let cal = Calendar.current
    private var today: Date { cal.startOfDay(for: .now) }
    private func day(_ offset: Int, hour: Int = 0) -> Date {
        cal.date(byAdding: .hour, value: hour, to: cal.date(byAdding: .day, value: offset, to: today)!)!
    }

    func testRatioIsE1RMOverBodyweight() {
        XCTAssertEqual(RelativeStrength.ratio(e1RMKg: 120, bodyweightKg: 80)!, 1.5, accuracy: 0.0001)
        XCTAssertNil(RelativeStrength.ratio(e1RMKg: 120, bodyweightKg: 0))
        XCTAssertNil(RelativeStrength.ratio(e1RMKg: 0, bodyweightKg: 80))
    }

    func testUsesTrendValueOnOrBeforeEachSession() {
        let trend = NutritionEngine.trend([
            DatedValue(date: day(-10), value: 80),
            DatedValue(date: day(-5), value: 78),
        ])
        let e1RM = [
            DatedValue(date: day(-7, hour: 18), value: 100),   // only the day -10 weigh-in is before it
            DatedValue(date: day(-5, hour: 18), value: 100),   // same-day weigh-in counts
            DatedValue(date: day(-1, hour: 18), value: 100),   // latest trend carries forward
        ]
        let ratios = RelativeStrength.ratios(e1RM: e1RM, trend: trend)
        XCTAssertEqual(ratios.count, 3)
        XCTAssertEqual(ratios[0]!, 100 / 80, accuracy: 0.0001)
        XCTAssertEqual(ratios[1]!, 100 / trend[1].value, accuracy: 0.0001)
        XCTAssertEqual(ratios[2]!, 100 / trend[1].value, accuracy: 0.0001)
        XCTAssertNotEqual(trend[1].value, 78, "trend should be smoothed, not the raw weigh-in")
    }

    func testSessionsBeforeFirstWeighInAreNil() {
        let trend = NutritionEngine.trend([DatedValue(date: day(-3), value: 80)])
        let e1RM = [DatedValue(date: day(-6), value: 100), DatedValue(date: day(-2), value: 100)]
        let ratios = RelativeStrength.ratios(e1RM: e1RM, trend: trend)
        XCTAssertNil(ratios[0])
        XCTAssertEqual(ratios[1]!, 1.25, accuracy: 0.0001)
    }

    func testNoWeighInsGivesAllNilAndEmptySeries() {
        let e1RM = [DatedValue(date: day(-6), value: 100), DatedValue(date: day(-2), value: 110)]
        XCTAssertEqual(RelativeStrength.ratios(e1RM: e1RM, trend: []).map { $0 == nil }, [true, true])
        XCTAssertTrue(RelativeStrength.series(e1RM: e1RM, trend: []).isEmpty)
    }

    func testSeriesDropsSessionsWithoutWeightAndKeepsDates() {
        let trend = NutritionEngine.trend([DatedValue(date: day(-3), value: 80)])
        let e1RM = [DatedValue(date: day(-6), value: 100), DatedValue(date: day(-2), value: 100)]
        let series = RelativeStrength.series(e1RM: e1RM, trend: trend)
        XCTAssertEqual(series.map(\.date), [day(-2)])
        XCTAssertEqual(series[0].value, 1.25, accuracy: 0.0001)
    }

    func testRelativeStrengthRisesWhenWeightDropsAndLiftHolds() {
        // The cutting case: same e1RM, bodyweight falling, ratio must climb.
        let weights = (0..<30).map { DatedValue(date: day(-29 + $0), value: 85 - 0.1 * Double($0)) }
        let trend = NutritionEngine.trend(weights)
        let e1RM = [DatedValue(date: day(-28, hour: 12), value: 120), DatedValue(date: day(0, hour: 12), value: 120)]
        let series = RelativeStrength.series(e1RM: e1RM, trend: trend)
        XCTAssertEqual(series.count, 2)
        XCTAssertGreaterThan(series[1].value, series[0].value)
    }

    func testLabelIsUnitless() {
        XCTAssertEqual(RelativeStrength.label(1.5), "1.5× bodyweight")
        XCTAssertEqual(RelativeStrength.label(1.5234), "1.52× bodyweight")
    }
}
