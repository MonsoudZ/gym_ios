import XCTest
import SwiftData
@testable import GymTracker

/// The heavy style halves the library's ranges by band and leaves a lifter's own range alone.
final class RepStyleTests: XCTestCase {
    private var container: ModelContainer?

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, WorkoutSession.self, SetEntry.self,
            BodyweightEntry.self, IntakeEntry.self, UserSettings.self, FoodItem.self,
            Program.self, ProgramDay.self, ReadinessEntry.self, AdjustmentEntry.self, SavedMeal.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    func testHeavyRangesByBand() {
        XCTAssertTrue(RepStyle.strength.range(forDefault: 3, high: 5) == (3, 5), "deadlift is already heavy")
        XCTAssertTrue(RepStyle.strength.range(forDefault: 6, high: 8) == (3, 5), "bench")
        XCTAssertTrue(RepStyle.strength.range(forDefault: 8, high: 12) == (4, 6), "rows and curls")
        XCTAssertTrue(RepStyle.strength.range(forDefault: 10, high: 15) == (6, 8), "leg press")
        XCTAssertTrue(RepStyle.strength.range(forDefault: 12, high: 20) == (8, 12), "lateral raise")
        XCTAssertTrue(RepStyle.balanced.range(forDefault: 8, high: 12) == (8, 12))
        XCTAssertTrue(RepStyle.strength.customDefault == (4, 6))
    }

    @MainActor
    func testApplyingAStyleRemapsDefaultsKeepsEditsAndSwitchesBack() throws {
        let context = try makeContext()
        Seeder.prepare(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = try XCTUnwrap(exercises.first { $0.name == "Barbell Bench Press" })   // 6–8, 3 min rest
        let raise = try XCTUnwrap(exercises.first { $0.name == "Lateral Raise" })         // 12–20, 2 min rest
        let curl = try XCTUnwrap(exercises.first { $0.name == "Barbell Curl" })           // 8–12
        let legPress = try XCTUnwrap(exercises.first { $0.name == "Leg Press" })          // 10–15, 2 min rest
        curl.repRangeLow = 5; curl.repRangeHigh = 8   // the lifter's own range
        let custom = Exercise(name: "Zercher Squat", metric: true, repStyle: .strength)
        context.insert(custom)
        XCTAssertEqual(raise.restSeconds, RestRule.lightSeconds)

        Seeder.applyRepStyle(from: .balanced, to: .strength, context: context)
        XCTAssertEqual(bench.repRangeLow, 3); XCTAssertEqual(bench.repRangeHigh, 5)
        XCTAssertEqual(raise.repRangeLow, 8); XCTAssertEqual(raise.repRangeHigh, 12)
        XCTAssertEqual(raise.restSeconds, RestRule.lightSeconds, "8–12 still tops out above ten reps: two minutes")
        XCTAssertEqual(legPress.repRangeLow, 6); XCTAssertEqual(legPress.repRangeHigh, 8)
        XCTAssertEqual(legPress.restSeconds, RestRule.heavySeconds, "rest follows a range that drops to ten reps or fewer")
        XCTAssertEqual(curl.repRangeLow, 5); XCTAssertEqual(curl.repRangeHigh, 8, "an edited range is kept")
        XCTAssertEqual(custom.repRangeLow, 4); XCTAssertEqual(custom.repRangeHigh, 6, "a custom exercise starts in the style's range")

        bench.repRangeLow = 2; bench.repRangeHigh = 4   // edited while heavy
        Seeder.applyRepStyle(from: .strength, to: .balanced, context: context)
        XCTAssertEqual(raise.repRangeLow, 12); XCTAssertEqual(raise.repRangeHigh, 20, "back to the library default")
        XCTAssertEqual(legPress.repRangeHigh, 15)
        XCTAssertEqual(legPress.restSeconds, RestRule.lightSeconds, "and so does the rest")
        XCTAssertEqual(bench.repRangeLow, 2); XCTAssertEqual(bench.repRangeHigh, 4, "an edit made under the other style is kept too")
        XCTAssertEqual(curl.repRangeLow, 5)
    }
}
