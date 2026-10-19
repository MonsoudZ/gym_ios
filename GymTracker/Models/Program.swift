import Foundation
import SwiftData

/// A training program you own: an ordered list of days, each an ordered list of exercises.
/// The built-in splits are seeded as Programs so they can be edited like any other.
@Model
final class Program {
    var id: UUID
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \ProgramDay.program) var days: [ProgramDay] = []

    init(name: String) {
        id = UUID()
        self.name = name
        createdAt = .now
    }

    var orderedDays: [ProgramDay] { days.sorted { $0.order < $1.order } }

    @discardableResult
    func addDay(named name: String) -> ProgramDay {
        let day = ProgramDay(name: name, order: (days.map(\.order).max() ?? -1) + 1)
        day.program = self
        days.append(day)
        return day
    }

    func renumberDays() {
        for (index, day) in orderedDays.enumerated() { day.order = index }
    }

    /// Turns a built-in split into a program. Names are resolved against `exercises` here and
    /// nowhere else; a name with no matching exercise is dropped.
    static func make(from builtIn: BuiltInProgram, exercises: [Exercise]) -> Program {
        let idsByName = Dictionary(exercises.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        let program = Program(name: builtIn.name)
        for (index, day) in builtIn.days.enumerated() {
            let model = ProgramDay(name: day.name, order: index, exerciseIDs: day.exerciseNames.compactMap { idsByName[$0] })
            model.program = program
            program.days.append(model)
        }
        return program
    }
}

@Model
final class ProgramDay {
    var id: UUID
    var name: String
    var order: Int
    /// Exercises in order, by `Exercise.id`, so renaming an exercise leaves the day intact.
    var exerciseIDs: [UUID] = []
    /// Exercise names from installs that predate `exerciseIDs`. `Seeder.migrate` turns these
    /// into ids on launch; nothing else reads them.
    @Attribute(originalName: "exerciseNames") var legacyExerciseNames: [String] = []
    var program: Program?

    init(name: String, order: Int, exerciseIDs: [UUID] = []) {
        id = UUID()
        self.name = name
        self.order = order
        self.exerciseIDs = exerciseIDs
    }

    /// The day's exercises in order, skipping any id that no longer resolves.
    func exercises(from all: [Exercise]) -> [Exercise] {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return exerciseIDs.compactMap { byID[$0] }
    }
}
