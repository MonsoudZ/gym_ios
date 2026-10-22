import XCTest
import SwiftData
@testable import GymTracker

/// The exercise library: every entry is well formed, the built-in splits only name real
/// exercises, and an older install picks up new entries without losing its own edits.
final class ExerciseLibraryTests: XCTestCase {
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

    func testNamesAreUniqueAndTrimmed() {
        let names = ExerciseLibrary.all.map(\.name)
        XCTAssertEqual(Set(names).count, names.count, "duplicate names would collide with the unique constraint")
        for name in names {
            XCTAssertEqual(name, name.trimmingCharacters(in: .whitespaces))
            XCTAssertFalse(name.isEmpty)
        }
    }

    func testEveryEntryIsWellFormed() {
        XCTAssertGreaterThanOrEqual(ExerciseLibrary.all.count, 90)
        for spec in ExerciseLibrary.all {
            XCTAssertTrue(spec.muscles.contains { $0.weight == 1 }, "\(spec.name) has no main muscle")
            XCTAssertEqual(Set(spec.muscles.map(\.muscle)).count, spec.muscles.count, "\(spec.name) lists a muscle twice")
            for mw in spec.muscles { XCTAssertTrue((0.25...1).contains(mw.weight), "\(spec.name): \(mw.muscle) weight \(mw.weight)") }
            XCTAssertGreaterThanOrEqual(spec.repRangeLow, 1, spec.name)
            XCTAssertGreaterThanOrEqual(spec.repRangeHigh, spec.repRangeLow + 1, "\(spec.name) needs a range to progress through")
            XCTAssertLessThanOrEqual(spec.repRangeHigh, 20, spec.name)
            XCTAssertGreaterThanOrEqual(spec.setCount, 1, spec.name)
            XCTAssertGreaterThan(spec.increment, 0, spec.name)
            XCTAssertGreaterThan(ExerciseLibrary.increment(forKg: spec.increment, metric: false), 0, spec.name)
        }
    }

    func testOriginalEntriesAreUnchanged() {
        // The built-in splits and several engine tests depend on these values. Stabilisers
        // (weight 0.25) were graded later and may be added; the primary and secondary tiers stay.
        func mainTiers(_ name: String) -> [MuscleWeight] { ExerciseLibrary.spec(name)!.muscles.filter { $0.weight >= 0.5 } }
        let bench = ExerciseLibrary.spec("Barbell Bench Press")!
        XCTAssertEqual(mainTiers(bench.name), [MuscleWeight(muscle: .chest, weight: 1), MuscleWeight(muscle: .triceps, weight: 0.5), MuscleWeight(muscle: .frontDelt, weight: 0.5)])
        XCTAssertEqual([bench.repRangeLow, bench.repRangeHigh, bench.setCount], [6, 8, 3])
        XCTAssertEqual(bench.increment, 2.5)
        let deadlift = ExerciseLibrary.spec("Deadlift")!
        XCTAssertEqual([deadlift.repRangeLow, deadlift.repRangeHigh, deadlift.setCount], [3, 5, 2])
        XCTAssertEqual(mainTiers("Deadlift"), [MuscleWeight(muscle: .hamstrings, weight: 1), MuscleWeight(muscle: .glutes, weight: 1), MuscleWeight(muscle: .lowerBack, weight: 1), MuscleWeight(muscle: .upperBack, weight: 0.5)])
        XCTAssertEqual(mainTiers("Triceps Pushdown"), [MuscleWeight(muscle: .triceps, weight: 1)])
        XCTAssertEqual(ExerciseLibrary.spec("Back Squat")!.muscles.max(by: { $0.weight < $1.weight })?.muscle, .quads, "stabilisers never change the main muscle")
    }

