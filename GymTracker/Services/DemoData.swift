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

        // History is written on the Upper / Lower rotation; the user's chosen split stays active.
        var dayIDsByName: [String: UUID] = [:]
        if let programs = try? context.fetch(FetchDescriptor<Program>()),
           let upperLower = programs.first(where: { $0.name == BuiltInPrograms.upperLower.name }) {
            if settings.activeProgramID == nil { settings.activeProgramID = upperLower.id }
            dayIDsByName = Dictionary(upperLower.days.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        }
        settings.goal = .cut
        settings.goalRatePercentPerWeek = -0.5
        settings.assumedWeightKg = Units.kg(fromLb: 185)

        // Bodyweight and intake, one entry per day.
        for day in 0...56 {
            let date = cal.date(byAdding: .day, value: day, to: start)!
            let trendLb = 185 - 0.75 * Double(day) / 7
            let noise = Double.random(in: -1.5...1.5, using: &rng)
            context.insert(BodyweightEntry(date: date, kg: Units.kg(fromLb: (trendLb + noise).rounded(toPlaces: 1))))

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
        // Starting loads in pounds; stored in kg like everything else.
        let loadsLb: [String: Double] = [
            "Barbell Bench Press": 155, "Barbell Row": 145, "Overhead Press": 95, "Lat Pulldown": 130,
            "Barbell Curl": 55, "Triceps Pushdown": 65, "Back Squat": 225, "Romanian Deadlift": 200,
            "Leg Press": 400, "Leg Curl": 100, "Standing Calf Raise": 180, "Incline Dumbbell Press": 60,
            "Seated Cable Row": 130, "Dumbbell Shoulder Press": 45, "Lateral Raise": 20, "Face Pull": 55,
            "Deadlift": 285, "Hip Thrust": 225, "Leg Extension": 110,
        ]
        var loads = loadsLb.mapValues { Units.kg(fromLb: $0) }
        let template = BuiltInPrograms.upperLower
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
                session.programDayID = dayIDsByName[day.name]
                session.isCompleted = true
                context.insert(session)

                for (order, spec) in day.specs.enumerated() {
                    guard let exercise = exercises.first(where: { $0.name == spec.name }) else { continue }
                    let weight = loads[spec.name] ?? Units.kg(fromLb: 45)
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
                    if outcome == .progressed { loads[spec.name] = weight + exercise.increment }
                }
            }
        }
        context.saveOrLog()
    }
}

nonisolated extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
