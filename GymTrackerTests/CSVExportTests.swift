import XCTest
import SwiftData
@testable import GymTracker

/// The export is a backup: the workouts file must come back through the app's own importer
/// with nothing lost, and bringing it back onto the same phone must add nothing.
final class CSVExportTests: XCTestCase {
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

    func testFieldsWithCommasQuotesAndLineBreaksAreQuoted() {
        XCTAssertEqual(CSVExport.line(["a", "b,c", "say \"hi\"", "two\nlines", ""]), "a,\"b,c\",\"say \"\"hi\"\"\",\"two\nlines\",")
        XCTAssertEqual(CSVExport.number(80), "80")
        XCTAssertEqual(CSVExport.number(82.5), "82.5")
        XCTAssertEqual(CSVExport.number(83.914), "83.914")
        XCTAssertEqual(CSVExport.number(-0.5), "-0.5")
    }

    @MainActor
    private func sampleSession(in context: ModelContext) throws -> (WorkoutSession, Exercise, Exercise) {
        Seeder.seedIfNeeded(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let bench = try XCTUnwrap(exercises.first { $0.name == "Barbell Bench Press" })
        let row = try XCTUnwrap(exercises.first { $0.name == "Barbell Row" })
        let session = WorkoutSession(date: Date(timeIntervalSince1970: 1_761_700_000.25), templateDayName: "Upper A")
        session.isCompleted = true
        session.notes = "Felt \"strong\", despite the drive"
        let specs: [(Exercise, Int, Int, Double, Int, Double?, Bool)] = [
            (bench, 0, 0, 60, 8, nil, true), (bench, 0, 1, 100, 8, 8, false), (bench, 0, 2, 100, 7, 9.5, false),
            (row, 1, 0, 80, 10, 8, false),
        ]
        context.insert(session)
        for (exercise, order, number, weight, reps, rpe, warmup) in specs {
            let set = SetEntry(exerciseOrder: order, setNumber: number, weight: weight, reps: reps, rpe: rpe, isWarmup: warmup)
            set.completedAt = session.date.addingTimeInterval(Double(60 * (order * 3 + number + 1)))
            set.exercise = exercise
            set.session = session
            context.insert(set)
        }
        try context.save()
        return (session, bench, row)
    }

    @MainActor
    func testWorkoutsRoundTripThroughTheImporter() throws {
        let context = try makeContext()
        let (session, bench, row) = try sampleSession(in: context)
        let text = CSVExport.workouts([session])
        XCTAssertTrue(text.hasPrefix("title,start_time,end_time,description,exercise_title"))

        let file = try WorkoutImportParser.parse(text, assumedUnit: .lb)
        XCTAssertEqual(file.source, .hevy)
        XCTAssertTrue(file.unitFromFile, "kilograms are in the header, so no unit question")
        XCTAssertEqual(file.workouts.count, 1)
        let workout = file.workouts[0]
        XCTAssertEqual(workout.name, "Upper A")
        XCTAssertEqual(workout.date.timeIntervalSince1970, session.date.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(workout.notes, session.notes)
        XCTAssertEqual(workout.sets.map(\.exerciseName), [bench.name, bench.name, bench.name, row.name])
        XCTAssertEqual(workout.sets.map(\.weightKg), [60, 100, 100, 80])
        XCTAssertEqual(workout.sets.map(\.reps), [8, 8, 7, 10])
        XCTAssertEqual(workout.sets.map(\.rpe), [nil, 8, 9.5, 8])
        XCTAssertEqual(workout.sets.map(\.isWarmup), [true, false, false, false])
        XCTAssertEqual(file.skippedRows, 0)
    }

    @MainActor
    func testBringingTheExportBackOntoTheSamePhoneAddsNothing() throws {
        let context = try makeContext()
        let (session, _, _) = try sampleSession(in: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        let file = try WorkoutImportParser.parse(CSVExport.workouts([session]), assumedUnit: .kg)
        let mapping = WorkoutImportService.defaultMapping(for: file.exerciseCounts.map(\.name), exercises: exercises)
        XCTAssertTrue(mapping.values.allSatisfy { if case .existing = $0 { true } else { false } }, "library names map straight back")

        let outcome = WorkoutImportService.apply(file, mapping: mapping, exercises: exercises, metric: true, context: context)
        XCTAssertEqual(outcome.sessionsAdded, 0)
        XCTAssertEqual(outcome.sessionsSkipped, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SetEntry>()), 4)
    }

    @MainActor
    func testOtherTablesHaveTheirColumnsAndOneRowPerEntry() throws {
        _ = try makeContext()
        let weigh = BodyweightEntry(date: Date(timeIntervalSince1970: 1_761_700_000), kg: 80, fromHealth: true)
        let bodyweight = CSVExport.bodyweight([weigh]).split(separator: "\n")
        XCTAssertEqual(bodyweight[0], "date,kg,lb,source")
        XCTAssertTrue(bodyweight[1].hasSuffix(",80,176.37,health"), String(bodyweight[1]))

        let meal = IntakeEntry(date: Date(timeIntervalSince1970: 1_761_700_000), name: "Eggs, scrambled", kcal: 300, protein: 20, fat: 22, grams: 150)
        let food = CSVExport.food([meal]).split(separator: "\n")
        XCTAssertEqual(food[0], "date,time,name,kcal,protein_g,carbs_g,fat_g,fibre_g,grams")
        XCTAssertTrue(food[1].hasSuffix(",\"Eggs, scrambled\",300,20,0,22,0,150"), String(food[1]))

        let entry = ReadinessEntry(date: .now, sleepHours: 7.5, soreness: [.chest: 4, .quads: 4])
        let readiness = CSVExport.readiness([entry]).split(separator: "\n")
        XCTAssertEqual(readiness[0], "date,sleep_hours,sleep_source,sore_muscles,hrv_ms,resting_heart_rate")
        XCTAssertTrue(readiness[1].hasSuffix(",7.5,typed,chest; quads,,"), String(readiness[1]))

        let adjustment = AdjustmentEntry(date: Date(timeIntervalSince1970: 1_761_700_000), kcal: -100, trendRatePercentPerWeek: -0.2,
                                         goalRatePercentPerWeek: -0.5, cumulativeKcalAfter: -100, note: nil)
        let adjustments = CSVExport.adjustments([adjustment]).split(separator: "\n")
        XCTAssertEqual(adjustments[1], "2025-10-29T01:06:40.000Z,-100,-0.2,-0.5,-100,")
    }
}
