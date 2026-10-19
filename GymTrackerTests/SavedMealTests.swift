import XCTest
import SwiftData
@testable import GymTracker

final class SavedMealTests: XCTestCase {
    private var container: ModelContainer?

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([IntakeEntry.self, SavedMeal.self, UserSettings.self, BodyweightEntry.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    @MainActor
    private func breakfast(in context: ModelContext) -> SavedMeal {
        let entries = [
            IntakeEntry(name: "Oats", kcal: 300, protein: 10, carbs: 54, fat: 6, fibre: 8, grams: 80),
            IntakeEntry(name: "Whey", kcal: 120, protein: 25, carbs: 3, fat: 1, grams: 30),
            IntakeEntry(name: "Banana", kcal: 105, protein: 1, carbs: 27, fat: 0, fibre: 3, grams: 118),
            IntakeEntry(name: "Milk", kcal: 90, protein: 6, carbs: 9, fat: 3, grams: 180),
        ]
        entries.forEach(context.insert)
        return SavedMeal(name: "Usual breakfast", from: entries)
    }

    @MainActor
    func testMealKeepsEveryFoodAndSumsTheirMacros() throws {
        let context = try makeContext()
        let meal = breakfast(in: context)
        XCTAssertEqual(meal.components.map(\.name), ["Oats", "Whey", "Banana", "Milk"])
        let totals = meal.totals()
        XCTAssertEqual(totals.kcal, 615)
        XCTAssertEqual(totals.protein, 42)
        XCTAssertEqual(totals.carbs, 93)
        XCTAssertEqual(totals.fat, 10)
        XCTAssertEqual(totals.fibre, 11)
    }

    @MainActor
    func testLoggingCreatesOneEntryPerFoodAndCountsTheUse() throws {
        let context = try makeContext()
        let meal = breakfast(in: context)
        context.insert(meal)
        let before = try context.fetchCount(FetchDescriptor<IntakeEntry>())
        let logged = meal.log(in: context)
        XCTAssertEqual(logged.count, 4)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<IntakeEntry>()) - before, 4)
        XCTAssertEqual(logged.map(\.kcal).reduce(0, +), 615)
        XCTAssertEqual(meal.useCount, 1)
    }

    @MainActor
    func testPortionScalesCaloriesMacrosAndGrams() throws {
        let context = try makeContext()
        let meal = breakfast(in: context)
        let half = meal.log(scale: 0.5, in: context)
        XCTAssertEqual(half.map(\.kcal).reduce(0, +), 307.5, accuracy: 0.001)
        XCTAssertEqual(half.first?.grams, 40)
        XCTAssertEqual(meal.totals(scale: 2).protein, 84)
    }

    @MainActor
    func testLoggedEntriesCountTowardTodaysIntake() throws {
        let context = try makeContext()
        let meal = breakfast(in: context)
        meal.log(in: context)
        let settings = UserSettings()
        let snapshot = NutritionService.snapshot(settings: settings, weights: [], intake: try context.fetch(FetchDescriptor<IntakeEntry>()))
        XCTAssertEqual(snapshot.eatenToday.kcal, 615 * 2, "the four source entries plus the four just logged")
    }
}
