import XCTest
@testable import GymTracker

final class ProgramTests: XCTestCase {
    @MainActor
    func testNextDayRotatesAndWraps() {
        let template = ProgramTemplate(name: "T", summary: "", days: [
            TemplateDay(name: "Upper", exerciseNames: []),
            TemplateDay(name: "Lower", exerciseNames: []),
        ])
        XCTAssertEqual(PlanService.nextDay(template: template, completedSessions: [])?.name, "Upper")

        let upper = WorkoutSession(date: .now, templateDayName: "Upper")
        upper.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(template: template, completedSessions: [upper])?.name, "Lower")

        let lower = WorkoutSession(date: .now.addingTimeInterval(60), templateDayName: "Lower")
        lower.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(template: template, completedSessions: [upper, lower])?.name, "Upper")
    }

    @MainActor
    func testNextDayIsNilForEmptyProgram() {
        XCTAssertNil(PlanService.nextDay(template: ProgramTemplate(name: "Empty", summary: "", days: []), completedSessions: []))
    }

    @MainActor
    func testRenamedDayFallsBackToFirst() {
        let template = ProgramTemplate(name: "T", summary: "", days: [TemplateDay(name: "A", exerciseNames: []), TemplateDay(name: "B", exerciseNames: [])])
        let old = WorkoutSession(date: .now, templateDayName: "Gone")
        old.isCompleted = true
        XCTAssertEqual(PlanService.nextDay(template: template, completedSessions: [old])?.name, "A")
    }

    @MainActor
    func testProgramFromTemplateKeepsOrderAndExercises() {
        let program = Program.make(from: ProgramTemplates.upperLower)
        XCTAssertEqual(program.orderedDays.map(\.name), ["Upper A", "Lower A", "Upper B", "Lower B"])
        XCTAssertEqual(program.asTemplate.days[0].exerciseNames.first, "Barbell Bench Press")
        let day = program.addDay(named: "Arms")
        XCTAssertEqual(day.order, 4)
    }

    @MainActor
    func testCustomExerciseDefaultsToPoundStep() {
        let exercise = Exercise(name: "Cable Fly", metric: false)
        XCTAssertEqual(Units.lb(fromKg: exercise.increment), 5, accuracy: 0.0001)
        XCTAssertFalse(exercise.isFromLibrary)
        XCTAssertTrue(Exercise(spec: ExerciseLibrary.all[0]).isFromLibrary)
    }
}
