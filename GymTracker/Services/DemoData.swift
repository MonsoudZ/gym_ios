import Foundation
import SwiftData

/// Eight weeks of plausible history so every screen has something to show.
enum DemoData {
    nonisolated struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    static func load(context: ModelContext, exercises: [Exercise], settings: UserSettings) {
        var rng = SplitMix64(state: 42)
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let start = cal.date(byAdding: .day, value: -56, to: today)!

        settings.templateName = ProgramTemplates.upperLower.name
        settings.goal = .cut
        settings.goalRatePercentPerWeek = -0.5
        settings.assumedWeightKg = 84

        // Bodyweight and intake, one entry per day.
        for day in 0...56 {
            let date = cal.date(byAdding: .day, value: day, to: start)!
            let trend = 84 - 0.35 * Double(day) / 7
            let noise = Double.random(in: -0.7...0.7, using: &rng)
            context.insert(BodyweightEntry(date: date, kg: (trend + noise).rounded(toPlaces: 1)))

            if day < 56, Double.random(in: 0...1, using: &rng) > 0.08 {
                let kcal = Double.random(in: 2100...2500, using: &rng).rounded()
                let protein = Double.random(in: 160...190, using: &rng).rounded()
                let fat = Double.random(in: 60...80, using: &rng).rounded()
                let carbs = max(0, (kcal - 4 * protein - 9 * fat) / 4).rounded()
                context.insert(IntakeEntry(date: date.addingTimeInterval(12 * 3600), name: "Day total",
                                           kcal: kcal, protein: protein, carbs: carbs, fat: fat, fibre: 28))
            }
        }

        // Workouts: four per week on the Upper / Lower rotation.
        var loads: [String: Double] = [
            "Barbell Bench Press": 70, "Barbell Row": 65, "Overhead Press": 42.5, "Lat Pulldown": 60,
            "Barbell Curl": 25, "Triceps Pushdown": 30, "Back Squat": 100, "Romanian Deadlift": 90,
            "Leg Press": 180, "Leg Curl": 45, "Standing Calf Raise": 80, "Incline Dumbbell Press": 26,
            "Seated Cable Row": 60, "Dumbbell Shoulder Press": 20, "Lateral Raise": 10, "Face Pull": 25,
            "Deadlift": 130, "Hip Thrust": 100, "Leg Extension": 50,
        ]
        let template = ProgramTemplates.upperLower
        var dayIndex = 0
        var sessionCount = 0
        for week in 0..<8 {
            for offset in [0, 1, 3, 4] {
                let date = cal.date(byAdding: .day, value: week * 7 + offset, to: start)!.addingTimeInterval(18 * 3600)
                guard date < .now else { continue }
                let day = template.days[dayIndex % template.days.count]
                dayIndex += 1
                sessionCount += 1
                let session = WorkoutSession(date: date, templateDayName: day.name,
                                             sleepHours: Double.random(in: 6...8.5, using: &rng).rounded(toPlaces: 1))
                session.isCompleted = true
                context.insert(session)

                for (order, spec) in day.exercises.enumerated() {
                    guard let exercise = exercises.first(where: { $0.name == spec.name }) else { continue }
                    let weight = loads[spec.name] ?? 20
                    // Bench holds for its last three Upper A sessions (one per week) so the Today screen has a deload to show.
                    let forceHold = spec.name == "Barbell Bench Press" && week >= 5
                    let roll = Double.random(in: 0...1, using: &rng)
                    let outcome: Verdict = forceHold ? .held : roll < 0.6 ? .progressed : roll < 0.9 ? .held : .failed
                    for setNumber in 0..<spec.setCount {
                        let reps: Int
                        let rpe: Double
                        switch outcome {
                        case .progressed: reps = spec.repRangeHigh; rpe = Double.random(in: 7...9, using: &rng).rounded(toPlaces: 1)
                        case .held: reps = max(spec.repRangeLow, spec.repRangeHigh - 1 - setNumber / 2); rpe = 9
                        default: reps = max(1, spec.repRangeLow - 1); rpe = 10
                        }
                        let set = SetEntry(exerciseOrder: order, setNumber: setNumber, weight: weight, reps: reps, rpe: rpe)
                        set.completedAt = date
                        set.exercise = exercise
                        set.session = session
                        context.insert(set)
                    }
                    if outcome == .progressed { loads[spec.name] = weight + spec.increment }
                }
            }
        }
        try? context.save()
    }
}

nonisolated extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
