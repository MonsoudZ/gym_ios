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
    func testTodaysPlannedSetsDoNotInflateTheStallCheck() throws {
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
        XCTAssertEqual(volume[.chest]!, 6, accuracy: 0.0001, "last week's 6 sets; today's planned 3 are the same day coming round again")
        XCTAssertEqual(volume[.triceps]!, 3, accuracy: 0.0001)
    }

    @MainActor
    func testAStalledLiftWhoseMuscleHasNoRecentSetsIsOfferedASetNotADeload() throws {
        // Three Held sessions, then nothing for the muscle in the two-week window (a break):
        // volume is zero, which is under the minimum, so step 1 of the stall check applies.
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)   // 6–8
        context.insert(bench)
        for day in [1, 4, 7] {
            let session = completedSession(bench, on: october(day, hour: 7), sets: 3, in: context)
            for set in session.sets { set.reps = 7 }   // in range, not at the top: Held
        }
        context.saveOrLog()
        let p = PlanService.prescription(for: bench, readiness: nil, weeklyVolume: [:], metric: true)
        XCTAssertEqual(p.stallStreak, 3)
        XCTAssertEqual(p.stallAction, .addSet)
        XCTAssertEqual(p.weight, 80)
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

    @MainActor
    func testSwapTakesTheOriginalsPlaceAndLeavesTheProgramAlone() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        let row = Exercise(spec: ExerciseLibrary.spec("Barbell Row")!)
        let dumbbell = Exercise(spec: ExerciseLibrary.spec("Incline Dumbbell Press")!)
        [bench, row, dumbbell].forEach(context.insert)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 80, in: context)
        session.addExercise(row, weight: 60, in: context)

        session.swap(bench, for: dumbbell, weight: 30, in: context)
        context.saveOrLog()

        XCTAssertEqual(session.orderedExercises.map(\.name), [dumbbell.name, row.name])
        XCTAssertTrue(session.sets(for: bench).isEmpty)
        XCTAssertEqual(session.sets(for: dumbbell).count, bench.setCount)
        XCTAssertEqual(session.sets(for: dumbbell).map(\.weight), Array(repeating: 30, count: bench.setCount))
    }

    @MainActor
    func testSwapKeepsSetsAlreadyLoggedAndDoesNotInterleave() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        let dumbbell = Exercise(spec: ExerciseLibrary.spec("Incline Dumbbell Press")!)
        [bench, dumbbell].forEach(context.insert)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 80, in: context)
        session.sets(for: bench).first?.reps = 8   // one set done before the bench was taken

        session.swap(bench, for: dumbbell, weight: 30, in: context)
        context.saveOrLog()

        XCTAssertEqual(session.sets(for: bench).count, 1)
        XCTAssertEqual(session.sets(for: dumbbell).count, bench.setCount - 1)
        XCTAssertEqual(session.orderedExercises.map(\.name), [bench.name, dumbbell.name])
        XCTAssertTrue(session.sets(for: dumbbell).allSatisfy { $0.setNumber > 0 })
    }

    @MainActor
    func testSkipDropsUnloggedSetsOnlyAndLeavesNoVerdict() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        let row = Exercise(spec: ExerciseLibrary.spec("Barbell Row")!)
        [bench, row].forEach(context.insert)
        let session = WorkoutSession(templateDayName: "Upper A")
        context.insert(session)
        session.addExercise(bench, weight: 80, in: context)
        session.addExercise(row, weight: 60, in: context)
        session.sets(for: row).first?.reps = 8

        XCTAssertFalse(session.skip(bench, in: context))
        XCTAssertTrue(session.skip(row, in: context))
        session.isCompleted = true
        context.saveOrLog()

        XCTAssertEqual(session.orderedExercises.map(\.name), [row.name])
        XCTAssertEqual(session.sets(for: row).count, 1)
        XCTAssertTrue(bench.sessionResults().isEmpty, "a skipped lift has no history, so no miss")
    }

    @MainActor
    func testEditingASetChangesTheVerdictAndHistoryRowsNameTheirSession() throws {
        let context = try makeContext()
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        context.insert(bench)
        let session = completedSession(bench, on: october(12, hour: 7), sets: 3, in: context)
        let mistyped = session.sets(for: bench).first!
        mistyped.reps = 1   // a mistyped rep count
        context.saveOrLog()

        let before = bench.sessionResults()
        XCTAssertEqual(before.last?.sessionID, session.id)
        let typo = ProgressionEngine.verdict(for: before.last!.sets, config: bench.config)
        XCTAssertEqual(typo, .failed)

        mistyped.reps = 8
        context.saveOrLog()
        let fixed = ProgressionEngine.verdict(for: bench.sessionResults().last!.sets, config: bench.config)
        XCTAssertNotEqual(typo, fixed)
    }

    // MARK: Weekly adjustment history

    @MainActor
    func testApplyingAnAdjustmentRecordsItWithTheRunningTotal() throws {
        let context = try makeContext()
        let settings = UserSettings()
        settings.goalRatePercentPerWeek = -0.5
        context.insert(settings)
        let first = settings.applyAdjustment(Adjustment(kcal: -100, note: nil), trendRatePercentPerWeek: -0.1, in: context, on: october(5, hour: 9))
        let second = settings.applyAdjustment(Adjustment(kcal: 100, note: "note"), trendRatePercentPerWeek: -0.9, in: context, on: october(12, hour: 9))
        context.saveOrLog()

        XCTAssertEqual(settings.cumulativeAdjustmentKcal, 0)
        XCTAssertEqual(settings.lastAdjustmentDate, october(12, hour: 9))
        XCTAssertEqual(first.cumulativeKcalAfter, -100)
        XCTAssertEqual(second.cumulativeKcalAfter, 0)
        XCTAssertEqual(second.goalRatePercentPerWeek, -0.5)
        XCTAssertEqual(second.note, "note")
        let stored = try context.fetch(FetchDescriptor<AdjustmentEntry>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(stored.map(\.kcal), [-100, 100])
    }

    @MainActor
    func testFreshSettingsNeedOnboardingAndSeededOnesDoToo() throws {
        let context = try makeContext()
        Seeder.prepare(context: context)
        let settings = try XCTUnwrap(context.fetch(FetchDescriptor<UserSettings>()).first)
        XCTAssertFalse(settings.hasCompletedOnboarding, "a seeded install asks the first-run questions once")
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

/// The volume lines on the Today tab (DESIGN.md §2.5).
final class VolumeNotesTests: XCTestCase {
    @MainActor
    private func planned(_ name: String, stallStreak: Int = 0) -> PlannedExercise {
        let exercise = Exercise(spec: ExerciseLibrary.spec(name)!)
        var prescription = Prescription(weight: 80, repRangeLow: 6, repRangeHigh: 8, setCount: 3, reason: "")
        prescription.stallStreak = stallStreak
        return PlannedExercise(exercise: exercise, prescription: prescription)
    }

    @MainActor
    func testLowVolumeSuggestsASetHighAndStallingSuggestsDroppingTwo() {
        let plan = [planned("Barbell Bench Press"), planned("Lateral Raise", stallStreak: 2), planned("Barbell Curl")]
        let volume: [Muscle: Double] = [.chest: 6, .sideDelt: 24, .biceps: 14]
        let notes = PlanService.volumeNotes(plan: plan, volume: volume)
        XCTAssertEqual(notes.map(\.muscle), [.chest, .sideDelt], "biceps are in range and say nothing")
        XCTAssertEqual(notes[0].band, .low)
        XCTAssertTrue(notes[0].text.contains("Barbell Bench Press"))
        XCTAssertEqual(notes[1].band, .high)
        XCTAssertTrue(notes[1].text.contains("Drop two sets"))
    }

    @MainActor
    func testHighVolumeWithoutAStallIsOnlyAnObservation() {
        let notes = PlanService.volumeNotes(plan: [planned("Lateral Raise")], volume: [.sideDelt: 22])
        XCTAssertEqual(notes.count, 1)
        XCTAssertFalse(notes[0].text.contains("Drop"))
    }

    @MainActor
    func testUntrainedMuscleCountsAsZero() {
        let notes = PlanService.volumeNotes(plan: [planned("Barbell Curl")], volume: [:])
        XCTAssertEqual(notes.first?.sets, 0)
        XCTAssertEqual(notes.first?.band, .low)
    }
}
