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
    var grams: Double?

    init(date: Date = .now, name: String, kcal: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, fibre: Double = 0, grams: Double? = nil) {
        self.date = date
        self.name = name
        self.kcal = kcal
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.fibre = fibre
        self.grams = grams
    }
}

@Model
final class UserSettings {
    var usesMetric: Bool
    var goal: Goal
    var goalRatePercentPerWeek: Double
    var proteinPerKgOverride: Double?
    var fatFloorPerKg: Double
    var activeProgramID: UUID?
    /// The built-in split chosen on installs that predate programs. `Seeder.ensurePrograms` reads
    /// it once to pick the active program, then clears it.
    @Attribute(originalName: "templateName") var legacyTemplateName: String?

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
    /// Set when the first-run questions have been answered or skipped. Existing installs get
    /// `true` through migration, so only a fresh install sees onboarding.
    var hasCompletedOnboarding: Bool = true
    /// Morning nudge to log weight and food (LogReminders). Off until the lifter asks for it,
    /// because turning it on is what asks for notification permission.
    var remindersEnabled: Bool = false
    /// Minutes after midnight the reminder fires; 10:00 by default.
    var reminderMinutes: Int = LogReminders.defaultMinutes

    init() {
        usesMetric = false
        goal = .maintain
        goalRatePercentPerWeek = 0
        proteinPerKgOverride = nil
        fatFloorPerKg = NutritionEngine.defaultFatFloorPerKg
        activeProgramID = nil
        legacyTemplateName = nil
        heightCm = Units.cm(feet: 5, inches: 10)
        ageYears = 30
        isMale = true
        activityFactor = 1.5
        assumedWeightKg = Units.kg(fromLb: 180)
        cumulativeAdjustmentKcal = 0
        lastAdjustmentDate = nil
        createdAt = .now
        hasCompletedOnboarding = false
    }

    var proteinPerKg: Double { proteinPerKgOverride ?? goal.proteinPerKg }

    func activeProgram(in programs: [Program]) -> Program? {
        programs.first { $0.id == activeProgramID } ?? programs.first
    }
}
