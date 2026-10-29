import Foundation
import SwiftData

enum Seeder {
    /// Everything that runs at launch, in order: first-run seeding, repairs for older installs,
    /// then the built-in programs.
    static func prepare(context: ModelContext) {
        seedIfNeeded(context: context)
        migrate(context: context)
        addMissingLibraryExercises(context: context)
        gradeLibraryMuscles(context: context)
        ensurePrograms(context: context)
    }

    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<UserSettings>())) ?? 0
        guard count == 0 else { return }
        let settings = UserSettings()
        context.insert(settings)
        for spec in ExerciseLibrary.all {
            let exercise = Exercise(spec: spec)
            exercise.increment = ExerciseLibrary.increment(forKg: spec.increment, metric: settings.usesMetric)
            context.insert(exercise)
        }
        context.saveOrLog()
    }

    /// Inserts any library exercise the store does not have yet, so an install made before the
    /// library grew still gets the new ones. Matched by name: an exercise the lifter already
    /// created or renamed to a library name is left alone, custom settings and all.
    static func addMissingLibraryExercises(context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        // Installs from before `librarySpecName` existed: a library name still identifies the row.
        for exercise in exercises where exercise.librarySpecName == nil && ExerciseLibrary.spec(exercise.name) != nil {
            exercise.librarySpecName = exercise.name
        }
        let existing = Set(exercises.flatMap { [$0.name, $0.librarySpecName].compactMap { $0 } })
        let metric = (try? context.fetch(FetchDescriptor<UserSettings>()).first?.usesMetric) ?? true
        var added = false
        for spec in ExerciseLibrary.all where !existing.contains(spec.name) {
            let exercise = Exercise(spec: spec)
            exercise.increment = ExerciseLibrary.increment(forKg: spec.increment, metric: metric)
            context.insert(exercise)
            added = true
        }
        if added { context.saveOrLog() }
    }

    /// Gives library exercises seeded before muscles were graded their stabiliser tier. Only an
    /// exercise whose primary and secondary muscles still match the library's is touched, so one
    /// the lifter has regraded keeps their grading; a custom exercise is never touched. Safe to
    /// run on every launch: once the tiers are present there is nothing to add.
    static func gradeLibraryMuscles(context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        var changed = false
        for exercise in exercises {
            guard let spec = exercise.librarySpec else { continue }
            let mainTiers = { (muscles: [MuscleWeight]) in Set(muscles.filter { $0.weight >= 0.5 }) }
            guard mainTiers(exercise.muscles) == mainTiers(spec.muscles) else { continue }
            let listed = Set(exercise.muscles.map(\.muscle))
            let missing = spec.muscles.filter { $0.weight < 0.5 && !listed.contains($0.muscle) }
            guard !missing.isEmpty else { continue }
            exercise.muscles.append(contentsOf: missing)
            changed = true
        }
        if changed { context.saveOrLog() }
    }

    /// Repairs for installs created before exercises had ids and program days referred to them by id.
    /// Safe to run on every launch: it only touches rows that still need it.
    static func migrate(context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        // Rows that gained `id` through a lightweight migration may all carry the same default.
        var seen: Set<UUID> = []
        for exercise in exercises where !seen.insert(exercise.id).inserted {
            exercise.id = UUID()
        }
        let idsByName = Dictionary(exercises.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let days = (try? context.fetch(FetchDescriptor<ProgramDay>())) ?? []
        for day in days where day.exerciseIDs.isEmpty && !day.legacyExerciseNames.isEmpty {
            let ids = day.legacyExerciseNames.compactMap { idsByName[$0] }
            guard !ids.isEmpty else { continue }
            day.exerciseIDs = ids
            day.legacyExerciseNames = []
        }
        if context.hasChanges { context.saveOrLog() }
    }

    /// Seeds the built-in splits as editable programs once, and makes sure one is active.
    static func ensurePrograms(context: ModelContext) {
        var programs = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        if programs.isEmpty {
            let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
            for builtIn in BuiltInPrograms.all {
                let program = Program.make(from: builtIn, exercises: exercises)
                context.insert(program)
                programs.append(program)
            }
        }
        if let settings = try? context.fetch(FetchDescriptor<UserSettings>()).first {
            if settings.activeProgramID == nil, let legacy = settings.legacyTemplateName {
                settings.activeProgramID = programs.first { $0.name == legacy }?.id
            }
            settings.legacyTemplateName = nil
            if settings.activeProgram(in: programs)?.id != settings.activeProgramID {
                settings.activeProgramID = settings.activeProgram(in: programs)?.id
            }
        }
        context.saveOrLog()
    }

    /// Re-map each library exercise's rep range from one style to another. Only a range still on
    /// the library's default, or on the old style's, is touched: a range the lifter set (5–8 on
    /// a curl) is kept. The rest between sets follows when it was the range's default.
    static func applyRepStyle(from old: RepStyle, to new: RepStyle, context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            guard let spec = exercise.librarySpec else { continue }
            let current = (low: exercise.repRangeLow, high: exercise.repRangeHigh)
            let base = (low: spec.repRangeLow, high: spec.repRangeHigh)
            let before = old.range(forDefault: base.low, high: base.high)
            let after = new.range(forDefault: base.low, high: base.high)
            guard current == base || current == before else { continue }
            if exercise.restSeconds == RestRule.defaultSeconds(repRangeHigh: current.high) {
                exercise.restSeconds = RestRule.defaultSeconds(repRangeHigh: after.high)
            }
            exercise.repRangeLow = after.low
            exercise.repRangeHigh = after.high
        }
        context.saveOrLog()
    }

    /// Re-map each library exercise's increment to the plate step for the chosen unit. Only an
    /// increment still on the other unit's default step is touched: a step the lifter set
    /// themselves (1.25 kg on a curl) is kept.
    static func applyUnits(metric: Bool, context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            guard let spec = exercise.librarySpec else {
                // A custom or imported exercise has no library step to go by. One sitting on any of
                // the other unit's default steps moves to the same step in this unit; anything else
                // was chosen by the lifter and stays.
                for kg in [1.25, 2.5, 5.0, 10.0] where abs(exercise.increment - ExerciseLibrary.increment(forKg: kg, metric: !metric)) < 0.0001 {
                    exercise.increment = ExerciseLibrary.increment(forKg: kg, metric: metric)
                    break
                }
                continue
            }
            let oldDefault = ExerciseLibrary.increment(forKg: spec.increment, metric: !metric)
            let newDefault = ExerciseLibrary.increment(forKg: spec.increment, metric: metric)
            if abs(exercise.increment - oldDefault) < 0.0001 || abs(exercise.increment - newDefault) < 0.0001 {
                exercise.increment = newDefault
            }
        }
        context.saveOrLog()
    }

}
