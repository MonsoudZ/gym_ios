import XCTest
import SwiftData
@testable import GymTracker

final class WorkoutImportTests: XCTestCase {
    private let denver = TimeZone(identifier: "America/Denver")!

    private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = denver
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: CSV

    func testCSVHandlesQuotesDelimitersInsideQuotesCRLFAndBOM() {
        let text = "\u{FEFF}a,b,c\r\n1,\"x, y\",\"say \"\"hi\"\"\"\r\n2,\"multi\nline\",3\r\n"
        let table = CSVTable(text: text)
        XCTAssertEqual(table.header, ["a", "b", "c"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.value(table.rows[0], "B"), "x, y")
        XCTAssertEqual(table.value(table.rows[0], "c"), "say \"hi\"")
        XCTAssertEqual(table.value(table.rows[1], "b"), "multi\nline")
        XCTAssertNil(table.value(table.rows[1], "missing"))
    }

    func testCSVPicksSemicolonDelimiterAndReadsDecimalCommas() {
        let table = CSVTable(text: "Weight;Reps\n82,5;8\n")
        XCTAssertEqual(table.delimiter, ";")
        XCTAssertEqual(CSVTable.number(table.value(table.rows[0], "weight")), 82.5)
        XCTAssertNil(CSVTable.number("abc"))
        XCTAssertNil(CSVTable.number("Infinity"))
    }

    // MARK: Strong

    private let strongCurrent = """
    Date,Workout Name,Duration,Exercise Name,Set Order,Weight,Reps,Distance,Seconds,Notes,Workout Notes,RPE
    2025-06-30 18:05:00,Upper A,1h 2m,Bench Press (Barbell),W,95,8,0,0,,,
    2025-06-30 18:05:00,Upper A,1h 2m,Bench Press (Barbell),1,185,8,0,0,,,8
    2025-06-30 18:05:00,Upper A,1h 2m,Bench Press (Barbell),2,185,7,0,0,,,9
    2025-06-30 18:05:00,Upper A,1h 2m,Bench Press (Barbell),Rest Timer,0,0,0,120,,,
    2025-06-30 18:05:00,Upper A,1h 2m,Lat Pulldown (Cable),1,140,10,0,0,,,
    2025-06-30 18:05:00,Upper A,1h 2m,Plank,1,0,0,0,60,,,
    2025-07-02 17:40:00,Lower A,55m,Squat (Barbell),1,225,5,0,0,,Knee felt fine,8.5
    2025-07-02 17:40:00,Lower A,55m,Pull Up,1,0,8,0,0,,,
    """

    func testStrongCurrentExportGroupsSetsIntoWorkoutsAndConvertsPounds() throws {
        let file = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: denver)
        XCTAssertEqual(file.source, .strong)
        XCTAssertFalse(file.unitFromFile)
        XCTAssertEqual(file.workouts.count, 2)
        XCTAssertEqual(file.setCount, 6)
        XCTAssertEqual(file.skippedRows, 1, "the plank has no reps")

        let upper = file.workouts[0]
        XCTAssertEqual(upper.name, "Upper A")
        XCTAssertEqual(upper.date, at(2025, 6, 30, 18, 5))
        XCTAssertEqual(upper.exerciseNames, ["Bench Press (Barbell)", "Lat Pulldown (Cable)"])
        XCTAssertTrue(upper.sets[0].isWarmup)
        XCTAssertFalse(upper.sets[1].isWarmup)
        XCTAssertEqual(upper.sets[1].weightKg, Units.kg(fromLb: 185), accuracy: 0.001)
        XCTAssertEqual(upper.sets[1].reps, 8)
        XCTAssertEqual(upper.sets[1].rpe, 8)
        XCTAssertNil(upper.sets[3].rpe)

        let lower = file.workouts[1]
        XCTAssertEqual(lower.sets.last?.weightKg, 0, "a bodyweight pull-up keeps its reps")
        XCTAssertEqual(lower.sets.last?.reps, 8)
        XCTAssertEqual(file.exerciseCounts.first?.name, "Bench Press (Barbell)")
    }

