import Foundation
import SwiftData

@Model
final class BodyweightEntry {
    @Attribute(.unique) var date: Date   // start of day
    var kg: Double

    init(date: Date, kg: Double) {
        self.date = Calendar.current.startOfDay(for: date)
        self.kg = kg
    }
}

@Model
final class IntakeEntry {
    var date: Date
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double

    init(date: Date = .now, name: String, kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fibre: Double = 0) {
        self.date = date
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fibre = fibre
    }
}

@Model
final class UserSettings {
    var usesMetric: Bool
    var goal: Goal
    var goalRatePercentPerWeek: Double
    var proteinPerKgOverride: Double?
    var fatFloorPerKg: Double
    var templateName: String

    // Profile, used only for the provisional Mifflin-St Jeor estimate.
    var heightCm: Double
    var ageYears: Int
    var isMale: Bool
    var activityFactor: Double
    var assumedWeightKg: Double

    // Weekly adjustment state.
    var cumulativeAdjustmentKcal: Double
    var lastAdjustmentDate: Date?
    var createdAt: Date

    init() {
        usesMetric = true
        goal = .maintain
        goalRatePercentPerWeek = 0
        proteinPerKgOverride = nil
        fatFloorPerKg = NutritionEngine.defaultFatFloorPerKg
        templateName = ProgramTemplates.upperLower.name
        heightCm = 175
        ageYears = 30
        isMale = true
        activityFactor = 1.5
        assumedWeightKg = 80
        cumulativeAdjustmentKcal = 0
        lastAdjustmentDate = nil
        createdAt = .now
    }

    var proteinPerKg: Double { proteinPerKgOverride ?? goal.proteinPerKg }
}
