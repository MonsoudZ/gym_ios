import Foundation

nonisolated struct ExerciseSpec: Hashable, Sendable {
    var name: String
    var muscles: [MuscleWeight]
    var repRangeLow: Int
    var repRangeHigh: Int
    var setCount: Int
    var increment: Double
}

/// One day of a built-in split, by library exercise name. Only the seeding path reads these;
/// once seeded, a `Program` refers to its exercises by id.
nonisolated struct BuiltInDay: Hashable, Sendable {
    var name: String
    var exerciseNames: [String]

    var specs: [ExerciseSpec] { exerciseNames.compactMap(ExerciseLibrary.spec) }
}

nonisolated struct BuiltInProgram: Hashable, Sendable {
    var name: String
    var days: [BuiltInDay]
}

nonisolated enum ExerciseLibrary {
    private static func m(_ muscle: Muscle, _ weight: Double = 1) -> MuscleWeight { MuscleWeight(muscle: muscle, weight: weight) }
    private static func ex(_ name: String, _ muscles: [MuscleWeight], _ low: Int, _ high: Int, sets: Int = 3, inc: Double) -> ExerciseSpec {
        ExerciseSpec(name: name, muscles: muscles, repRangeLow: low, repRangeHigh: high, setCount: sets, increment: inc)
    }

    /// Grouped by the muscle each exercise mainly trains. Rep ranges follow DESIGN.md §2.1:
    /// 3–6 for heavy barbell strength work, 6–12 for compound hypertrophy work, 12–20 for
    /// isolation. Increments are in kg: 2.5 for upper-body barbells, 5 for lower-body barbells,
    /// 2 for dumbbells (1 for the small ones), 2.5 for cable stacks and most machines, 5 or 10
    /// for the big leg machines. Bodyweight lifts (pull-ups, dips) use the added-weight step.
    /// The first 21 are the originals the built-in splits are made from; keep them unchanged.
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

        // Chest
        ex("Incline Barbell Bench Press", [m(.chest), m(.frontDelt, 0.5), m(.triceps, 0.5)], 6, 10, inc: 2.5),
        ex("Close-Grip Bench Press", [m(.triceps), m(.chest, 0.5), m(.frontDelt, 0.5)], 6, 10, inc: 2.5),
        ex("Flat Dumbbell Press", [m(.chest), m(.triceps, 0.5), m(.frontDelt, 0.5)], 8, 12, inc: 2),
        ex("Machine Chest Press", [m(.chest), m(.triceps, 0.5), m(.frontDelt, 0.5)], 8, 12, inc: 5),
        ex("Smith Machine Bench Press", [m(.chest), m(.triceps, 0.5), m(.frontDelt, 0.5)], 6, 10, inc: 2.5),
        ex("Dip", [m(.chest), m(.triceps), m(.frontDelt, 0.5)], 6, 12, inc: 2.5),
        ex("Push-Up", [m(.chest), m(.triceps, 0.5), m(.frontDelt, 0.5)], 10, 20, inc: 2.5),
        ex("Cable Fly", [m(.chest)], 12, 20, inc: 2.5),
        ex("Pec Deck", [m(.chest)], 12, 20, inc: 2.5),
        ex("Dumbbell Fly", [m(.chest)], 12, 15, inc: 2),

        // Back
        ex("Pull-Up", [m(.lats), m(.upperBack, 0.5), m(.biceps, 0.5)], 5, 10, inc: 2.5),
        ex("Chin-Up", [m(.lats), m(.biceps), m(.upperBack, 0.5)], 5, 10, inc: 2.5),
        ex("Pendlay Row", [m(.upperBack), m(.lats), m(.rearDelt, 0.5), m(.biceps, 0.5)], 5, 8, inc: 2.5),
        ex("T-Bar Row", [m(.upperBack), m(.lats), m(.biceps, 0.5)], 8, 12, inc: 5),
        ex("Chest-Supported Row", [m(.upperBack), m(.lats, 0.5), m(.rearDelt, 0.5), m(.biceps, 0.5)], 8, 12, inc: 2),
        ex("Machine Row", [m(.upperBack), m(.lats, 0.5), m(.biceps, 0.5)], 10, 12, inc: 5),
        ex("Close-Grip Lat Pulldown", [m(.lats), m(.biceps, 0.5), m(.upperBack, 0.5)], 8, 12, inc: 2.5),
        ex("Straight-Arm Pulldown", [m(.lats)], 12, 15, inc: 2.5),
        ex("Rack Pull", [m(.upperBack), m(.lowerBack), m(.glutes, 0.5), m(.hamstrings, 0.5)], 3, 6, sets: 2, inc: 5),
        ex("Back Extension", [m(.lowerBack), m(.glutes, 0.5), m(.hamstrings, 0.5)], 10, 15, inc: 2.5),
        ex("Barbell Shrug", [m(.upperBack)], 10, 15, inc: 5),
        ex("Dumbbell Shrug", [m(.upperBack)], 12, 15, inc: 2),

        // Shoulders
        ex("Seated Barbell Press", [m(.frontDelt), m(.sideDelt, 0.5), m(.triceps, 0.5)], 6, 10, inc: 2.5),
        ex("Arnold Press", [m(.frontDelt), m(.sideDelt, 0.5), m(.triceps, 0.5)], 8, 12, inc: 2),
        ex("Machine Shoulder Press", [m(.frontDelt), m(.sideDelt, 0.5), m(.triceps, 0.5)], 8, 12, inc: 5),
        ex("Cable Lateral Raise", [m(.sideDelt)], 12, 20, inc: 1),
        ex("Machine Lateral Raise", [m(.sideDelt)], 12, 20, inc: 2.5),
        ex("Upright Row", [m(.sideDelt), m(.upperBack, 0.5), m(.biceps, 0.5)], 10, 15, inc: 2.5),
        ex("Reverse Pec Deck", [m(.rearDelt), m(.upperBack, 0.5)], 12, 20, inc: 2.5),
        ex("Rear Delt Fly", [m(.rearDelt), m(.upperBack, 0.5)], 12, 20, inc: 1),
        ex("Front Raise", [m(.frontDelt)], 12, 15, inc: 1),

        // Arms
        ex("Dumbbell Curl", [m(.biceps)], 8, 12, inc: 1),
        ex("Incline Dumbbell Curl", [m(.biceps)], 10, 15, inc: 1),
        ex("Hammer Curl", [m(.biceps), m(.forearms, 0.5)], 8, 12, inc: 1),
        ex("Preacher Curl", [m(.biceps)], 8, 12, inc: 1.25),
        ex("Cable Curl", [m(.biceps)], 10, 15, inc: 2.5),
        ex("EZ-Bar Curl", [m(.biceps)], 8, 12, inc: 1.25),
        ex("Machine Curl", [m(.biceps)], 10, 15, inc: 2.5),
        ex("Skull Crusher", [m(.triceps)], 8, 12, inc: 1.25),
        ex("Overhead Triceps Extension", [m(.triceps)], 10, 15, inc: 2.5),
        ex("Rope Pushdown", [m(.triceps)], 12, 15, inc: 2.5),
        ex("Dumbbell Kickback", [m(.triceps)], 12, 20, inc: 1),
        ex("Wrist Curl", [m(.forearms)], 12, 20, inc: 1.25),
        ex("Reverse Curl", [m(.forearms), m(.biceps, 0.5)], 10, 15, inc: 1.25),

        // Quads
        ex("Front Squat", [m(.quads), m(.glutes, 0.5), m(.upperBack, 0.5)], 4, 6, inc: 5),
        ex("Hack Squat", [m(.quads), m(.glutes, 0.5)], 8, 12, inc: 5),
        ex("Smith Machine Squat", [m(.quads), m(.glutes), m(.lowerBack, 0.5)], 6, 10, inc: 5),
        ex("Goblet Squat", [m(.quads), m(.glutes, 0.5)], 10, 15, inc: 2),
        ex("Bulgarian Split Squat", [m(.quads), m(.glutes)], 8, 12, inc: 2),
        ex("Walking Lunge", [m(.quads), m(.glutes)], 10, 15, inc: 2),
        ex("Step-Up", [m(.quads), m(.glutes)], 10, 15, inc: 2),
        ex("Sissy Squat", [m(.quads)], 10, 15, inc: 2.5),

        // Hamstrings and glutes
        ex("Sumo Deadlift", [m(.glutes), m(.hamstrings), m(.quads, 0.5), m(.lowerBack, 0.5), m(.upperBack, 0.5)], 3, 5, sets: 2, inc: 5),
        ex("Trap Bar Deadlift", [m(.quads), m(.glutes), m(.hamstrings), m(.lowerBack, 0.5), m(.upperBack, 0.5)], 4, 6, sets: 2, inc: 5),
        ex("Stiff-Leg Deadlift", [m(.hamstrings), m(.glutes), m(.lowerBack, 0.5)], 6, 10, inc: 5),
        ex("Dumbbell Romanian Deadlift", [m(.hamstrings), m(.glutes), m(.lowerBack, 0.5)], 8, 12, inc: 2),
        ex("Good Morning", [m(.hamstrings), m(.lowerBack), m(.glutes, 0.5)], 8, 12, inc: 2.5),
        ex("Seated Leg Curl", [m(.hamstrings)], 10, 15, inc: 2.5),
        ex("Nordic Curl", [m(.hamstrings)], 5, 10, inc: 2.5),
        ex("Glute-Ham Raise", [m(.hamstrings), m(.glutes, 0.5)], 6, 12, inc: 2.5),
        ex("Cable Pull-Through", [m(.glutes), m(.hamstrings, 0.5)], 12, 15, inc: 2.5),
        ex("Glute Bridge", [m(.glutes), m(.hamstrings, 0.5)], 10, 15, inc: 5),
        ex("Machine Hip Thrust", [m(.glutes), m(.hamstrings, 0.5)], 8, 12, inc: 5),
        ex("Hip Abduction", [m(.glutes)], 12, 20, inc: 2.5),
        ex("Kettlebell Swing", [m(.glutes), m(.hamstrings), m(.lowerBack, 0.5)], 10, 20, inc: 2),

        // Calves
        ex("Seated Calf Raise", [m(.calves)], 12, 20, sets: 4, inc: 2.5),
        ex("Leg Press Calf Raise", [m(.calves)], 10, 15, sets: 4, inc: 10),
        ex("Donkey Calf Raise", [m(.calves)], 10, 15, sets: 4, inc: 5),

        // Abs
        ex("Hanging Leg Raise", [m(.abs)], 8, 15, inc: 2.5),
        ex("Hanging Knee Raise", [m(.abs)], 10, 20, inc: 2.5),
        ex("Ab Wheel Rollout", [m(.abs)], 8, 15, inc: 2.5),
        ex("Machine Crunch", [m(.abs)], 10, 15, inc: 2.5),
        ex("Decline Sit-Up", [m(.abs)], 10, 20, inc: 2.5),
        ex("Pallof Press", [m(.abs)], 10, 15, inc: 2.5),
    ]

    static func spec(_ name: String) -> ExerciseSpec? {
        all.first { $0.name == name }
    }

    /// Library increments are written in kg. In pounds the equivalent plate step is used instead,
    /// stored as its exact kg value so prescriptions round to whole pounds.
    static func increment(forKg kg: Double, metric: Bool) -> Double {
        guard !metric else { return kg }
        let lb: Double
        switch kg {
        case ..<1.5: lb = 2.5      // 1 or 1.25 kg: small dumbbells, cable stacks
        case ..<3: lb = 5          // 2 or 2.5 kg: upper-body barbell, dumbbells
        case ..<7.5: lb = 10       // 5 kg: lower-body barbell
        default: lb = 20           // 10 kg: leg press
        }
        return Units.kg(fromLb: lb)
    }
}

