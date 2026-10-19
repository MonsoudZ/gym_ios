import XCTest
import SwiftData
@testable import GymTracker

/// The snapshot the widgets read is pre-formatted by the app, so these pin the strings down:
/// the widget extension only lays them out.
final class WidgetBridgeTests: XCTestCase {
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

    /// Settings in kg, one program with one day of one lift that has a starting weight.
    @MainActor
    private func seedProgram(in context: ModelContext) -> (settings: UserSettings, day: ProgramDay, exercise: Exercise) {
        let settings = UserSettings()
        settings.usesMetric = true
        context.insert(settings)
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        bench.startingWeight = 40
        context.insert(bench)
        let program = Program(name: "Test")
        context.insert(program)
        let day = program.addDay(named: "Upper A")
        day.exerciseIDs = [bench.id]
        settings.activeProgramID = program.id
        context.saveOrLog()
        return (settings, day, bench)
    }

    @MainActor
    func testEmptyStoreGivesNoSnapshots() throws {
        let context = try makeContext()
        XCTAssertNil(WidgetBridge.liftSnapshot(context: context, now: .now))
        XCTAssertNil(WidgetBridge.nutritionSnapshot(context: context, now: .now))
    }

    @MainActor
    func testPlannedDayFormatsThePrescription() throws {
        let context = try makeContext()
        let (_, day, bench) = seedProgram(in: context)

        let lift = try XCTUnwrap(WidgetBridge.liftSnapshot(context: context, now: .now))
        XCTAssertEqual(lift.dayName, day.name)
        XCTAssertFalse(lift.inProgress)
        XCTAssertEqual(lift.lines.count, 1)
        XCTAssertEqual(lift.lines[0].name, bench.name)
        XCTAssertEqual(lift.lines[0].detail, "40 kg · \(bench.setCount) × \(bench.repRangeLow)–\(bench.repRangeHigh)")
        XCTAssertNil(lift.lines[0].badge, "a lift with no history has nothing to flag")
        XCTAssertEqual(lift.headline, lift.lines[0])
        XCTAssertFalse(lift.headlineReason?.isEmpty ?? true)
    }

    @MainActor
    func testLiftWithoutStartingWeightAsksForOne() throws {
        let context = try makeContext()
        let (_, _, bench) = seedProgram(in: context)
        bench.startingWeight = nil
        context.saveOrLog()

        let lift = try XCTUnwrap(WidgetBridge.liftSnapshot(context: context, now: .now))
        XCTAssertEqual(lift.lines[0].detail, "\(bench.setCount) × \(bench.repRangeLow)–\(bench.repRangeHigh) · choose a weight")
    }

    @MainActor
    func testInProgressWorkoutCountsSetsDone() throws {
        let context = try makeContext()
        let (_, day, bench) = seedProgram(in: context)
        let session = WorkoutSession(templateDayName: day.name)
        session.programDayID = day.id
        context.insert(session)
        for number in 0..<3 {
            let set = SetEntry(exerciseOrder: 0, setNumber: number, weight: 40, reps: number == 0 ? 8 : 0)
            if number == 0 { set.completedAt = .now }
            set.exercise = bench
            set.session = session
            context.insert(set)
        }
        context.saveOrLog()

        let lift = try XCTUnwrap(WidgetBridge.liftSnapshot(context: context, now: .now))
        XCTAssertTrue(lift.inProgress)
        XCTAssertEqual(lift.dayName, day.name)
        XCTAssertEqual(lift.lines[0].detail, "40 kg · 1/3 sets")
        XCTAssertNil(lift.lines[0].badge)
        XCTAssertEqual(lift.headline?.name, bench.name)
        XCTAssertEqual(lift.headlineReason, "Workout in progress. Tap to continue.")
    }

    @MainActor
    func testInProgressWorkoutWithEverySetDoneSaysFinish() throws {
        let context = try makeContext()
        let (_, day, bench) = seedProgram(in: context)
        let session = WorkoutSession(templateDayName: day.name)
        context.insert(session)
        let set = SetEntry(exerciseOrder: 0, setNumber: 0, weight: 40, reps: 8)
        set.completedAt = .now
        set.exercise = bench
        set.session = session
        context.insert(set)
        context.saveOrLog()

        let lift = try XCTUnwrap(WidgetBridge.liftSnapshot(context: context, now: .now))
        XCTAssertEqual(lift.lines[0].badge, "Done")
        XCTAssertNil(lift.headline)
        XCTAssertEqual(lift.headlineReason, "Every set logged. Tap Finish.")
    }

    @MainActor
    func testNutritionSnapshotSumsTodayOnly() throws {
        let context = try makeContext()
        let settings = UserSettings()
        context.insert(settings)
        let now = Date.now
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!
        context.insert(IntakeEntry(date: now, name: "Eggs", kcal: 300, protein: 24))
        context.insert(IntakeEntry(date: now, name: "Rice", kcal: 200, protein: 4))
        context.insert(IntakeEntry(date: yesterday, name: "Old", kcal: 900, protein: 60))
        context.saveOrLog()

        let nutrition = try XCTUnwrap(WidgetBridge.nutritionSnapshot(context: context, now: now))
        XCTAssertEqual(nutrition.eatenKcal, 500)
        XCTAssertEqual(nutrition.eatenProtein, 28)
        XCTAssertEqual(nutrition.dayStart, Calendar.current.startOfDay(for: now))
        XCTAssertGreaterThan(nutrition.targetKcal, 0)
        XCTAssertGreaterThan(nutrition.targetProtein, 0)
        XCTAssertTrue(nutrition.isProvisional, "no logged weight yet, so the target is the formula estimate")
    }

    @MainActor
    func testSnapshotRoundTripsThroughJSON() throws {
        let context = try makeContext()
        _ = seedProgram(in: context)
        context.insert(IntakeEntry(name: "Eggs", kcal: 300, protein: 24))
        context.saveOrLog()
        let now = Date.now
        let original = WidgetSnapshot(lift: WidgetBridge.liftSnapshot(context: context, now: now),
                                      nutrition: WidgetBridge.nutritionSnapshot(context: context, now: now),
                                      updatedAt: now)

        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(WidgetSnapshot.self, from: encoder.encode(original))
        XCTAssertEqual(decoded.lift, original.lift)
        XCTAssertEqual(decoded.nutrition?.eatenKcal, 300)
        XCTAssertEqual(decoded.nutrition?.targetKcal, original.nutrition?.targetKcal)
    }
}
