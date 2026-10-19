import Foundation
import SwiftData

/// One day's readiness check-in (DESIGN.md §2.4), kept so it survives leaving the Today tab
/// and is asked for only once. The session started that day copies it.
@Model
final class ReadinessEntry {
    @Attribute(.unique) var date: Date   // start of day
    var sleepHours: Double?
    var sorenessByMuscle: [String: Int]

    init(date: Date, sleepHours: Double? = nil, soreness: [Muscle: Int] = [:]) {
        self.date = Calendar.current.startOfDay(for: date)
        self.sleepHours = sleepHours
        sorenessByMuscle = Dictionary(uniqueKeysWithValues: soreness.map { ($0.key.rawValue, $0.value) })
    }

    var soreMuscles: Set<Muscle> {
        get { Set(sorenessByMuscle.compactMap { Muscle(rawValue: $0.key) }) }
        set { sorenessByMuscle = Dictionary(uniqueKeysWithValues: newValue.map { ($0.rawValue, Readiness.sorenessThreshold) }) }
    }

    var readiness: Readiness {
        var soreness: [Muscle: Int] = [:]
        for (key, value) in sorenessByMuscle {
            if let muscle = Muscle(rawValue: key) { soreness[muscle] = value }
        }
        return Readiness(sleepHours: sleepHours, soreness: soreness)
    }

    /// Anything entered at all. An entry with nothing in it reads as "not logged".
    var isLogged: Bool { readiness.hasAnyInput }

    /// The entry for the day containing `date`, if any.
    static func entry(for date: Date, in entries: [ReadinessEntry]) -> ReadinessEntry? {
        let day = Calendar.current.startOfDay(for: date)
        return entries.first { $0.date == day }
    }
}
