import Foundation
import SwiftData

enum Seeder {
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
        try? context.save()
    }

    /// Re-map every library exercise's increment to the plate step for the chosen unit.
    static func applyUnits(metric: Bool, context: ModelContext) {
        let exercises = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        for exercise in exercises {
            guard let spec = ExerciseLibrary.spec(exercise.name) else { continue }
            exercise.increment = ExerciseLibrary.increment(forKg: spec.increment, metric: metric)
        }
        try? context.save()
    }

    static func resetAll(context: ModelContext) {
        try? context.delete(model: SetEntry.self)
        try? context.delete(model: WorkoutSession.self)
        try? context.delete(model: Exercise.self)
        try? context.delete(model: BodyweightEntry.self)
        try? context.delete(model: IntakeEntry.self)
        try? context.delete(model: UserSettings.self)
        try? context.delete(model: FoodItem.self)
        try? context.save()
        seedIfNeeded(context: context)
    }
}
