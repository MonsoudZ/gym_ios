import Foundation
import SwiftData

/// A training program you own: an ordered list of days, each an ordered list of exercise names.
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

    /// Value-type view for the planning engine.
    var asTemplate: ProgramTemplate {
        ProgramTemplate(name: name, summary: "", days: orderedDays.map { TemplateDay(name: $0.name, exerciseNames: $0.exerciseNames) })
    }

    func addDay(named name: String) -> ProgramDay {
        let day = ProgramDay(name: name, order: (days.map(\.order).max() ?? -1) + 1)
        day.program = self
        days.append(day)
        return day
    }

    func renumberDays() {
        for (index, day) in orderedDays.enumerated() { day.order = index }
    }

    static func make(from template: ProgramTemplate) -> Program {
        let program = Program(name: template.name)
        for (index, day) in template.days.enumerated() {
            let model = ProgramDay(name: day.name, order: index, exerciseNames: day.exerciseNames)
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
    var exerciseNames: [String]
    var program: Program?

    init(name: String, order: Int, exerciseNames: [String] = []) {
        id = UUID()
        self.name = name
        self.order = order
        self.exerciseNames = exerciseNames
    }
}
