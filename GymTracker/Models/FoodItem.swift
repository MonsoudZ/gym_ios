import Foundation
import SwiftData

/// A food you have logged before, kept so it can be re-logged in two taps.
/// Nutrients are per 100 g, which is how Open Food Facts reports them.
@Model
final class FoodItem {
    var name: String
    var brand: String
    var barcode: String?
    var kcalPer100g: Double
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fibrePer100g: Double
    var servingGrams: Double?
    var servingDescription: String?
    var lastUsed: Date
    var useCount: Int

    init(draft: FoodDraft) {
        name = draft.name
        brand = draft.brand
        barcode = draft.barcode
        kcalPer100g = draft.kcalPer100g
        proteinPer100g = draft.proteinPer100g
        carbsPer100g = draft.carbsPer100g
        fatPer100g = draft.fatPer100g
        fibrePer100g = draft.fibrePer100g
        servingGrams = draft.servingGrams
        servingDescription = draft.servingDescription
        lastUsed = .now
        useCount = 0
    }

    var draft: FoodDraft {
        FoodDraft(name: name, brand: brand, barcode: barcode, kcalPer100g: kcalPer100g, proteinPer100g: proteinPer100g,
                  carbsPer100g: carbsPer100g, fatPer100g: fatPer100g, fibrePer100g: fibrePer100g,
                  servingGrams: servingGrams, servingDescription: servingDescription)
    }

    func update(from draft: FoodDraft) {
        name = draft.name
        brand = draft.brand
        barcode = draft.barcode ?? barcode
        kcalPer100g = draft.kcalPer100g
        proteinPer100g = draft.proteinPer100g
        carbsPer100g = draft.carbsPer100g
        fatPer100g = draft.fatPer100g
        fibrePer100g = draft.fibrePer100g
        servingGrams = draft.servingGrams ?? servingGrams
        servingDescription = draft.servingDescription ?? servingDescription
    }
}

/// Unit-free food description shared by search results, saved foods and the log screen.
nonisolated struct FoodDraft: Hashable, Sendable, Identifiable {
    var name: String
    var brand: String = ""
    var barcode: String? = nil
    var kcalPer100g: Double
    var proteinPer100g: Double = 0
    var carbsPer100g: Double = 0
    var fatPer100g: Double = 0
    var fibrePer100g: Double = 0
    var servingGrams: Double? = nil
    var servingDescription: String? = nil

    var id: String { barcode ?? "\(brand)|\(name)" }

    var displayName: String { brand.isEmpty ? name : "\(name) · \(brand)" }

    func macros(forGrams grams: Double) -> Macros {
        let f = grams / 100
        return Macros(kcal: kcalPer100g * f, protein: proteinPer100g * f, fat: fatPer100g * f,
                      carbs: carbsPer100g * f, fibre: fibrePer100g * f)
    }
}