    @MainActor
    func testOlderInstallGainsStabiliserTierButKeepsItsOwnGrading() throws {
        let context = try makeContext()
        let settings = UserSettings()
        settings.hasCompletedOnboarding = true
        context.insert(settings)
        // Seeded before muscles were graded: primary and secondary only.
        let squat = Exercise(spec: ExerciseLibrary.spec("Back Squat")!)
        squat.muscles = [MuscleWeight(muscle: .quads, weight: 1), MuscleWeight(muscle: .glutes, weight: 1), MuscleWeight(muscle: .lowerBack, weight: 0.5)]
        context.insert(squat)
        // The lifter regraded this one: glutes dropped to secondary.
        let press = Exercise(spec: ExerciseLibrary.spec("Leg Press")!)
        press.muscles = [MuscleWeight(muscle: .quads, weight: 1), MuscleWeight(muscle: .hamstrings, weight: 0.5)]
        context.insert(press)
        // The lifter added their own stabiliser; the library's others still arrive.
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        bench.muscles = [MuscleWeight(muscle: .chest, weight: 1), MuscleWeight(muscle: .triceps, weight: 0.5), MuscleWeight(muscle: .frontDelt, weight: 0.5), MuscleWeight(muscle: .abs, weight: 0.25)]
        context.insert(bench)
        let custom = Exercise(name: "Sled Push", metric: true)
        custom.muscles = [MuscleWeight(muscle: .quads, weight: 1)]
        context.insert(custom)
        try context.save()

        Seeder.prepare(context: context)

        XCTAssertEqual(squat.muscles, ExerciseLibrary.spec("Back Squat")!.muscles, "an unedited exercise gets the library's grading")
        XCTAssertEqual(press.muscles, [MuscleWeight(muscle: .quads, weight: 1), MuscleWeight(muscle: .hamstrings, weight: 0.5)], "a regraded exercise is left alone")
        XCTAssertEqual(bench.muscles.map(\.muscle), [.chest, .triceps, .frontDelt, .abs, .upperBack])
        XCTAssertEqual(custom.muscles, [MuscleWeight(muscle: .quads, weight: 1)])
        let all = try context.fetch(FetchDescriptor<Exercise>())
        for exercise in all where exercise.isFromLibrary && ![squat.id, press.id, bench.id].contains(exercise.id) {
            XCTAssertEqual(exercise.muscles, ExerciseLibrary.spec(exercise.name)!.muscles, "\(exercise.name) seeded now carries the full grading")
        }

        // Running again changes nothing.
        let before = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.muscles) })
        Seeder.prepare(context: context)
        for exercise in try context.fetch(FetchDescriptor<Exercise>()) {
            XCTAssertEqual(exercise.muscles, before[exercise.id], exercise.name)
        }
    }

    func testBuiltInSplitsOnlyNameLibraryExercises() {
        for program in BuiltInPrograms.all {
            for day in program.days {
                for name in day.exerciseNames {
                    XCTAssertNotNil(ExerciseLibrary.spec(name), "\(program.name) / \(day.name) names unknown exercise \(name)")
                }
                XCTAssertEqual(day.specs.count, day.exerciseNames.count)
            }
        }
    }

    func testEveryMuscleHasAtLeastTwoMainExercises() {
        for muscle in Muscle.allCases {
            let count = ExerciseLibrary.all.filter { spec in spec.muscles.contains { $0.muscle == muscle && $0.weight == 1 } }.count
            XCTAssertGreaterThanOrEqual(count, 2, "\(muscle.displayName) has \(count) main exercise(s)")
        }
    }

    @MainActor
    func testFreshInstallSeedsWholeLibrary() throws {
        let context = try makeContext()
        Seeder.prepare(context: context)
        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, ExerciseLibrary.all.count)
        XCTAssertEqual(Set(exercises.map(\.name)), Set(ExerciseLibrary.all.map(\.name)))
    }

    @MainActor
    func testOlderInstallGainsNewLibraryExercisesAndKeepsItsOwn() throws {
        let context = try makeContext()
        // An install from when the library had one exercise, in pounds, with a customised increment.
        let settings = UserSettings()
        settings.usesMetric = false
        settings.hasCompletedOnboarding = true
        context.insert(settings)
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        bench.increment = Units.kg(fromLb: 10)
        bench.setCount = 5
        context.insert(bench)
        let custom = Exercise(name: "Cable Fly", metric: false)   // same name as a library entry
        custom.repRangeLow = 20; custom.repRangeHigh = 30
        context.insert(custom)
        try context.save()

        Seeder.prepare(context: context)

        let exercises = try context.fetch(FetchDescriptor<Exercise>())
        XCTAssertEqual(exercises.count, ExerciseLibrary.all.count)
        let benchAfter = exercises.first { $0.name == "Barbell Bench Press" }!
        XCTAssertEqual(benchAfter.id, bench.id)
        XCTAssertEqual(Units.lb(fromKg: benchAfter.increment), 10, accuracy: 0.0001, "the lifter's edit is kept")
        XCTAssertEqual(benchAfter.setCount, 5)
        let flyAfter = exercises.first { $0.name == "Cable Fly" }!
        XCTAssertEqual(flyAfter.id, custom.id)
        XCTAssertEqual(flyAfter.repRangeHigh, 30, "a custom exercise sharing a library name is not replaced")
        let pullUp = exercises.first { $0.name == "Pull-Up" }!
        XCTAssertEqual(Units.lb(fromKg: pullUp.increment), 5, accuracy: 0.0001, "new entries use the install's unit")

        // Running again is a no-op.
        Seeder.prepare(context: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Exercise>()), ExerciseLibrary.all.count)
    }

    @MainActor
    func testPickerGroupsByMainMuscleInDeclarationOrderWithOtherLast() {
        var exercises = ExerciseLibrary.all.map { Exercise(spec: $0) }
        let custom = Exercise(name: "Mystery Machine", metric: true)
        exercises.append(custom)
        let groups = ExerciseGroup.grouping(exercises)
        XCTAssertEqual(groups.first?.title, "Chest")
        XCTAssertEqual(groups.last?.title, "Other")
        XCTAssertEqual(groups.last?.exercises.map(\.name), ["Mystery Machine"])
        XCTAssertEqual(groups.map(\.exercises.count).reduce(0, +), exercises.count)
        let titles = groups.dropLast().map(\.title)
        let order = Muscle.allCases.map(\.displayName).filter(titles.contains)
        XCTAssertEqual(titles, order)
        XCTAssertTrue(groups.first { $0.title == "Triceps" }!.exercises.contains { $0.name == "Close-Grip Bench Press" })
    }
}
