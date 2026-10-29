import Foundation

/// Maps exercise names as Strong and Hevy write them ("Bench Press (Barbell)", "Lat Pulldown
/// (Cable)", "Bicep Curl (Dumbbell)") onto the library's names. Pure. A name with no confident
/// match returns nil and the import screen lets the lifter pick, rather than guessing wrong and
/// poisoning a lift's history.
nonisolated enum ExerciseMatcher {
    /// The library exercise `name` refers to, or nil.
    static func libraryName(for name: String) -> String? {
        let normalized = normalize(name)
        guard !normalized.isEmpty else { return nil }
        if let hit = aliases[normalized] { return hit }
        if let hit = byNormalizedLibraryName[normalized] { return hit }
        // Drop trailing equipment words one at a time: "lat pulldown cable wide grip" → "lat pulldown".
        // Dropping an implement is only safe when the library lift is done with it: "squat
        // bodyweight" must not land on Back Squat, a barbell lift, so that is a guess and the
        // lifter picks (DESIGN.md §4).
        var tokens = normalized.split(separator: " ").map(String.init)
        var droppedImplements: [String] = []
        while let last = tokens.last, equipmentWords.contains(last) || qualifierWords.contains(last) {
            tokens.removeLast()
            if implementWords.contains(last) { droppedImplements.append(last) }
            let shorter = tokens.joined(separator: " ")
            if let hit = aliases[shorter] ?? byNormalizedLibraryName[shorter] {
                return droppedImplements.allSatisfy { implements(for: hit).contains($0) } ? hit : nil
            }
        }
        return nil
    }

    /// The implements a library lift is known under: every word of its own name and of its
    /// aliases that names one. Back Squat → {barbell}; Goblet Squat → {dumbbell, kettlebell}.
    private static func implements(for libraryName: String) -> Set<String> {
        implementsByLibraryName[libraryName] ?? []
    }

    private static let implementsByLibraryName: [String: Set<String>] = {
        var result: [String: Set<String>] = [:]
        let names = aliases.map { ($0.key, $0.value) } + ExerciseLibrary.all.map { (normalize($0.name), $0.name) }
        for (key, target) in names {
            for word in key.split(separator: " ").map(String.init) where implementWords.contains(word) {
                result[target, default: []].insert(word)
            }
        }
        return result
    }()

    /// Lowercased words only, with the other apps' spellings folded onto the library's.
    static func normalize(_ name: String) -> String {
        var text = name.lowercased()
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        let words = text
            .replacingOccurrences(of: "[^a-z0-9 ]", with: " ", options: .regularExpression)
            .split(separator: " ")
            .map { tokenSynonyms[String($0)] ?? String($0) }
            .filter { !$0.isEmpty && !fillerWords.contains($0) }
        return words.joined(separator: " ")
    }

    // MARK: Tables

    private static let replacements: [(String, String)] = [
        ("-", " "), ("/", " "), ("skullcrusher", "skull crusher"), ("skull crushers", "skull crusher"),
        ("pull-up", "pull up"), ("chin-up", "chin up"), ("push-up", "push up"), ("ez-bar", "ez bar"),
        ("t-bar", "t bar"), ("rdl", "romanian deadlift"), ("hyperextension", "back extension"),
    ]

    private static let tokenSynonyms: [String: String] = [
        "bicep": "biceps", "tricep": "triceps", "dumbbells": "dumbbell", "barbells": "barbell", "kettlebells": "kettlebell",
        "pulldowns": "pulldown", "pushdowns": "pushdown", "rows": "row", "curls": "curl", "raises": "raise",
        "presses": "press", "squats": "squat", "lunges": "lunge", "extensions": "extension", "flyes": "fly", "flies": "fly",
        "shrugs": "shrug", "crunches": "crunch", "dips": "dip", "pullups": "pull up", "chinups": "chin up", "pushups": "push up",
        "legged": "leg", "db": "dumbbell", "bb": "barbell", "kb": "kettlebell",
    ]

    private static let fillerWords: Set<String> = ["the", "with", "and", "a", "exercise"]

    private static let equipmentWords: Set<String> = [
        "barbell", "dumbbell", "cable", "machine", "smith", "kettlebell", "band", "bands", "plates", "plate",
        "bar", "ez", "trap", "hex", "rope", "straight", "v", "assisted", "weighted", "bodyweight", "bench",
    ]

    /// Equipment words that change which lift it is, as opposed to attachments, grips and how
    /// much load is added ("weighted", "assisted" are the same movement).
    private static let implementWords: Set<String> = [
        "barbell", "dumbbell", "cable", "machine", "smith", "kettlebell", "band", "bands", "bodyweight", "rope",
    ]

    private static let qualifierWords: Set<String> = [
        "grip", "wide", "close", "narrow", "neutral", "underhand", "overhand", "seated", "standing", "lying",
        "single", "arm", "one", "two", "alternating", "horizontal", "vertical", "high", "low", "pulley",
    ]

    /// Normalized source name → library name. Keys are what `normalize` produces for the common
    /// Strong and Hevy names; trailing equipment words are also tried stripped, so "bench press
    /// barbell" and "bench press" both land here.
    private static let aliases: [String: String] = [
        // Chest
        "bench press barbell": "Barbell Bench Press", "bench press": "Barbell Bench Press", "flat bench press": "Barbell Bench Press",
        "bench press dumbbell": "Flat Dumbbell Press", "dumbbell bench press": "Flat Dumbbell Press", "flat dumbbell press": "Flat Dumbbell Press",
        "incline bench press barbell": "Incline Barbell Bench Press", "incline bench press": "Incline Barbell Bench Press",
        "incline bench press dumbbell": "Incline Dumbbell Press", "incline dumbbell press": "Incline Dumbbell Press",
        "bench press close grip barbell": "Close-Grip Bench Press", "close grip bench press": "Close-Grip Bench Press",
        "chest press machine": "Machine Chest Press", "machine chest press": "Machine Chest Press", "chest press": "Machine Chest Press",
        "bench press smith machine": "Smith Machine Bench Press", "smith machine bench press": "Smith Machine Bench Press",
        "chest dip": "Dip", "dip": "Dip", "triceps dip": "Dip", "chest dip assisted": "Dip",
        "push up": "Push-Up",
        "chest fly cable": "Cable Fly", "cable fly": "Cable Fly", "cable crossover": "Cable Fly", "cable chest fly": "Cable Fly",
        "chest fly machine": "Pec Deck", "pec deck": "Pec Deck", "pec deck machine": "Pec Deck", "butterfly": "Pec Deck", "machine fly": "Pec Deck",
        "chest fly dumbbell": "Dumbbell Fly", "dumbbell fly": "Dumbbell Fly", "chest fly": "Dumbbell Fly",
        // Back
        "pull up": "Pull-Up", "pull up assisted": "Pull-Up", "pull up weighted": "Pull-Up",
        "chin up": "Chin-Up", "chin up assisted": "Chin-Up", "chin up weighted": "Chin-Up",
        "bent over row barbell": "Barbell Row", "barbell row": "Barbell Row", "bent over row": "Barbell Row", "barbell bent over row": "Barbell Row",
        "pendlay row barbell": "Pendlay Row", "pendlay row": "Pendlay Row",
        "t bar row": "T-Bar Row", "landmine row": "T-Bar Row",
        "chest supported row": "Chest-Supported Row", "chest supported incline row dumbbell": "Chest-Supported Row",
        "chest supported row dumbbell": "Chest-Supported Row", "seal row": "Chest-Supported Row", "incline row dumbbell": "Chest-Supported Row",
        "seated row machine": "Machine Row", "machine row": "Machine Row", "row machine": "Machine Row", "iso lateral row": "Machine Row",
        "seated cable row": "Seated Cable Row", "seated row cable": "Seated Cable Row", "seated row": "Seated Cable Row",
        "cable row": "Seated Cable Row", "seated cable row v grip cable": "Seated Cable Row", "low row cable": "Seated Cable Row",
        "lat pulldown cable": "Lat Pulldown", "lat pulldown": "Lat Pulldown", "lat pulldown machine": "Lat Pulldown",
        "wide grip lat pulldown": "Lat Pulldown", "pulldown": "Lat Pulldown",
        "close grip lat pulldown": "Close-Grip Lat Pulldown", "lat pulldown close grip": "Close-Grip Lat Pulldown",
        "lat pulldown underhand": "Close-Grip Lat Pulldown", "neutral grip lat pulldown": "Close-Grip Lat Pulldown",
        "straight arm lat pulldown cable": "Straight-Arm Pulldown", "straight arm pulldown": "Straight-Arm Pulldown",
        "straight arm lat pulldown": "Straight-Arm Pulldown",
        "bent over row dumbbell": "Dumbbell Row", "dumbbell row": "Dumbbell Row", "single arm row dumbbell": "Dumbbell Row",
        "one arm dumbbell row": "Dumbbell Row", "dumbbell bent over row": "Dumbbell Row", "single arm dumbbell row": "Dumbbell Row",
        "face pull": "Face Pull", "face pull cable": "Face Pull", "face pull rope": "Face Pull", "face pull cable rope": "Face Pull",
        "rack pull": "Rack Pull", "rack pull barbell": "Rack Pull",
        "back extension": "Back Extension", "back extension machine": "Back Extension", "45 degree back extension": "Back Extension",
        "shrug barbell": "Barbell Shrug", "barbell shrug": "Barbell Shrug",
        "shrug dumbbell": "Dumbbell Shrug", "dumbbell shrug": "Dumbbell Shrug",
        // Shoulders
        "overhead press barbell": "Overhead Press", "overhead press": "Overhead Press", "military press": "Overhead Press",
        "strict military press barbell": "Overhead Press", "standing military press barbell": "Overhead Press",
        "shoulder press barbell": "Overhead Press", "barbell shoulder press": "Overhead Press", "strict press": "Overhead Press",
        "seated overhead press barbell": "Seated Barbell Press", "seated shoulder press barbell": "Seated Barbell Press",
        "seated barbell press": "Seated Barbell Press",
        "shoulder press dumbbell": "Dumbbell Shoulder Press", "overhead press dumbbell": "Dumbbell Shoulder Press",
        "seated overhead press dumbbell": "Dumbbell Shoulder Press", "dumbbell shoulder press": "Dumbbell Shoulder Press",
        "seated shoulder press dumbbell": "Dumbbell Shoulder Press",
        "arnold press dumbbell": "Arnold Press", "arnold press": "Arnold Press",
        "shoulder press machine": "Machine Shoulder Press", "shoulder press machine plates": "Machine Shoulder Press",
        "overhead press machine": "Machine Shoulder Press", "machine shoulder press": "Machine Shoulder Press",
        "lateral raise dumbbell": "Lateral Raise", "lateral raise": "Lateral Raise", "side lateral raise": "Lateral Raise",
        "dumbbell lateral raise": "Lateral Raise", "side raise": "Lateral Raise",
        "lateral raise cable": "Cable Lateral Raise", "cable lateral raise": "Cable Lateral Raise",
        "lateral raise machine": "Machine Lateral Raise", "machine lateral raise": "Machine Lateral Raise",
        "upright row barbell": "Upright Row", "upright row": "Upright Row", "upright row cable": "Upright Row", "upright row dumbbell": "Upright Row",
        "reverse fly machine": "Reverse Pec Deck", "rear delt reverse fly machine": "Reverse Pec Deck", "reverse pec deck": "Reverse Pec Deck",
        "rear delt fly machine": "Reverse Pec Deck",
        "rear delt reverse fly dumbbell": "Rear Delt Fly", "reverse fly dumbbell": "Rear Delt Fly", "rear delt fly": "Rear Delt Fly",
        "rear delt raise": "Rear Delt Fly", "reverse fly cable": "Rear Delt Fly", "reverse fly": "Rear Delt Fly", "bent over fly": "Rear Delt Fly",
        "rear delt fly dumbbell": "Rear Delt Fly",
        "front raise dumbbell": "Front Raise", "front raise": "Front Raise", "front raise cable": "Front Raise", "front raise barbell": "Front Raise",
        // Arms
        "biceps curl barbell": "Barbell Curl", "barbell curl": "Barbell Curl", "barbell biceps curl": "Barbell Curl",
        "biceps curl dumbbell": "Dumbbell Curl", "dumbbell curl": "Dumbbell Curl", "dumbbell biceps curl": "Dumbbell Curl",
        "incline curl dumbbell": "Incline Dumbbell Curl", "incline dumbbell curl": "Incline Dumbbell Curl",
        "hammer curl dumbbell": "Hammer Curl", "hammer curl": "Hammer Curl",
        "preacher curl barbell": "Preacher Curl", "preacher curl dumbbell": "Preacher Curl", "preacher curl machine": "Preacher Curl",
        "preacher curl": "Preacher Curl",
        "biceps curl cable": "Cable Curl", "cable curl": "Cable Curl", "cable biceps curl": "Cable Curl",
        "ez bar curl": "EZ-Bar Curl", "biceps curl ez bar": "EZ-Bar Curl", "ez bar biceps curl": "EZ-Bar Curl",
        "biceps curl machine": "Machine Curl", "machine curl": "Machine Curl", "machine biceps curl": "Machine Curl",
        "skull crusher barbell": "Skull Crusher", "skull crusher dumbbell": "Skull Crusher", "skull crusher": "Skull Crusher",
        "lying triceps extension": "Skull Crusher", "lying triceps extension barbell": "Skull Crusher",
        "triceps extension": "Overhead Triceps Extension", "overhead triceps extension": "Overhead Triceps Extension",
        "triceps extension dumbbell": "Overhead Triceps Extension", "triceps extension cable": "Overhead Triceps Extension",
        "overhead triceps extension dumbbell": "Overhead Triceps Extension", "overhead triceps extension cable": "Overhead Triceps Extension",
        "triceps pushdown cable straight bar": "Triceps Pushdown", "triceps pushdown": "Triceps Pushdown",
        "triceps pushdown cable": "Triceps Pushdown", "triceps pressdown": "Triceps Pushdown", "pushdown": "Triceps Pushdown",
        "triceps rope pushdown": "Rope Pushdown", "triceps pushdown cable rope": "Rope Pushdown", "rope pushdown": "Rope Pushdown",
        "triceps pushdown rope": "Rope Pushdown", "rope triceps pushdown": "Rope Pushdown",
        "triceps kickback dumbbell": "Dumbbell Kickback", "triceps kickback": "Dumbbell Kickback", "kickback": "Dumbbell Kickback",
        "dumbbell kickback": "Dumbbell Kickback",
        "wrist curl": "Wrist Curl", "seated wrist curl": "Wrist Curl", "wrist curl barbell": "Wrist Curl", "wrist curl dumbbell": "Wrist Curl",
        "reverse curl barbell": "Reverse Curl", "reverse curl": "Reverse Curl", "reverse curl dumbbell": "Reverse Curl",
        // Legs
        "squat barbell": "Back Squat", "squat": "Back Squat", "back squat": "Back Squat", "high bar squat": "Back Squat",
        "low bar squat": "Back Squat", "barbell squat": "Back Squat", "barbell back squat": "Back Squat",
        "front squat barbell": "Front Squat", "front squat": "Front Squat",
        "hack squat": "Hack Squat", "hack squat machine": "Hack Squat",
        "squat smith machine": "Smith Machine Squat", "smith machine squat": "Smith Machine Squat",
        "goblet squat": "Goblet Squat", "goblet squat dumbbell": "Goblet Squat", "goblet squat kettlebell": "Goblet Squat",
        "bulgarian split squat": "Bulgarian Split Squat", "split squat": "Bulgarian Split Squat", "bulgarian split squat dumbbell": "Bulgarian Split Squat",
        "walking lunge": "Walking Lunge", "lunge": "Walking Lunge", "lunge dumbbell": "Walking Lunge", "lunge barbell": "Walking Lunge",
        "walking lunge dumbbell": "Walking Lunge",
        "step up": "Step-Up", "step up dumbbell": "Step-Up",
        "sissy squat": "Sissy Squat",
        "leg press": "Leg Press", "leg press machine": "Leg Press", "leg press horizontal": "Leg Press", "seated leg press": "Leg Press",
        "leg extension machine": "Leg Extension", "leg extension": "Leg Extension",
        "lying leg curl machine": "Leg Curl", "leg curl": "Leg Curl", "lying leg curl": "Leg Curl", "leg curl machine": "Leg Curl",
        "seated leg curl machine": "Seated Leg Curl", "seated leg curl": "Seated Leg Curl",
        "deadlift barbell": "Deadlift", "deadlift": "Deadlift", "conventional deadlift": "Deadlift", "barbell deadlift": "Deadlift",
        "sumo deadlift barbell": "Sumo Deadlift", "sumo deadlift": "Sumo Deadlift",
        "trap bar deadlift": "Trap Bar Deadlift", "deadlift trap bar": "Trap Bar Deadlift", "hex bar deadlift": "Trap Bar Deadlift",
        "romanian deadlift barbell": "Romanian Deadlift", "romanian deadlift": "Romanian Deadlift",
        "romanian deadlift dumbbell": "Dumbbell Romanian Deadlift", "dumbbell romanian deadlift": "Dumbbell Romanian Deadlift",
        "stiff leg deadlift": "Stiff-Leg Deadlift", "stiff leg deadlift barbell": "Stiff-Leg Deadlift", "straight leg deadlift": "Stiff-Leg Deadlift",
        "good morning barbell": "Good Morning", "good morning": "Good Morning",
        "nordic hamstring curl": "Nordic Curl", "nordic curl": "Nordic Curl", "nordic hamstring": "Nordic Curl",
        "glute ham raise": "Glute-Ham Raise", "ghr": "Glute-Ham Raise",
        "cable pull through": "Cable Pull-Through", "pull through": "Cable Pull-Through", "pull through cable": "Cable Pull-Through",
        "glute bridge": "Glute Bridge", "glute bridge barbell": "Glute Bridge",
        "hip thrust barbell": "Hip Thrust", "hip thrust": "Hip Thrust", "barbell hip thrust": "Hip Thrust",
        "hip thrust machine": "Machine Hip Thrust", "machine hip thrust": "Machine Hip Thrust",
        "hip abduction machine": "Hip Abduction", "hip abduction": "Hip Abduction", "abductor machine": "Hip Abduction",
        "kettlebell swing": "Kettlebell Swing",
        "standing calf raise machine": "Standing Calf Raise", "standing calf raise": "Standing Calf Raise", "calf raise": "Standing Calf Raise",
        "calf raise standing": "Standing Calf Raise", "standing calf raise dumbbell": "Standing Calf Raise", "smith machine calf raise": "Standing Calf Raise",
        "seated calf raise machine": "Seated Calf Raise", "seated calf raise": "Seated Calf Raise", "calf raise seated": "Seated Calf Raise",
        "calf press on leg press": "Leg Press Calf Raise", "leg press calf raise": "Leg Press Calf Raise", "calf press leg press": "Leg Press Calf Raise",
        "calf press": "Leg Press Calf Raise", "calf raise on leg press": "Leg Press Calf Raise",
        "donkey calf raise": "Donkey Calf Raise",
        // Core
        "hanging leg raise": "Hanging Leg Raise", "leg raise": "Hanging Leg Raise", "hanging leg raise captains chair": "Hanging Leg Raise",
        "hanging knee raise": "Hanging Knee Raise", "knee raise": "Hanging Knee Raise", "knee raise captains chair": "Hanging Knee Raise",
        "ab wheel": "Ab Wheel Rollout", "ab wheel rollout": "Ab Wheel Rollout", "ab rollout": "Ab Wheel Rollout",
        "crunch machine": "Machine Crunch", "machine crunch": "Machine Crunch", "ab crunch machine": "Machine Crunch",
        "cable crunch": "Cable Crunch", "crunch cable": "Cable Crunch", "kneeling cable crunch": "Cable Crunch",
        "decline sit up": "Decline Sit-Up", "decline crunch": "Decline Sit-Up", "sit up": "Decline Sit-Up",
        "pallof press": "Pallof Press", "pallof press cable": "Pallof Press",
    ]

    private static let byNormalizedLibraryName: [String: String] =
        Dictionary(ExerciseLibrary.all.map { (normalize($0.name), $0.name) }, uniquingKeysWith: { first, _ in first })
}
