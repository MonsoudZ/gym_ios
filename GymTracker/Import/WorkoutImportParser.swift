import Foundation

/// The apps whose workout exports can be read (DESIGN.md §4, "Importing history").
nonisolated enum WorkoutImportSource: String, Sendable, CaseIterable {
    case strong = "Strong"
    case hevy = "Hevy"
}

nonisolated enum WeightUnit: String, Sendable, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "kg" : "lb" }

    func kilograms(_ value: Double) -> Double { self == .kg ? value : Units.kg(fromLb: value) }
}

/// One set as the other app logged it. Weight is already in kilograms.
nonisolated struct ImportedSet: Hashable, Sendable {
    var exerciseName: String
    var weightKg: Double
    var reps: Int
    var rpe: Double?
    var isWarmup: Bool
}

/// One workout from the file, its sets in the order they were done.
nonisolated struct ImportedWorkout: Hashable, Sendable {
    var source: WorkoutImportSource
    var name: String
    var date: Date
    /// The date exactly as the file wrote it. The key is built from this rather than `date`
    /// so the same file gives the same keys whatever time zone it is imported in.
    var dateText: String
    var sets: [ImportedSet]
    /// Strong's "Workout Notes" or Hevy's "description", when the file has one.
    var notes: String? = nil

    /// Stable across exports of the same history, so importing a file twice adds nothing.
    var key: String { "\(source.rawValue)|\(dateText)|\(name)" }

    /// Exercises in order of first appearance.
    var exerciseNames: [String] {
        var seen: Set<String> = []
        return sets.map(\.exerciseName).filter { seen.insert($0).inserted }
    }
}

nonisolated struct WorkoutImport: Sendable {
    var source: WorkoutImportSource
    var workouts: [ImportedWorkout]
    /// True when the file says which unit its weights are in; otherwise the assumed unit was used.
    var unitFromFile: Bool
    /// Rows that looked like sets but could not be read (no date, no reps, bad numbers).
    var skippedRows: Int

    var setCount: Int { workouts.reduce(0) { $0 + $1.sets.count } }
    var dateRange: ClosedRange<Date>? {
        guard let first = workouts.map(\.date).min(), let last = workouts.map(\.date).max() else { return nil }
        return first...last
    }

    /// Every exercise name in the file with its set count, most-used first.
    var exerciseCounts: [(name: String, sets: Int)] {
        var counts: [String: Int] = [:]
        for workout in workouts { for set in workout.sets { counts[set.exerciseName, default: 0] += 1 } }
        return counts.map { (name: $0.key, sets: $0.value) }
            .sorted { $0.sets != $1.sets ? $0.sets > $1.sets : $0.name < $1.name }
    }
}

nonisolated enum WorkoutImportError: Error, LocalizedError, Equatable {
    case unknownFormat
    case noWorkouts

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            "This is not a Strong or Hevy workout export. Strong's has a Date, Exercise Name and Set Order column; Hevy's has title, exercise_title and set_index."
        case .noWorkouts:
            "No sets with reps were found in the file."
        }
    }
}

