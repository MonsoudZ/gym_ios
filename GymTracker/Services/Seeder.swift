import Foundation
import SwiftData

enum Seeder {
    /// Everything that runs at launch, in order: first-run seeding, repairs for older installs,
    /// then the built-in programs.
    static func prepare(context: ModelContext) {
        seedIfNeeded(context: context)
        migrate(context: context)
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

    /// Re-map every library exercise's increment to the plate step for the chosen unit.
    static func applyUnits(metric: Bool, context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            guard let spec = ExerciseLibrary.spec(exercise.name) else { continue }
            exercise.increment = ExerciseLibrary.increment(forKg: spec.increment, metric: metric)
        }
        context.saveOrLog()
    }

    static func resetAll(context: ModelContext) {
        try? context.delete(model: SetEntry.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: ReadinessEntry.self)
        try? context.delete(model: AdjustmentEntry.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: BodyweightEntry.self)
        try? context.delete(model: IntakeEntry.self)
        try? context.delete(model: UserSettings.self)
        try? context.delete(model: FoodItem.self)
        try? context.delete(model: ProgramDay.self)
        try? context.delete(model: Program.self)
        context.saveOrLog()
        prepare(context: context)
    }
}