/// The splits seeded as editable programs on first launch.
nonisolated enum BuiltInPrograms {
    static let upperLower = BuiltInProgram(
        name: "Upper / Lower",
        days: [
            BuiltInDay(name: "Upper A", exerciseNames: ["Barbell Bench Press", "Barbell Row", "Overhead Press", "Lat Pulldown", "Barbell Curl", "Triceps Pushdown"]),
            BuiltInDay(name: "Lower A", exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Standing Calf Raise"]),
            BuiltInDay(name: "Upper B", exerciseNames: ["Incline Dumbbell Press", "Seated Cable Row", "Dumbbell Shoulder Press", "Lat Pulldown", "Lateral Raise", "Face Pull", "Barbell Curl"]),
            BuiltInDay(name: "Lower B", exerciseNames: ["Deadlift", "Leg Press", "Hip Thrust", "Leg Extension", "Leg Curl", "Standing Calf Raise"]),
        ])

    static let pushPullLegs = BuiltInProgram(
        name: "Push / Pull / Legs",
        days: [
            BuiltInDay(name: "Push", exerciseNames: ["Barbell Bench Press", "Overhead Press", "Incline Dumbbell Press", "Lateral Raise", "Triceps Pushdown"]),
            BuiltInDay(name: "Pull", exerciseNames: ["Barbell Row", "Lat Pulldown", "Seated Cable Row", "Face Pull", "Barbell Curl"]),
            BuiltInDay(name: "Legs", exerciseNames: ["Back Squat", "Romanian Deadlift", "Leg Press", "Leg Curl", "Standing Calf Raise", "Cable Crunch"]),
        ])

    static let fullBody = BuiltInProgram(
        name: "Full Body",
        days: [
            BuiltInDay(name: "Full Body A", exerciseNames: ["Back Squat", "Barbell Bench Press", "Barbell Row", "Lateral Raise", "Barbell Curl"]),
            BuiltInDay(name: "Full Body B", exerciseNames: ["Deadlift", "Overhead Press", "Lat Pulldown", "Leg Press", "Triceps Pushdown"]),
            BuiltInDay(name: "Full Body C", exerciseNames: ["Hip Thrust", "Incline Dumbbell Press", "Seated Cable Row", "Leg Curl", "Face Pull"]),
        ])

    static let all: [BuiltInProgram] = [upperLower, pushPullLegs, fullBody]
}
