import Foundation
import SwiftData

/// Everything the app stores, as CSV files the lifter can keep, open in a spreadsheet, or bring
/// back (DESIGN.md §6: "Export to CSV from day one").
///
/// `workouts.csv` is written in Hevy's column layout with ISO 8601 times and kilograms, so the
/// app's own importer (Settings → Import from Strong or Hevy) reads it back on a new phone with
/// every set, warm-up flag, RPE and note intact. The other files are plain tables.
enum CSVExport {
    static let workoutsHeader = ["title", "start_time", "end_time", "description", "exercise_title", "superset_id",
                                 "exercise_notes", "set_index", "set_type", "weight_kg", "reps", "distance_km",
                                 "duration_seconds", "rpe"]

    /// One row per set of every finished workout, oldest first.
    static func workouts(_ sessions: [WorkoutSession]) -> String {
        var lines = [line(workoutsHeader)]
        for session in sessions.filter(\.isCompleted).sorted(by: { $0.date < $1.date }) {
            let start = iso(session.date)
            let end = session.sets.compactMap(\.completedAt).max().map(iso) ?? ""
            let sets = session.sets.sorted { ($0.exerciseOrder, $0.setNumber) < ($1.exerciseOrder, $1.setNumber) }
            for (index, set) in sets.enumerated() {
                guard let exercise = set.exercise else { continue }
                lines.append(line([
                    session.templateDayName, start, end, session.notes ?? "", exercise.name, "",
                    exercise.notes ?? "", String(index), set.isWarmup ? "warmup" : "normal",
                    number(set.weight), String(set.reps), "", "", set.rpe.map(number) ?? "",
                ]))
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let bodyweightHeader = ["date", "kg", "lb", "source"]

    static func bodyweight(_ entries: [BodyweightEntry]) -> String {
        var lines = [line(bodyweightHeader)]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            lines.append(line([day(entry.date), number(entry.kg), number(Units.lb(fromKg: entry.kg)), entry.fromHealth ? "health" : "typed"]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let foodHeader = ["date", "time", "name", "kcal", "protein_g", "carbs_g", "fat_g", "fibre_g", "grams"]

    static func food(_ entries: [IntakeEntry]) -> String {
        var lines = [line(foodHeader)]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            lines.append(line([day(entry.date), time(entry.date), entry.name, number(entry.kcal), number(entry.protein),
                               number(entry.carbs), number(entry.fat), number(entry.fibre), entry.grams.map(number) ?? ""]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let readinessHeader = ["date", "sleep_hours", "sleep_source", "sore_muscles", "hrv_ms", "resting_heart_rate"]

    static func readiness(_ entries: [ReadinessEntry]) -> String {
        var lines = [line(readinessHeader)]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            let sore = entry.sorenessByMuscle.keys.sorted().joined(separator: "; ")
            lines.append(line([day(entry.date), entry.sleepHours.map(number) ?? "",
                               entry.sleepHours == nil ? "" : (entry.sleepFromHealth ? "health" : "typed"),
                               sore, entry.hrvMs.map(number) ?? "", entry.restingHeartRate.map(number) ?? ""]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static let adjustmentsHeader = ["date", "kcal", "trend_rate_pct_per_week", "goal_rate_pct_per_week", "cumulative_kcal", "note"]

    static func adjustments(_ entries: [AdjustmentEntry]) -> String {
        var lines = [line(adjustmentsHeader)]
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            lines.append(line([iso(entry.date), String(entry.kcal), number(entry.trendRatePercentPerWeek),
                               number(entry.goalRatePercentPerWeek), number(entry.cumulativeKcalAfter), entry.note ?? ""]))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: Files

    /// Writes every file into a fresh folder in the temporary directory and returns their URLs,
    /// ready for the share sheet. Empty tables are left out.
    static func writeFiles(context: ModelContext, now: Date = .now) throws -> [URL] {
        let stamp = now.formatted(.iso8601.year().month().day().dateSeparator(.dash))
        let folder = FileManager.default.temporaryDirectory.appending(path: "GymTracker export \(stamp)", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        let weights = try context.fetch(FetchDescriptor<BodyweightEntry>())
        let intake = try context.fetch(FetchDescriptor<IntakeEntry>())
        let readinessEntries = try context.fetch(FetchDescriptor<ReadinessEntry>())
        let adjustmentEntries = try context.fetch(FetchDescriptor<AdjustmentEntry>())

        let tables: [(name: String, text: String, rows: Int)] = [
            ("workouts.csv", workouts(sessions), sessions.filter(\.isCompleted).count),
            ("bodyweight.csv", bodyweight(weights), weights.count),
            ("food.csv", food(intake), intake.count),
            ("readiness.csv", readiness(readinessEntries), readinessEntries.count),
            ("adjustments.csv", adjustments(adjustmentEntries), adjustmentEntries.count),
        ]
        var urls: [URL] = []
        for table in tables where table.rows > 0 {
            let url = folder.appending(path: table.name)
            try table.text.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }

    // MARK: Formatting (pure)

    /// Fields joined by commas; one holding a comma, quote or line break is quoted, with quotes doubled.
    nonisolated static func line(_ fields: [String]) -> String {
        fields.map { field in
            field.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
                ? "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
                : field
        }.joined(separator: ",")
    }

    /// Plain digits with a dot, never grouped or localised, so the file reads the same anywhere.
    nonisolated static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(format: "%.3f", value)
            .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }

    nonisolated static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    nonisolated static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    nonisolated static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}
