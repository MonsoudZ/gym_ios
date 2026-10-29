import Foundation
import SwiftData

/// Writes a parsed Strong or Hevy export into the store as completed sessions, so the Progress
/// tab, the progression engine and personal records see the old history as if it had been
/// logged here. Each imported session carries its file key, so importing the same export twice
/// adds nothing.
@MainActor
enum WorkoutImportService {
    /// Where a source exercise name's sets go.
    enum Target: Hashable {
        /// An exercise already in the store, by `Exercise.id`.
        case existing(UUID)
        /// A new custom exercise named after the source.
        case create
        case skip
    }

    struct Outcome: Equatable {
        var sessionsAdded = 0
        var setsAdded = 0
        /// Workouts already in the store from an earlier import of the same file.
        var sessionsSkipped = 0
        var exercisesCreated: [String] = []
    }

    /// Keys of sessions imported before, so the preview can say how many the file would add.
    static func importedKeys(context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.importKey != nil })
        return Set(((try? context.fetch(descriptor)) ?? []).compactMap(\.importKey))
    }

    /// Start time to the millisecond (what an ISO export keeps) plus the name.
    nonisolated static func sameWorkoutKey(date: Date, name: String) -> String {
        "\(Int((date.timeIntervalSince1970 * 1000).rounded()))|\(name)"
    }

    /// The library exercise (or an existing custom one of the same name) each source name maps
    /// to by default; names with no confident match are created as custom exercises.
    static func defaultMapping(for names: [String], exercises: [Exercise]) -> [String: Target] {
        let byName = Dictionary(exercises.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        let byLibrary = Dictionary(exercises.compactMap { e in e.librarySpecName.map { ($0, e) } }, uniquingKeysWith: { first, _ in first })
        let byNormalized = Dictionary(exercises.map { (ExerciseMatcher.normalize($0.name), $0) }, uniquingKeysWith: { first, _ in first })
        var mapping: [String: Target] = [:]
        for name in names {
            if let library = ExerciseMatcher.libraryName(for: name), let exercise = byLibrary[library] ?? byName[library] {
                mapping[name] = .existing(exercise.id)
            } else if let exercise = byName[name] ?? byNormalized[ExerciseMatcher.normalize(name)] {
                mapping[name] = .existing(exercise.id)
            } else {
                mapping[name] = .create
            }
        }
        return mapping
    }

    @discardableResult
    static func apply(_ file: WorkoutImport, mapping: [String: Target], exercises: [Exercise], metric: Bool,
                      context: ModelContext) -> Outcome {
        var outcome = Outcome()
        let done = importedKeys(context: context)
        // A workout that already exists here with the same start and name is the same workout:
        // the app's own export brought back onto the phone it came from must not double history.
        let existing = Set(((try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []).map { sameWorkoutKey(date: $0.date, name: $0.templateDayName) })
        var byID = Dictionary(exercises.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var created: [String: Exercise] = [:]

        func exercise(for name: String) -> Exercise? {
            switch mapping[name] ?? .skip {
            case .skip: return nil
            case .existing(let id): return byID[id]
            case .create:
                if let existing = created[name] { return existing }
                // Exercise.name is unique, so inserting a second one would overwrite the first
                // (muscles, rep range and a new id). Use what is there.
                if let existing = exercises.first(where: { $0.name == name }) { return existing }
                let exercise = Exercise(name: name, metric: metric)
                context.insert(exercise)
                created[name] = exercise
                byID[exercise.id] = exercise
                outcome.exercisesCreated.append(name)
                return exercise
            }
        }

        for workout in file.workouts {
            if done.contains(workout.key) || existing.contains(sameWorkoutKey(date: workout.date, name: workout.name)) {
                outcome.sessionsSkipped += 1
                continue
            }
            var order: [UUID: Int] = [:]
            var setNumbers: [UUID: Int] = [:]
            var sets: [SetEntry] = []
            for imported in workout.sets {
                guard let exercise = exercise(for: imported.exerciseName) else { continue }
                let exerciseOrder = order[exercise.id] ?? { let next = order.count; order[exercise.id] = next; return next }()
                let setNumber = setNumbers[exercise.id, default: 0]
                setNumbers[exercise.id] = setNumber + 1
                let set = SetEntry(exerciseOrder: exerciseOrder, setNumber: setNumber, weight: imported.weightKg,
                                   reps: imported.reps, rpe: imported.rpe, isWarmup: imported.isWarmup)
                set.completedAt = workout.date
                set.exercise = exercise
                sets.append(set)
            }
            guard !sets.isEmpty else { continue }
            let session = WorkoutSession(date: workout.date, templateDayName: workout.name)
            session.isCompleted = true
            session.importKey = workout.key
            session.notes = workout.notes
            context.insert(session)
            for set in sets {
                set.session = session
                context.insert(set)
                session.sets.append(set)
            }
            outcome.sessionsAdded += 1
            outcome.setsAdded += sets.count
        }
        context.saveOrLog()
        return outcome
    }
}
