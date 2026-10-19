import Foundation

nonisolated struct ExerciseSpec: Hashable, Sendable {
    var name: String
    var muscles: [MuscleWeight]
    var repRangeLow: Int
    var repRangeHigh: Int
    var setCount: Int
    var increment: Double
}

nonisolated struct TemplateDay: Hashable, Sendable {
    var name: String
    var exerciseNames: [String]

    var exercises: [ExerciseSpec] { exerciseNames.compactMap(ExerciseLibrary.spec) }
}

nonisolated struct ProgramTemplate: Hashable, Sendable {
    var name: String
    var summary: String
    var days: [TemplateDay]
}

nonisolated enum ExerciseLibrary {
    private static func m(_ muscle: Muscle, _ weight: Double = 1) -> MuscleWeight { MuscleWeight(muscle: muscle, weight: weight) }
    private static func ex(_ name: String, _ muscles: [MuscleWeight], _ low: Int, _ high: Int, sets: Int = 3, inc: Double) -> ExerciseSpec {
        ExerciseSpec(name: name, muscles: muscles, repRangeLow: low, repRangeHigh: high, setCount: sets, increment: inc)
    }

    static let all: [ExerciseSpec] = [
        ex("Barbell Bench Press", [m(.chest), m(.triceps, 0.5), m(.frontDelt, 0.5)], 6, 8, inc: 2.5),
        ex("Incline Dumbbell Press", [m(.chest), m(.frontDelt, 0.5), m(.triceps, 0.5)], 8, 12, inc: 2),
        ex("Overhead Press", [m(.frontDelt), m(.sideDelt, 0.5), m(.triceps, 0.5)], 6, 10, inc: 2.5),
        ex("Dumbbell Shoulder Press", [m(.frontDelt), m(.sideDelt, 0.5), m(.triceps, 0.5)], 8, 12, inc: 2),
        ex("Lateral Raise", [m(.sideDelt)], 12, 20, inc: 1),
        ex("Triceps Pushdown", [m(.triceps)], 10, 15, inc: 2.5),
        ex("Barbell Row", [m(.upperBack), m(.lats), m(.biceps, 0.5), m(.rearDelt, 0.5)], 6, 10, inc: 2.5),
        ex("Lat Pulldown", [m(.lats), m(.upperBack, 0.5), m(.biceps, 0.5)], 8, 12, inc: 2.5),
        ex("Seated Cable Row", [m(.upperBack), m(.lats, 0.5), m(.biceps, 0.5)], 10, 12, inc: 2.5),
        ex("Dumbbell Row", [m(.lats), m(.upperBack), m(.biceps, 0.5)], 8, 12, inc: 2),
        ex("Face Pull", [m(.rearDelt), m(.upperBack, 0.5)], 12, 20, inc: 1),
        ex("Barbell Curl", [m(.biceps)], 8, 12, inc: 1.25),
        ex("Back Squat", [m(.quads), m(.glutes), m(.lowerBack, 0.5)], 5, 8, inc: 5),
        ex("Romanian Deadlift", [m(.hamstrings), m(.glutes), m(.lowerBack, 0.5)], 6, 10, inc: 5),
        ex("Deadlift", [m(.hamstrings), m(.glutes), m(.lowerBack), m(.upperBack, 0.5)], 3, 5, sets: 2, inc: 5),
        ex("Leg Press", [m(.quads), m(.glutes, 0.5)], 10, 15, inc: 10),
        ex("Leg Curl", [m(.hamstrings)], 10, 15, inc: 2.5),
        ex("Leg Extension", [m(.quads)], 12, 15, inc: 2.5),
        ex("Hip Thrust", [m(.glutes), m(.hamstrings, 0.5)], 8, 12, inc: 5),
        ex("Standing Calf Raise", [m(.calves)], 10, 15, sets: 4, inc: 5),
        ex("Cable Crunch", [m(.abs)], 10, 15, inc: 2.5),
    ]

    static func spec(_ name: String) -> ExerciseSpec? {
        all.first { $0.name == name }
    }
}

nonisolated enum ProgramTemplates {
    static let upperLower = ProgramTemplate(
        name: "Upper / Lower",
        summary: "4 days. Every muscle twice a week.",
        days: [
            TemplateDay(name: "Upper A", exerciseNames: ["Barbell Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown", "Barbell Curl", "Triceps Pushdown"]),
            TemplateDay(name: "Lower A", exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Standing Calf Raise"]),
            TemplateDay(name: "Upper B", exerciseNames: ["Incline Dumbbell Press", "Seated Cable Row", "Dumbbell Shoulder Press", "Lat Pulldown", "Lateral Raise", "Face Pull", "Barbell Curl"]),
            TemplateDay(name: "Lower B", exerciseNames: ["Deadlift", "Leg Press", "Hip Thrust", "Leg Extension", "Leg Curl", "Standing Calf Raise"]),
        ])

    static let pushPullLegs = ProgramTemplate(
        name: "Push / Pull / Legs",
        summary: "6 days, or 3 days rotating.",
        days: [
            TemplateDay(name: "Push", exerciseNames: ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Triceps Pushdown"]),
            TemplateDay(name: "Pull", exerciseNames: ["Barbell Row", "Lat Pulldown", "Seated Cable Row", "Face Pull", "Barbell Curl"]),
            TemplateDay(name: "Legs", exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Standing Calf Raise", "Cable Crunch"]),
        ])

    static let fullBody = ProgramTemplate(
        name: "Full Body",
        summary: "3 days. Compound-led.",
        days: [
            TemplateDay(name: "Full Body A", exerciseNames: ["Back Squat", "Barbell Bench Press", "Barbell Row", "Lateral Raise", "Barbell Curl"]),
            TemplateDay(name: "Full Body B", exerciseNames: ["Deadlift", "Overhead Press", "Lat Pulldown", "Leg Press", "Triceps Pushdown"]),
            TemplateDay(name: "Full Body C", exerciseNames: ["Hip Thrust", "Incline Dumbbell Press", "Seated Cable Row", "Leg Curl", "Face Pull"]),
        ])

    static let all: [ProgramTemplate] = [upperLower, pushPullLegs, fullBody]

    static func named(_ name: String) -> ProgramTemplate {
        all.first { $0.name == name } ?? upperLower
    }
}
