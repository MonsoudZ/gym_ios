import Foundation
import SwiftData

/// One food inside a saved meal, at the amount it was logged. Macros are for that amount, not
/// per 100 g: a meal is "the usual breakfast", and its portions do not change.
nonisolated struct MealComponent: Codable, Hashable, Sendable {
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double
    var grams: Double?

    func scaled(by factor: Double) -> MealComponent {
        MealComponent(name: name, kcal: kcal * factor, protein: protein * factor, carbs: carbs * factor,
                      fat: fat * factor, fibre: fibre * factor, grams: grams.map { $0 * factor })
    }
}

/// Foods logged together, saved so the whole meal is one tap (DESIGN.md §4).
@Model
final class SavedMeal {
    var name: String
    var components: [MealComponent]
    var lastUsed: Date
    var useCount: Int

    init(name: String, components: [MealComponent]) {
        self.name = name
        self.components = components
        lastUsed = .now
        useCount = 0
    }

    /// A meal made from foods already logged, in the order given.
    convenience init(name: String, from entries: [IntakeEntry]) {
        self.init(name: name, components: entries.map {
            MealComponent(name: $0.name, kcal: $0.kcal, protein: $0.protein, carbs: $0.carbs,
                          fat: $0.fat, fibre: $0.fibre, grams: $0.grams)
        })
    }

    func totals(scale: Double = 1) -> Macros {
        var sum = Macros.zero
        for component in components {
            sum.kcal += component.kcal * scale; sum.protein += component.protein * scale
            sum.carbs += component.carbs * scale; sum.fat += component.fat * scale
            sum.fibre += component.fibre * scale
        }
        return sum
    }

    /// Logs every food at `scale` times its saved amount, as separate entries so each stays
    /// editable and shows in the day's list. The caller saves.
    @discardableResult
    func log(scale: Double = 1, at date: Date = .now, in context: ModelContext) -> [IntakeEntry] {
        let entries = components.map { component -> IntakeEntry in
            let c = component.scaled(by: scale)
            return IntakeEntry(date: date, name: c.name, kcal: c.kcal, protein: c.protein, carbs: c.carbs,
                               fat: c.fat, fibre: c.fibre, grams: c.grams)
        }
        entries.forEach(context.insert)
        lastUsed = date
        useCount += 1
        return entries
    }
}