/// Reads Strong and Hevy CSV exports into `ImportedWorkout`s. Pure; the store is touched by
/// `WorkoutImportService`.
///
/// Strong writes one row per set: `Date, Workout Name, Duration, Exercise Name, Set Order,
/// Weight, Reps, Distance, Seconds, Notes, Workout Notes, RPE`. Older exports add a `Weight
/// Unit` column per row and may use semicolons; current ones give no unit, so the caller says
/// which the account used. `Set Order` is a number, `W` for a warm-up, or "Rest Timer" / "Note"
/// for rows that are not sets.
///
/// Hevy writes `title, start_time, end_time, description, exercise_title, superset_id,
/// exercise_notes, set_index, set_type, weight_kg | weight_lbs, reps, distance_km |
/// distance_miles, duration_seconds, rpe`, the unit in the column name, and dates like
/// "30 Jun 2025, 19:56" or ISO 8601. `set_type` is normal, warmup, dropset or failure.
///
/// Rows without reps (timed or distance work) are skipped; a set at 0 kg with reps (pull-ups)
/// is kept. Times are read in `timeZone`, since neither export carries one.
nonisolated enum WorkoutImportParser {
    static func detect(_ table: CSVTable) -> WorkoutImportSource? {
        if table.hasColumn("exercise_title"), table.hasColumn("set_index") { return .hevy }
        if table.hasColumn("Exercise Name"), table.hasColumn("Set Order"), table.hasColumn("Date") { return .strong }
        return nil
    }

    static func parse(_ text: String, assumedUnit: WeightUnit, timeZone: TimeZone = .current) throws -> WorkoutImport {
        let table = CSVTable(text: text)
        guard let source = detect(table) else { throw WorkoutImportError.unknownFormat }
        let result = switch source {
        case .strong: parseStrong(table, assumedUnit: assumedUnit, timeZone: timeZone)
        case .hevy: parseHevy(table, assumedUnit: assumedUnit, timeZone: timeZone)
        }
        guard !result.workouts.isEmpty else { throw WorkoutImportError.noWorkouts }
        return result
    }

    // MARK: Strong

    private static func parseStrong(_ table: CSVTable, assumedUnit: WeightUnit, timeZone: TimeZone) -> WorkoutImport {
        var builder = Builder(source: .strong)
        let unitColumn = table.hasColumn("Weight Unit")
        for row in table.rows {
            let order = (table.value(row, "Set Order") ?? "").lowercased()
            if order.contains("rest timer") || order.hasPrefix("note") { continue }
            guard let exercise = table.value(row, "Exercise Name"),
                  let dateText = table.value(row, "Date"),
                  let date = strongDate(dateText, timeZone: timeZone),
                  let reps = reps(table.value(row, "Reps")) else { builder.skipped += 1; continue }
            var unit = assumedUnit
            if unitColumn, let text = table.value(row, "Weight Unit") {
                unit = text.lowercased().hasPrefix("k") ? .kg : .lb
            }
            let weight = CSVTable.number(table.value(row, "Weight")) ?? 0
            guard weight >= 0 else { builder.skipped += 1; continue }
            let set = ImportedSet(exerciseName: exercise, weightKg: unit.kilograms(weight), reps: reps,
                                  rpe: rpe(table.value(row, "RPE")), isWarmup: order.hasPrefix("w"))
            builder.add(set, workoutName: table.value(row, "Workout Name") ?? "Strong workout", date: date, dateText: dateText,
                        notes: table.value(row, "Workout Notes"))
        }
        return builder.finish(unitFromFile: unitColumn)
    }

    private static func strongDate(_ text: String?, timeZone: TimeZone) -> Date? {
        guard let text else { return nil }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            if let date = date(text, format: format, timeZone: timeZone) { return date }
        }
        return isoDate(text)
    }

    // MARK: Hevy

    private static func parseHevy(_ table: CSVTable, assumedUnit: WeightUnit, timeZone: TimeZone) -> WorkoutImport {
        var builder = Builder(source: .hevy)
        let weightColumn: String
        let unit: WeightUnit
        let unitFromFile: Bool
        if table.hasColumn("weight_kg") {
            (weightColumn, unit, unitFromFile) = ("weight_kg", .kg, true)
        } else if table.hasColumn("weight_lbs") {
            (weightColumn, unit, unitFromFile) = ("weight_lbs", .lb, true)
        } else {
            (weightColumn, unit, unitFromFile) = ("weight", assumedUnit, false)
        }
        for row in table.rows {
            guard let exercise = table.value(row, "exercise_title"),
                  let dateText = table.value(row, "start_time"),
                  let date = hevyDate(dateText, timeZone: timeZone),
                  let reps = reps(table.value(row, "reps")) else { builder.skipped += 1; continue }
            let weight = CSVTable.number(table.value(row, weightColumn)) ?? 0
            guard weight >= 0 else { builder.skipped += 1; continue }
            let type = (table.value(row, "set_type") ?? "").lowercased()
            let set = ImportedSet(exerciseName: exercise, weightKg: unit.kilograms(weight), reps: reps,
                                  rpe: rpe(table.value(row, "rpe")), isWarmup: type == "warmup" || type == "warm up" || type == "2")
            builder.add(set, workoutName: table.value(row, "title") ?? "Hevy workout", date: date, dateText: dateText,
                        notes: table.value(row, "description"))
        }
        return builder.finish(unitFromFile: unitFromFile)
    }

    private static func hevyDate(_ text: String?, timeZone: TimeZone) -> Date? {
        guard let text else { return nil }
        for format in ["d MMM yyyy, HH:mm", "d MMM yyyy, h:mm a", "yyyy-MM-dd HH:mm:ss"] {
            if let date = date(text, format: format, timeZone: timeZone) { return date }
        }
        return isoDate(text)
    }

    // MARK: Shared

    private struct Builder {
        var source: WorkoutImportSource
        var workouts: [ImportedWorkout] = []
        var indexByKey: [String: Int] = [:]
        var skipped = 0

        init(source: WorkoutImportSource) { self.source = source }

        mutating func add(_ set: ImportedSet, workoutName: String, date: Date, dateText: String, notes: String? = nil) {
            let key = ImportedWorkout(source: source, name: workoutName, date: date, dateText: dateText, sets: []).key
            let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? notes : nil
            if let index = indexByKey[key] {
                workouts[index].sets.append(set)
                if workouts[index].notes == nil { workouts[index].notes = notes }
            } else {
                indexByKey[key] = workouts.count
                workouts.append(ImportedWorkout(source: source, name: workoutName, date: date, dateText: dateText, sets: [set], notes: notes))
            }
        }

        func finish(unitFromFile: Bool) -> WorkoutImport {
            WorkoutImport(source: source, workouts: workouts.sorted { $0.date < $1.date },
                          unitFromFile: unitFromFile, skippedRows: skipped)
        }
    }

    private static func reps(_ text: String?) -> Int? {
        guard let value = CSVTable.number(text), value > 0 else { return nil }
        return Int(value.rounded())
    }

    private static func rpe(_ text: String?) -> Double? {
        guard let value = CSVTable.number(text), value > 0, value <= 10 else { return nil }
        return value
    }

    private static func date(_ text: String, format: String, timeZone: TimeZone) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.date(from: text)
    }

    private static func isoDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
