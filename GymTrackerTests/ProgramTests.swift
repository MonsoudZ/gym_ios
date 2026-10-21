import XCTest
@testable import GymTracker

final class ProgramTests: XCTestCase {
    @MainActor
    private func program(days: [String]) -> Program {
        let program = Program(name: "T")
        for name in days { program.addDay(named: name) }
        return program
    }

    @MainActor
    func testNextDayRotatesAndWraps() {
        let program = program(days: ["Upper", "Lower"])
        XCTAssertEqual(PlanService.nextDay(in: program, completedSessions: [])?.name, "Upper")

        let upper = WorkoutSession(date: .now, templateDayName: "Upper")
        upper.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(in: program, completedSessions: [upper])?.name, "Lower")

        let lower = WorkoutSession(date: .now.addingTimeInterval(60), templateDayName: "Lower")
        lower.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(in: program, completedSessions: [upper, lower])?.name, "Upper")
    }

    @MainActor
    func testNextDayIsNilForEmptyProgram() {
        XCTAssertNil(PlanService.nextDay(in: Program(name: "Empty"), completedSessions: []))
    }

    @MainActor
    func testRenamedDayFallsBackToFirst() {
        let program = program(days: ["A", "B"])
        let old = WorkoutSession(date: .now, templateDayName: "Gone")
        old.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(in: program, completedSessions: [old])?.name, "A")
    }

    @MainActor
    func testRenamedDayStillRotatesWhenSessionRemembersItsID() {
        let program = program(days: ["A", "B"])
        let dayA = program.orderedDays[0]
        let session = WorkoutSession(date: .now, templateDayName: "A")
        session.programDayID = dayA.id
        session.isCompleted = true
        dayA.name = "Push"
        XCTAssertEqual(PlanService.nextDay(in: program, completedSessions: [session])?.name, "B")
    }

    @MainActor
    func testProgramFromBuiltInKeepsOrderAndLinksExercisesByID() {
        let exercises = ExerciseLibrary.all.map { Exercise(spec: $0) }
        let program = Program.make(from: BuiltInPrograms.upperLower, exercises: exercises)
        XCTAssertEqual(program.orderedDays.map(\.name), ["Upper A", "Lower A", "Upper B", "Lower B"])
        let upperA = program.orderedDays[0]
        XCTAssertEqual(upperA.exercises(from: exercises).map(\.name).first, "Barbell Bench Press")
        XCTAssertEqual(upperA.exerciseIDs.count, BuiltInPrograms.upperLower.days[0].exerciseNames.count)
        XCTAssertTrue(upperA.legacyExerciseNames.isEmpty)
        let day = program.addDay(named: "Arms")
        XCTAssertEqual(day.order, 4)
    }

    @MainActor
    func testUnknownBuiltInExerciseNameIsDropped() {
        let bench = Exercise(spec: ExerciseLibrary.spec("Barbell Bench Press")!)
        let program = Program.make(from: BuiltInPrograms.upperLower, exercises: [bench])
        XCTAssertEqual(program.orderedDays[0].exerciseIDs, [bench.id])
        XCTAssertTrue(program.orderedDays[1].exerciseIDs.isEmpty)
    }

    @MainActor
    func testRenamingAnExerciseLeavesProgramsIntact() {
        let exercises = ExerciseLibrary.all.map { Exercise(spec: $0) }
        let program = Program.make(from: BuiltInPrograms.pushPullLegs, exercises: exercises)
        let bench = exercises.first { $0.name == "Barbell Bench Press" }!
        bench.name = "Competition Bench"
        let push = program.orderedDays[0]
        XCTAssertEqual(push.exercises(from: exercises).first?.name, "Competition Bench")
        XCTAssertEqual(push.exercises(from: exercises).count, BuiltInPrograms.pushPullLegs.days[0].exerciseNames.count)
    }

    @MainActor
    func testCustomExerciseDefaultsToPoundStep() {
        let exercise = Exercise(name: "Landmine Press", metric: false)
        XCTAssertEqual(Units.lb(fromKg: exercise.increment), 5, accuracy: 0.0001)
        XCTAssertFalse(exercise.isFromLibrary)
        XCTAssertTrue(Exercise(spec: ExerciseLibrary.all[0]).isFromLibrary)
    }

    @MainActor
    func testEveryExerciseGetsItsOwnID() {
        let a = Exercise(name: "A", metric: true)
        let b = Exercise(name: "B", metric: true)
        XCTAssertNotEqual(a.id, b.id)
    }
}
