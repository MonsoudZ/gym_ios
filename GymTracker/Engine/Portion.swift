import Foundation

/// How an amount of food is measured. Mass always works; volume needs the food's grams per
/// cup; a piece needs its piece weight; a serving needs the label's serving size.
nonisolated enum PortionUnit: String, CaseIterable, Codable, Sendable, Identifiable {
    case gram, ounce, cup, tablespoon, teaspoon, millilitre, fluidOunce, serving, piece

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gram: "g"
        case .ounce: "oz"
        case .cup: "cup"
        case .tablespoon: "tbsp"
        case .teaspoon: "tsp"
        case .millilitre: "ml"
        case .fluidOunce: "fl oz"
        case .serving: "serving"
        case .piece: "piece"
        }
    }

    static let gramsPerOunce = 28.3495
    static let millilitresPerCup = 240.0
    static let millilitresPerTablespoon = 15.0
    static let millilitresPerTeaspoon = 5.0
    static let millilitresPerFluidOunce = 29.5735

    /// Millilitres, for the volume units.
    var millilitres: Double? {
        switch self {
        case .cup: Self.millilitresPerCup
        case .tablespoon: Self.millilitresPerTablespoon
        case .teaspoon: Self.millilitresPerTeaspoon
        case .millilitre: 1
        case .fluidOunce: Self.millilitresPerFluidOunce
        default: nil
        }
    }

    var isVolume: Bool { millilitres != nil }
}

/// A quantity of a unit: "½ cup", "2 large eggs", "150 g".
nonisolated struct Portion: Hashable, Sendable {
    var quantity: Double
    var unit: PortionUnit

    /// Grams of `food`, or nil when the unit needs something the food does not carry.
    func grams(for food: FoodDraft) -> Double? {
        guard quantity > 0 else { return 0 }
        switch unit {
        case .gram: return quantity
        case .ounce: return quantity * PortionUnit.gramsPerOunce
        case .serving: return food.servingGrams.map { quantity * $0 }
        case .piece: return food.pieceGrams.map { quantity * $0 }
        case .cup, .tablespoon, .teaspoon, .millilitre, .fluidOunce:
            guard let gramsPerCup = food.gramsPerCup, let ml = unit.millilitres else { return nil }
            return quantity * ml / PortionUnit.millilitresPerCup * gramsPerCup
        }
    }

    /// "½ cup", "2 large eggs", "1 serving", "150 g".
    func label(for food: FoodDraft) -> String {
        let q = Portion.format(quantity)
        switch unit {
        case .piece:
            let name = food.pieceName ?? "piece"
            return "\(q) \(name)\(quantity == 1 ? "" : "s")"
        case .serving:
            return "\(q) serving\(quantity == 1 ? "" : "s")"
        case .gram, .ounce, .cup, .tablespoon, .teaspoon, .millilitre, .fluidOunce:
            return "\(q) \(unit.label)"
        }
    }

    /// The units that make sense for `food`: mass always, the rest when the food carries them.
    static func units(for food: FoodDraft) -> [PortionUnit] {
        var units: [PortionUnit] = []
        if food.servingGrams ?? 0 > 0 { units.append(.serving) }
        if food.pieceGrams ?? 0 > 0 { units.append(.piece) }
        if food.gramsPerCup ?? 0 > 0 { units += [.cup, .tablespoon, .teaspoon, .millilitre, .fluidOunce] }
        units += [.gram, .ounce]
        return units
    }

    // MARK: Quantities as people type them

    /// "1/2", "3/4", "1 1/2", "1½", "0.75", "1,5" and plain numbers.
    static func parse(_ text: String) -> Double? {
        var text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !text.isEmpty else { return nil }
        var whole = 0.0
        for (glyph, value) in vulgarFractions where text.contains(glyph) {
            text = text.replacingOccurrences(of: glyph, with: "")
            whole += value
        }
        if text.isEmpty { return whole }
        let parts = text.split(separator: " ")
        for part in parts {
            if let slash = part.firstIndex(of: "/") {
                guard let n = Double(part[..<slash]), let d = Double(part[part.index(after: slash)...]), d > 0 else { return nil }
                whole += n / d
            } else if let n = Double(part) {
                whole += n
            } else {
                return nil
            }
        }
        return whole
    }

    /// 0.5 → "½", 1.5 → "1½", 0.75 → "¾", anything else as a number.
    static func format(_ quantity: Double) -> String {
        let whole = quantity.rounded(.down)
        let fraction = quantity - whole
        if let glyph = vulgarFractions.first(where: { abs($0.value - fraction) < 0.01 })?.glyph {
            return whole == 0 ? glyph : "\(Int(whole))\(glyph)"
        }
        return quantity.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static let vulgarFractions: [(glyph: String, value: Double)] = [
        ("½", 0.5), ("¼", 0.25), ("¾", 0.75), ("⅓", 1.0 / 3), ("⅔", 2.0 / 3), ("⅛", 0.125),
    ]
}
