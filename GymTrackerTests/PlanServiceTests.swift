import XCTest
import SwiftData
@testable import GymTracker

/// PlanService and Seeder against an in-memory store, so relationships and fetches behave as in the app.
final class PlanServiceTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)
    /// Kept alive for the test's duration: a context whose container has been released traps.
    private var container: ModelContainer?

    @MainActor
    private func makeContext() throws -> ModelContext {
        let schema = Schema([
            Exercise.self, WorkoutSession.self, SetEntry.self,
            BodyweightEntry.self, IntakeEntry.self, UserSettings.self, FoodItem.self,
            Program.self, ProgramDay.self, ReadinessEntry.self,
        ])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        self.container = container
        return container.mainContext
    }

    override func tearDown() {
        container = nil
        super.tearDown()
    }

    /// Local time on a given day in October 2026 (the 19th is a Monday).
    private func october(_ day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    @MainActor
    private func completedSession(_ exercise: Exercise, on date: Date, sets: Int, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(date: date, templateDayName: "Upper A")
        session.isCompleted = true
        context.insert(session)
        for number in 0..<sets {
            let set = SetEntry(exerciseOrder: 0, setNumber: number, weight: 80, reps: 8, rpe: 8)
            set.exercise = exercise
            set.session = session
            context.insert(set)
        }
        return session
    }

    // MARK: Weekly volume

    @MainActor
    func testMondayLookupUsesAverageInsteadOfRollingWeek() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        // Last week: Monday and Thursday mornings, 6 hard chest sets each.
        let sessions = [
            completedSession(bench, on: october(12, hour: 7), sets: 6, in: context),
            completedSession(bench, on: october(15, hour: 7), sets: 6, in: context),
        ]
        context.saveOrLog()
        XCTAssertEqual(calendar.component(.weekday, from: october(19, hour: 8)), 2, "19 October 2026 is a Monday")

        // Read on the next Monday, an hour after last Monday's session time.
        let monday = october(19, hour: 8)
        let rolling = PlanService.weeklyVolume(completedSessions: sessions, asOf: monday)
        XCTAssertEqual(rolling[.chest], 6, "the rolling week has already dropped last Monday")
        XCTAssertEqual(VolumeTracker.band(rolling[.chest]!), .low)

        let average = PlanService.averageWeeklyVolume(completedSessions: sessions, asOf: monday)
        XCTAssertEqual(average[.chest]!, 12, accuracy: 0.25)
        XCTAssertGreaterThanOrEqual(average[.chest]!, VolumeTracker.minimumWeeklySets)
        XCTAssertEqual(VolumeTracker.band(average[.chest]!), .ok)
    }

    @MainActor
    func testAverageUsesTheFullWindowOnceHistoryFillsIt() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        var sessions = [completedSession(bench, on: october(1, hour: 7), sets: 6, in: context)]   // before the window
        for day in [6, 9, 12, 15] {
            sessions.append(completedSession(bench, on: october(day, hour: 7), sets: 6, in: context))
        }
        context.saveOrLog()
        let average = PlanService.averageWeeklyVolume(completedSessions: sessions, asOf: october(19, hour: 8))
        XCTAssertEqual(average[.chest]!, 12, accuracy: 0.0001)   // 24 sets over exactly two weeks
        XCTAssertEqual(average[.triceps]!, 6, accuracy: 0.0001)
    }

    @MainActor
    func testAverageWithNoHistoryIsEmpty() throws {
        XCTAssertTrue(PlanService.averageWeeklyVolume(completedSessions: [], asOf: .now).isEmpty)
    }

    @MainActor
    func testTodaysPlannedSetsCountTowardTheStallCheck() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)   // 3 sets: chest 1, triceps 0.5, front delt 0.5
        let pushdown = Exercise(spec: ExerciseLibrary.spec("Triceps Pushdown")!)   // 3 sets: triceps 1
        context.insert(bench)
        context.insert(pushdown)
        let planned = PlanService.plannedVolume(for: [bench, pushdown])
        XCTAssertEqual(planned[.chest], 3)
        XCTAssertEqual(planned[.triceps], 4.5)

        let sessions = [completedSession(bench, on: october(15, hour: 7), sets: 6, in: context)]
        context.saveOrLog()
        let volume = PlanService.volumeForStallCheck(dayExercises: [bench, pushdown], completedSessions: sessions, asOf: october(19, hour: 8))
        XCTAssertEqual(volume[.chest]!, 9, accuracy: 0.0001)      // 6 last week + 3 today
        XCTAssertEqual(volume[.triceps]!, 7.5, accuracy: 0.0001)  // 3 + 4.5
    }

    // MARK: Session results

    @MainActor
    func testSessionResultsFetchesOnlyCompletedSessionsOldestFirst() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        let squat = Exercise(spec: ExerciseLibrary.spec("Back Squat")!)
        context.insert(bench)
        context.insert(squat)
        _ = completedSession(bench, on: october(15, hour: 7), sets: 3, in: context)
        _ = completedSession(bench, on: october(12, hour: 7), sets: 2, in: context)
        _ = completedSession(squat, on: october(13, hour: 7), sets: 3, in: context)
        let open = WorkoutSession(date: october(18, hour: 7), templateDayName: "Upper A")
        context.insert(open)
        let unfinished = SetEntry(exerciseOrder: 0, setNumber: 0, weight: 80)
        unfinished.exercise = bench
        unfinished.session = open
        context.insert(unfinished)
        context.saveOrLog()

        let results = bench.sessionResults()
        XCTAssertEqual(results.map(\.date), [october(12, hour: 7), october(15, hour: 7)])
        XCTAssertEqual(results.map(\.sets.count), [2, 3])
        XCTAssertEqual(squat.sessionResults().count, 1)
    }

    @MainActor
    func testLoggedSetCountIgnoresSetsWithoutReps() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        let session = completedSession(bench, on: october(15, hour: 7), sets: 3, in: context)
        let blank = SetEntry(exerciseOrder: 0, setNumber: 3, weight: 80)
        blank.exercise = bench
        blank.session = session
        context.insert(blank)
        XCTAssertEqual(session.sets.count, 4)
        XCTAssertEqual(session.loggedSetCount, 3)
    }

    // MARK: Mid-workout changes

    @MainActor
    func testAddSetAppendsAtTheLastWorkingWeight() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 80, in: context)
        XCTAssertEqual(session.sets(for: bench).count, bench.setCount)

        let added = session.addSet(for: bench, in: context)
        XCTAssertEqual(added.setNumber, bench.setCount)
        XCTAssertEqual(added.weight, 80)
        XCTAssertFalse(added.isWarmup)
        XCTAssertEqual(session.sets(for: bench).last?.persistentModelID, added.persistentModelID)
    }

    @MainActor
    func testWarmupsGoFirstAndNeverCountAsVolume() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 100, in: context)
        let warmups = session.addWarmups(for: bench, in: context)
        XCTAssertEqual(warmups.map(\.weight), [50, 70, 90])

        let ordered = session.sets(for: bench)
        XCTAssertEqual(ordered.prefix(3).map(\.isWarmup), [true, true, true])
        XCTAssertEqual(ordered.dropFirst(3).map(\.setNumber), [3, 4, 5])

        session.isCompleted = true
        for set in ordered where !set.isWarmup { set.reps = 8 }
        context.saveOrLog()
        let volume = PlanService.weeklyVolume(completedSessions: [session], asOf: .now.addingTimeInterval(60))
        XCTAssertEqual(volume[.chest], 3)   // warm-ups excluded
        XCTAssertEqual(bench.sessionResults().last?.sets.filter { !$0.isWarmup }.count, 3)
    }

    @MainActor
    func testAddExerciseIsIgnoredWhenAlreadyInSession() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 80, in: context)
        session.addExercise(bench, weight: 90, in: context)
        XCTAssertEqual(session.sets(for: bench).count, bench.setCount)
        XCTAssertEqual(session.orderedExercises.count, 1)
    }

    // MARK: Migration

    @MainActor
    func testMigrateTurnsLegacyExerciseNamesIntoIDs() throws {
        let context = try makeContext()
        let row = Exercise(spec: ExerciseLibrary.spec("Barbell Row")!)
        let squat = Exercise(spec: ExerciseLibrary.spec("Back Squat")!)
        context.insert(row)
        context.insert(squat)
        let program = Program(name: "Old")
        context.insert(program)
        let day = program.addDay(named: "Day 1")
        day.legacyExerciseNames = ["Barbell Row", "Gone", "Back Squat"]
        context.insert(day)
        context.saveOrLog()

        Seeder.migrate(context: context)
        XCTAssertEqual(day.exerciseIDs, [row.id, squat.id])
        XCTAssertTrue(day.legacyExerciseNames.isEmpty)
    }

    @MainActor
    func testMigrateGivesDuplicateExerciseIDsFreshOnes() throws {
        let context = try makeContext()
        let shared = UUID()
        let a = Exercise(name: "A", metric: true)
        let b = Exercise(name: "B", metric: true)
        a.id = shared
        b.id = shared
        context.insert(a)
        context.insert(b)
        context.saveOrLog()

        Seeder.migrate(context: context)
        XCTAssertNotEqual(a.id, b.id)
    }

    @MainActor
    func testEnsureProgramsSeedsBuiltInsWithExerciseIDsAndReadsLegacyTemplateOnce() throws {
        let context = try makeContext()
        Seeder.seedIfNeeded(context: context)
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        settings.legacyTemplateName = BuiltInPrograms.pushPullLegs.name
        Seeder.ensurePrograms(context: context)

        let programs = try context.fetch(FetchDescriptor<Program>())
        XCTAssertEqual(Set(programs.map(\.name)), Set(BuiltInPrograms.all.map(\.name)))
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        for program in programs {
            for day in program.orderedDays {
                XCTAssertFalse(day.exerciseIDs.isEmpty, "\(program.name) / \(day.name)")
                XCTAssertEqual(day.exercises(from: exercises).count, day.exerciseIDs.count)
            }
        }
        XCTAssertEqual(settings.activeProgram(in: programs)?.name, BuiltInPrograms.pushPullLegs.name)
        XCTAssertNil(settings.legacyTemplateName)
    }
}