    func testStrongAssumedUnitKilogramsIsKeptAsIs() throws {
        let file = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .kg, timeZone: denver)
        XCTAssertEqual(file.workouts[0].sets[1].weightKg, 185)
    }

    func testStrongOlderExportReadsUnitPerRowAndSemicolons() throws {
        let text = """
        Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;RPE;Distance;Distance Unit;Seconds;Notes;Workout Notes;Workout Duration
        2021-07-24 10:37:18;Push;Bench Press (Barbell);1;80;kg;8;;0;m;0;;;45m
        2021-07-24 10:37:18;Push;Bench Press (Barbell);2;180;lbs;6;;0;m;0;;;45m
        """
        let file = try WorkoutImportParser.parse(text, assumedUnit: .lb, timeZone: denver)
        XCTAssertTrue(file.unitFromFile)
        XCTAssertEqual(file.workouts.count, 1)
        XCTAssertEqual(file.workouts[0].sets[0].weightKg, 80)
        XCTAssertEqual(file.workouts[0].sets[1].weightKg, Units.kg(fromLb: 180), accuracy: 0.001)
    }

    // MARK: Hevy

    private let hevy = """
    "title","start_time","end_time","description","exercise_title","superset_id","exercise_notes","set_index","set_type","weight_lbs","reps","distance_miles","duration_seconds","rpe"
    "Push Day","30 Jun 2025, 19:56","30 Jun 2025, 20:50","","Bench Press (Barbell)","","","0","warmup","95","10","","",""
    "Push Day","30 Jun 2025, 19:56","30 Jun 2025, 20:50","","Bench Press (Barbell)","","","1","normal","185","8","","","8"
    "Push Day","30 Jun 2025, 19:56","30 Jun 2025, 20:50","","Bench Press (Barbell)","","","2","failure","185","6","","",""
    "Push Day","30 Jun 2025, 19:56","30 Jun 2025, 20:50","","Running","","","0","normal","","","1.5","600",""
    "Pull Day","2 Jul 2025, 18:10","2 Jul 2025, 19:00","","Lat Pulldown (Cable)","","","0","normal","140","10","","",""
    """

    func testHevyExportReadsUnitFromHeaderSetTypesAndDates() throws {
        let file = try WorkoutImportParser.parse(hevy, assumedUnit: .kg, timeZone: denver)
        XCTAssertEqual(file.source, .hevy)
        XCTAssertTrue(file.unitFromFile)
        XCTAssertEqual(file.workouts.count, 2)
        XCTAssertEqual(file.skippedRows, 1, "running has no reps")
        let push = file.workouts[0]
        XCTAssertEqual(push.name, "Push Day")
        XCTAssertEqual(push.date, at(2025, 6, 30, 19, 56))
        XCTAssertTrue(push.sets[0].isWarmup)
        XCTAssertFalse(push.sets[2].isWarmup, "a set to failure is a working set")
        XCTAssertEqual(push.sets[1].weightKg, Units.kg(fromLb: 185), accuracy: 0.001)
        XCTAssertEqual(push.sets[1].rpe, 8)
        XCTAssertEqual(file.workouts[1].date, at(2025, 7, 2, 18, 10))
    }

    func testHevyKilogramsAndISODates() throws {
        let text = """
        title,start_time,end_time,description,exercise_title,superset_id,exercise_notes,set_index,set_type,weight_kg,reps,distance_km,duration_seconds,rpe
        Legs,2025-07-04T16:00:00Z,2025-07-04T17:00:00Z,,Squat (Barbell),,,0,normal,100,5,,,
        """
        let file = try WorkoutImportParser.parse(text, assumedUnit: .lb, timeZone: denver)
        XCTAssertEqual(file.workouts[0].sets[0].weightKg, 100)
        XCTAssertEqual(file.workouts[0].date, Date(timeIntervalSince1970: 1_751_644_800))
    }

    func testUnknownFormatAndEmptyFileThrow() {
        XCTAssertThrowsError(try WorkoutImportParser.parse("name,value\nx,1\n", assumedUnit: .kg)) {
            XCTAssertEqual($0 as? WorkoutImportError, .unknownFormat)
        }
        let header = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps\n"
        XCTAssertThrowsError(try WorkoutImportParser.parse(header, assumedUnit: .kg)) {
            XCTAssertEqual($0 as? WorkoutImportError, .noWorkouts)
        }
    }

    // MARK: Matching

    func testCommonStrongAndHevyNamesLandOnTheLibrary() {
        let expected: [String: String] = [
            "Bench Press (Barbell)": "Barbell Bench Press",
            "Incline Bench Press (Dumbbell)": "Incline Dumbbell Press",
            "Squat (Barbell)": "Back Squat",
            "Deadlift (Barbell)": "Deadlift",
            "Romanian Deadlift (Barbell)": "Romanian Deadlift",
            "Lat Pulldown (Cable)": "Lat Pulldown",
            "Bent Over Row (Barbell)": "Barbell Row",
            "Seated Cable Row - V Grip (Cable)": "Seated Cable Row",
            "Bicep Curl (Dumbbell)": "Dumbbell Curl",
            "Triceps Pushdown (Cable - Straight Bar)": "Triceps Pushdown",
            "Lateral Raise (Dumbbell)": "Lateral Raise",
            "Overhead Press (Barbell)": "Overhead Press",
            "Shoulder Press (Dumbbell)": "Dumbbell Shoulder Press",
            "Lying Leg Curl (Machine)": "Leg Curl",
            "Leg Extension (Machine)": "Leg Extension",
            "Hip Thrust (Barbell)": "Hip Thrust",
            "Skullcrusher (Barbell)": "Skull Crusher",
            "Pull Up": "Pull-Up",
            "Chin Up (Assisted)": "Chin-Up",
            "Face Pull (Cable)": "Face Pull",
            "Standing Calf Raise (Machine)": "Standing Calf Raise",
            "Hanging Leg Raise": "Hanging Leg Raise",
            "RDL": "Romanian Deadlift",
            "Lat Pulldown - Wide Grip (Cable)": "Lat Pulldown",
            "Barbell Bench Press": "Barbell Bench Press",
        ]
        for (source, library) in expected {
            XCTAssertEqual(ExerciseMatcher.libraryName(for: source), library, source)
        }
    }

    func testEveryMatchTargetIsALibraryExercise() throws {
        let names = Set(ExerciseLibrary.all.map(\.name))
        for source in ["Bench Press (Barbell)", "Squat (Barbell)", "Hip Abduction (Machine)", "Calf Press on Leg Press"] {
            let hit = try XCTUnwrap(ExerciseMatcher.libraryName(for: source))
            XCTAssertTrue(names.contains(hit), "\(source) → \(hit) is not in the library")
        }
    }

    func testUnknownNamesAreNotGuessed() {
        XCTAssertNil(ExerciseMatcher.libraryName(for: "Zercher Squat"))
        XCTAssertNil(ExerciseMatcher.libraryName(for: "Running"))
        XCTAssertNil(ExerciseMatcher.libraryName(for: ""))
    }

    func testADifferentImplementIsNotGuessedOntoTheBarbellLift() {
        // Stripping the equipment word would land these on barbell or machine lifts and put
        // 0 kg bodyweight squats into Back Squat's history. They go orange for the lifter to pick.
        for name in ["Squat (Bodyweight)", "Squat (Dumbbell)", "Deadlift (Dumbbell)", "Deadlift (Band)",
                     "Hip Thrust (Bodyweight)", "Chest Press (Band)", "Pushdown (Cable - Rope)"] {
            XCTAssertNil(ExerciseMatcher.libraryName(for: name), name)
        }
        // The lift's own implement, plain grips, and how much load is added still strip.
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Chest Dip (Weighted)"), "Dip")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Push Up (Weighted)"), "Push-Up")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Back Extension (Weighted)"), "Back Extension")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Face Pull (Rope)"), "Face Pull")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Lat Pulldown - Wide Grip (Cable)"), "Lat Pulldown")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Back Squat (Barbell) - Low Bar"), "Back Squat")
        XCTAssertEqual(ExerciseMatcher.libraryName(for: "Goblet Squat (Kettlebell)"), "Goblet Squat")
    }

    // MARK: Applying to the store

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

    func testWorkoutNotesComeAlong() throws {
        let file = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: denver)
        XCTAssertNil(file.workouts[0].notes)
        XCTAssertEqual(file.workouts[1].notes, "Knee felt fine")
    }

    func testKeysDoNotDependOnTheTimeZoneTheFileIsParsedIn() throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let here = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: denver)
        let there = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: tokyo)
        XCTAssertEqual(here.workouts.map(\.key), there.workouts.map(\.key))
        XCTAssertNotEqual(here.workouts[0].date, there.workouts[0].date, "the dates themselves follow the zone")
    }

    @MainActor
    func testImportMapsToARenamedLibraryLift() throws {
        let context = try makeContext()
        Seeder.seedIfNeeded(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = try XCTUnwrap(exercises.first { $0.name == "Barbell Bench Press" })
        bench.name = "Comp Bench"
        let mapping = WorkoutImportService.defaultMapping(for: ["Bench Press (Barbell)"], exercises: exercises)
        XCTAssertEqual(mapping["Bench Press (Barbell)"], .existing(bench.id))
    }

    @MainActor
    func testImportWritesCompletedSessionsCreatesCustomExercisesAndIsIdempotent() throws {
        let context = try makeContext()
        Seeder.seedIfNeeded(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let file = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: denver)

        var mapping = WorkoutImportService.defaultMapping(for: file.exerciseCounts.map(\.name), exercises: exercises)
        let bench = try XCTUnwrap(exercises.first { $0.name == "Barbell Bench Press" })
        XCTAssertEqual(mapping["Bench Press (Barbell)"], .existing(bench.id))
        XCTAssertEqual(mapping["Pull Up"], .existing(try XCTUnwrap(exercises.first { $0.name == "Pull-Up" }).id))
        mapping["Lat Pulldown (Cable)"] = .skip
        mapping["Squat (Barbell)"] = .create

        let first = WorkoutImportService.apply(file, mapping: mapping, exercises: exercises, metric: false, context: context)
        XCTAssertEqual(first.sessionsAdded, 2)
        XCTAssertEqual(first.setsAdded, 5, "the skipped pulldown set is not written")
        XCTAssertEqual(first.exercisesCreated, ["Squat (Barbell)"])

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)]))
        XCTAssertEqual(sessions.count, 2)
        XCTAssertTrue(sessions.allSatisfy(\.isCompleted))
        XCTAssertEqual(sessions[0].templateDayName, "Upper A")
        XCTAssertEqual(sessions[0].importKey, file.workouts[0].key)
        let benchSets = sessions[0].sets(for: bench)
        XCTAssertEqual(benchSets.map(\.setNumber), [0, 1, 2])
        XCTAssertEqual(benchSets.map(\.isWarmup), [true, false, false])
        XCTAssertEqual(benchSets[1].weight, Units.kg(fromLb: 185), accuracy: 0.001)
        XCTAssertEqual(benchSets[1].completedAt, sessions[0].date)
        XCTAssertEqual(bench.sessionResults().count, 1, "the engine sees the imported session")

        let squat = try XCTUnwrap(try context.fetch(FetchDescriptor<Exercise>()).first { $0.name == "Squat (Barbell)" })
        XCTAssertFalse(squat.isFromLibrary)
        XCTAssertEqual(sessions[1].sets(for: squat).count, 1)

        let again = WorkoutImportService.apply(file, mapping: mapping, exercises: exercises, metric: false, context: context)
        XCTAssertEqual(again.sessionsAdded, 0)
        XCTAssertEqual(again.sessionsSkipped, 2)
        XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 2)
        XCTAssertEqual(WorkoutImportService.importedKeys(context: context).count, 2)
    }

    @MainActor
    func testCreateForANameThatAlreadyExistsReusesItInsteadOfOverwriting() throws {
        // Exercise.name is unique: inserting a second "Squat (Barbell)" would upsert over the
        // first with blank muscles, a new id, and break every program day that points at it.
        let context = try makeContext()
        let existing = Exercise(name: "Squat (Barbell)", metric: false)
        existing.muscles = [MuscleWeight(muscle: .quads, weight: 1)]
        context.insert(existing)
        try context.save()
        let file = try WorkoutImportParser.parse(strongCurrent, assumedUnit: .lb, timeZone: denver)
        var mapping = WorkoutImportService.defaultMapping(for: file.exerciseCounts.map(\.name), exercises: [existing])
        for name in mapping.keys where name != "Squat (Barbell)" { mapping[name] = .skip }
        mapping["Squat (Barbell)"] = .create

        let outcome = WorkoutImportService.apply(file, mapping: mapping, exercises: [existing], metric: false, context: context)
        XCTAssertTrue(outcome.exercisesCreated.isEmpty)
        let all = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all[0].id, existing.id)
        XCTAssertEqual(all[0].muscles.map(\.muscle), [.quads])
        XCTAssertEqual(existing.sessionResults().count, 1, "the squat sets landed on the existing exercise")
    }

    @MainActor
    func testDefaultMappingReusesACustomExerciseOfTheSameName() throws {
        let context = try makeContext()
        let custom = Exercise(name: "Zercher Squat", metric: true)
        context.insert(custom)
        let mapping = WorkoutImportService.defaultMapping(for: ["zercher squat", "Running"], exercises: [custom])
        XCTAssertEqual(mapping["zercher squat"], .existing(custom.id))
        XCTAssertEqual(mapping["Running"], .create)
    }
}
