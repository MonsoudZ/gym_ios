import XCTest
import SwiftData
@testable import GymTracker

/// The nutrition half of the backup: bodyweight.csv and food.csv come back through the parser
/// whole, and applying them never overwrites or doubles what is already logged.
final class NutritionImportTests: XCTestCase {
    private let calendar = Calendar.current
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

    private func day(_ offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: .now))!
    }

    // MARK: Parsing

    @MainActor
    func testWeighInsRoundTripThroughTheExport() throws {
        _ = try makeContext()
        let entries = [BodyweightEntry(date: day(-2), kg: 80.25), BodyweightEntry(date: day(-1), kg: 79.9, fromHealth: true)]
        let file = try NutritionImportParser.parse(CSVExport.bodyweight(entries))
        XCTAssertEqual(file.kind, .bodyweight)
        XCTAssertEqual(file.weighIns, [ImportedWeighIn(day: day(-2), kg: 80.25, fromHealth: false),
                                       ImportedWeighIn(day: day(-1), kg: 79.9, fromHealth: true)])
        XCTAssertEqual(file.skippedRows, 0)
    }

    @MainActor
    func testFoodRoundTripsThroughTheExport() throws {
        _ = try makeContext()
        let lunch = calendar.date(bySettingHour: 13, minute: 5, second: 0, of: day(-1))!
        let entries = [IntakeEntry(date: lunch, name: "Rice, chicken \"bowl\"", kcal: 650, protein: 45, carbs: 80, fat: 12, fibre: 4, grams: 420),
                       IntakeEntry(date: lunch.addingTimeInterval(3600), name: "Apple", kcal: 95)]
        let file = try NutritionImportParser.parse(CSVExport.food(entries))
        XCTAssertEqual(file.kind, .food)
        XCTAssertEqual(file.foods.count, 2)
        XCTAssertEqual(file.foods[0], ImportedFood(date: lunch, name: "Rice, chicken \"bowl\"", kcal: 650, protein: 45, carbs: 80, fat: 12, fibre: 4, grams: 420))
        XCTAssertEqual(file.foods[1].name, "Apple")
        XCTAssertNil(file.foods[1].grams)
        XCTAssertEqual(file.foods[1].date, lunch.addingTimeInterval(3600))
    }

    func testPoundsOnlyDecimalCommasMissingTimesAndBadRows() throws {
        let weights = "date,lb\n2026-10-20,176.4\n2026-10-21,\nnot a date,180\n"
        let file = try NutritionImportParser.parse(weights)
        XCTAssertEqual(file.weighIns.count, 1)
        XCTAssertEqual(file.weighIns[0].kg, Units.kg(fromLb: 176.4), accuracy: 0.0001)
        XCTAssertEqual(file.skippedRows, 2)

        let food = "date;name;kcal;protein_g\n2026-10-20;Oats;\"350,5\";12\n2026-10-20;;100;0\n"
        let meals = try NutritionImportParser.parse(food)
        XCTAssertEqual(meals.foods.count, 1)
        XCTAssertEqual(meals.foods[0].kcal, 350.5)
        XCTAssertEqual(calendar.component(.hour, from: meals.foods[0].date), 12, "no time: noon, like a backdated entry")
        XCTAssertEqual(meals.skippedRows, 1)
    }

    func testOtherFilesAreRefused() {
        XCTAssertThrowsError(try NutritionImportParser.parse("title,start_time,exercise_title\nA,2026-10-20,Squat\n")) {
            XCTAssertEqual($0 as? NutritionImportError, .unknownFormat)
        }
        XCTAssertThrowsError(try NutritionImportParser.parse("date,kg\n")) {
            XCTAssertEqual($0 as? NutritionImportError, .noRows)
        }
    }

    // MARK: Applying

    @MainActor
    func testWeighInsNeverOverwriteAndImportTwiceAddsNothing() throws {
        let context = try makeContext()
        context.insert(BodyweightEntry(date: day(-1), kg: 81))   // typed by the lifter
        try context.save()
        let file = try NutritionImportParser.parse("date,kg,source\n2026-01-01,80,typed\n\(CSVExport.day(day(-1))),79,health\n")
        XCTAssertEqual(NutritionImportService.alreadyPresent(file, context: context), 1)

        let first = NutritionImportService.apply(file, context: context)
        XCTAssertEqual(first, NutritionImportService.Outcome(added: 1, skipped: 1))
        let entries = try context.fetch(FetchDescriptor<BodyweightEntry>())
        XCTAssertEqual(entries.first { $0.date == day(-1) }?.kg, 81, "the typed weigh-in stays")
        XCTAssertEqual(entries.count, 2)

        let again = NutritionImportService.apply(file, context: context)
        XCTAssertEqual(again, NutritionImportService.Outcome(added: 0, skipped: 2))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyweightEntry>()), 2)
    }

    @MainActor
    func testFoodAlreadyLoggedIsNotDoubled() throws {
        let context = try makeContext()
        let lunch = calendar.date(bySettingHour: 13, minute: 5, second: 30, of: day(-1))!
        context.insert(IntakeEntry(date: lunch, name: "Eggs", kcal: 300))
        try context.save()
        // The export keeps the minute, not the second: the same entry still matches.
        let text = CSVExport.food([IntakeEntry(date: lunch, name: "Eggs", kcal: 300), IntakeEntry(date: lunch, name: "Toast", kcal: 180)])
        let file = try NutritionImportParser.parse(text)
        XCTAssertEqual(NutritionImportService.alreadyPresent(file, context: context), 1)
        let outcome = NutritionImportService.apply(file, context: context)
        XCTAssertEqual(outcome, NutritionImportService.Outcome(added: 1, skipped: 1))
        XCTAssertEqual(try context.fetch(FetchDescriptor<IntakeEntry>()).map(\.name).sorted(), ["Eggs", "Toast"])
    }
}
