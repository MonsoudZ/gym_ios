import Foundation
import SwiftData

@Model
final class BodyweightEntry {
    @Attribute(.unique) var date: Date   // start of day
    var kg: Double
    /// Filled in from Health rather than typed. Only these are updated when Health's number
    /// for the day changes; a typed weight is never overwritten (BodyweightImport).
    var fromHealth: Bool = false

    init(date: Date, kg: Double, fromHealth: Bool = false) {
        self.date = Calendar.current.startOfDay(for: date)
        self.kg = kg
        self.fromHealth = fromHealth
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

    /// The timestamp for a food logged against `day`: now when that is today, else noon on
    /// that day, so a backdated entry sorts into its day whatever the time zone does.
    nonisolated static func timestamp(for day: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        return calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }

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
    /// Reads HRV and resting heart rate from Health as a readiness input (HealthService).
    /// Off until the lifter asks for it, because turning it on is what asks for Health access.
    var heartReadinessEnabled: Bool = false
    /// Fills last night's sleep on the readiness check-in from Health (SleepRule).
    var sleepFromHealthEnabled: Bool = false
    /// Fills days with no typed weigh-in from Health's bodyweight samples (BodyweightImport).
    var bodyweightFromHealthEnabled: Bool = false
    /// Saves each finished workout to Health as strength training.
    var saveWorkoutsToHealthEnabled: Bool = false

    /// A program day picked on the Today tab in place of the next in rotation, until a workout
    /// starts. Stored so the widget shows the same day.
    var chosenDayID: UUID?

    var usesAnyHealthReading: Bool { heartReadinessEnabled || sleepFromHealthEnabled || bodyweightFromHealthEnabled }

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
