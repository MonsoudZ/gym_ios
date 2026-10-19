import Foundation
import SwiftData

enum Seeder {
    static func seedIfNeeded(context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<UserSettings>())) ?? 0
        guard count == 0 else { return }
        context.insert(UserSettings())
        for spec in ExerciseLibrary.all {
            context.insert(Exercise(spec: spec))
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
        try? context.save()
        seedIfNeeded(context: context)
    }
}
