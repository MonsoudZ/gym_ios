import XCTest
import SwiftData
@testable import GymTracker

/// Demo data is additive: it never overwrites what the lifter logged, loads only once, and
/// leaves a chosen goal alone.
final class DemoDataTests: XCTestCase {
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

    @MainActor
    func testLoadingTwiceAddsNothing() throws {
        let context = try makeContext()
        Seeder.prepare(context: context)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        DemoData.load(context: context, exercises: exercises, settings: settings)
        let sessions = try context.fetchCount(FetchDescriptor<WorkoutSession>())
        let sets = try context.fetchCount(FetchDescriptor<SetEntry>())
        let weights = try context.fetchCount(FetchDescriptor<BodyweightEntry>())
        let intake = try context.fetchCount(FetchDescriptor<IntakeEntry>())
        XCTAssertGreaterThan(sessions, 20)
        XCTAssertEqual(settings.goal, .cut, "a fresh install with the default goal gets the demo's cut")

        DemoData.load(context: context, exercises: exercises, settings: settings)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), sessions)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), sets)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyweightEntry>()), weights)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<IntakeEntry>()), intake)

        // Loaded again on a later day: the history stays anchored on its first load, so every
        // key is the same and nothing is written. Anchoring on "today" wrote all 32 sessions again.
        let later = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        DemoData.load(context: context, exercises: exercises, settings: settings, now: later)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), sessions)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), sets)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<BodyweightEntry>()), weights)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<IntakeEntry>()), intake)
    }

    @MainActor
    func testLoggedDaysAndChosenGoalAreKept() throws {
        let context = try makeContext()
        Seeder.prepare(context: context)
        let settings = try XCTUnwrap(try context.fetch(FetchDescriptor<UserSettings>()).first)
        settings.goal = .leanGain
        settings.goalRatePercentPerWeek = 0.25
        let today = Calendar.current.startOfDay(for: .now)
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        context.insert(BodyweightEntry(date: today, kg: 70))
        context.insert(IntakeEntry(date: yesterday.addingTimeInterval(8 * 3600), name: "Eggs", kcal: 300))
        try context.save()

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        DemoData.load(context: context, exercises: exercises, settings: settings)

        let weights = try context.fetch(FetchDescriptor<BodyweightEntry>())
        XCTAssertEqual(weights.first { $0.date == today }?.kg, 70, "the lifter's weigh-in is not overwritten")
        let intakeYesterday = try context.fetch(FetchDescriptor<IntakeEntry>()).filter { Calendar.current.isDate($0.date, inSameDayAs: yesterday) }
        XCTAssertEqual(intakeYesterday.map(\.name), ["Eggs"], "a day with food logged gets no demo food")
        XCTAssertEqual(settings.goal, .leanGain)
        XCTAssertEqual(settings.goalRatePercentPerWeek, 0.25)
    }
}
