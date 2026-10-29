import Foundation
import SwiftData

/// Which of the app's own nutrition exports a file is (CSVExport).
nonisolated enum NutritionImportKind: String, Sendable {
    case bodyweight = "Weigh-ins"
    case food = "Food"
}

nonisolated struct ImportedWeighIn: Hashable, Sendable {
    var day: Date   // start of day
    var kg: Double
    var fromHealth: Bool
}

nonisolated struct ImportedFood: Hashable, Sendable {
    var date: Date
    var name: String
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fibre: Double
    var grams: Double?
}

nonisolated struct NutritionImport: Sendable {
    var kind: NutritionImportKind
    var weighIns: [ImportedWeighIn] = []
    var foods: [ImportedFood] = []
    /// Rows that looked like entries but could not be read (no date, no number).
    var skippedRows: Int

    var count: Int { kind == .bodyweight ? weighIns.count : foods.count }
    var dateRange: ClosedRange<Date>? {
        let dates = kind == .bodyweight ? weighIns.map(\.day) : foods.map(\.date)
        guard let first = dates.min(), let last = dates.max() else { return nil }
        return first...last
    }
}

nonisolated enum NutritionImportError: Error, LocalizedError, Equatable {
    case unknownFormat
    case noRows

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            "This is not a weigh-in or food export from this app. bodyweight.csv has date and kg columns; food.csv has date, name and kcal."
        case .noRows:
            "No entries with a date and a number were found in the file."
        }
    }
}

/// Reads `bodyweight.csv` and `food.csv` as `CSVExport` writes them, so a backup comes back
/// whole (DESIGN.md §6). Pure; the store is touched by `NutritionImportService`.
///
/// Dates are `yyyy-MM-dd` and times `HH:mm` in the calendar the file was exported in, which is
/// taken to be this one. A row with only `lb` is converted; a food row with no time lands at
/// noon, like a backdated entry typed in the app.
nonisolated enum NutritionImportParser {
    static func detect(_ table: CSVTable) -> NutritionImportKind? {
        guard table.hasColumn("date") else { return nil }
        if table.hasColumn("kcal"), table.hasColumn("name") { return .food }
        if table.hasColumn("kg") || table.hasColumn("lb") { return .bodyweight }
        return nil
    }

    static func parse(_ text: String, calendar: Calendar = .current) throws -> NutritionImport {
        let table = CSVTable(text: text)
        guard let kind = detect(table) else { throw NutritionImportError.unknownFormat }
        var result = NutritionImport(kind: kind, skippedRows: 0)
        for row in table.rows {
            guard let date = day(table.value(row, "date"), calendar: calendar) else { result.skippedRows += 1; continue }
            switch kind {
            case .bodyweight:
                let kg = CSVTable.number(table.value(row, "kg")) ?? CSVTable.number(table.value(row, "lb")).map(Units.kg(fromLb:))
                guard let kg, kg > 0 else { result.skippedRows += 1; continue }
                let source = (table.value(row, "source") ?? "").lowercased()
                result.weighIns.append(ImportedWeighIn(day: date, kg: kg, fromHealth: source == "health"))
            case .food:
                guard let name = table.value(row, "name"), let kcal = CSVTable.number(table.value(row, "kcal")), kcal >= 0 else {
                    result.skippedRows += 1
                    continue
                }
                let time = clock(table.value(row, "time"))
                let stamp = calendar.date(bySettingHour: time?.hour ?? 12, minute: time?.minute ?? 0, second: 0, of: date) ?? date
                result.foods.append(ImportedFood(
                    date: stamp, name: name, kcal: kcal,
                    protein: CSVTable.number(table.value(row, "protein_g")) ?? 0,
                    carbs: CSVTable.number(table.value(row, "carbs_g")) ?? 0,
                    fat: CSVTable.number(table.value(row, "fat_g")) ?? 0,
                    fibre: CSVTable.number(table.value(row, "fibre_g")) ?? 0,
                    grams: CSVTable.number(table.value(row, "grams"))))
            }
        }
        guard result.count > 0 else { throw NutritionImportError.noRows }
        return result
    }

    /// `yyyy-MM-dd`, or an ISO 8601 timestamp, as the start of that day.
    private static func day(_ text: String?, calendar: Calendar) -> Date? {
        guard let text else { return nil }
        let parts = text.split(separator: "-")
        if parts.count == 3, let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2].prefix(2)),
           let date = calendar.date(from: DateComponents(year: y, month: m, day: d)) {
            return calendar.startOfDay(for: date)
        }
        if let iso = ISO8601DateFormatter().date(from: text) { return calendar.startOfDay(for: iso) }
        return nil
    }

    private static func clock(_ text: String?) -> (hour: Int, minute: Int)? {
        guard let text else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]), (0...23).contains(h), (0...59).contains(m) else { return nil }
        return (h, m)
    }
}

/// Writes a parsed weigh-in or food file into the store. A day that already has a weigh-in is
/// left alone (a typed weight is never overwritten, DESIGN.md §3.2); a food entry already here
/// at the same minute with the same name and calories is not written again. So bringing the
/// export back onto the phone it came from adds nothing, and importing twice adds nothing.
@MainActor
enum NutritionImportService {
    struct Outcome: Equatable {
        var added = 0
        var skipped = 0
    }

    /// How many of the file's rows are already in the store, for the preview.
    static func alreadyPresent(_ file: NutritionImport, context: ModelContext) -> Int {
        switch file.kind {
        case .bodyweight:
            let days = Set(((try? context.fetch(FetchDescriptor<BodyweightEntry>())) ?? []).map(\.date))
            return file.weighIns.filter { days.contains($0.day) }.count
        case .food:
            let keys = existingFoodKeys(context: context)
            return file.foods.filter { keys.contains(foodKey(date: $0.date, name: $0.name, kcal: $0.kcal)) }.count
        }
    }

    @discardableResult
    static func apply(_ file: NutritionImport, context: ModelContext) -> Outcome {
        var outcome = Outcome()
        switch file.kind {
        case .bodyweight:
            var days = Set(((try? context.fetch(FetchDescriptor<BodyweightEntry>())) ?? []).map(\.date))
            for weighIn in file.weighIns {
                guard days.insert(weighIn.day).inserted else { outcome.skipped += 1; continue }
                context.insert(BodyweightEntry(date: weighIn.day, kg: weighIn.kg, fromHealth: weighIn.fromHealth))
                outcome.added += 1
            }
        case .food:
            var keys = existingFoodKeys(context: context)
            for food in file.foods {
                guard keys.insert(foodKey(date: food.date, name: food.name, kcal: food.kcal)).inserted else { outcome.skipped += 1; continue }
                context.insert(IntakeEntry(date: food.date, name: food.name, kcal: food.kcal, protein: food.protein,
                                           carbs: food.carbs, fat: food.fat, fibre: food.fibre, grams: food.grams))
                outcome.added += 1
            }
        }
        context.saveOrLog()
        LogReminders.refresh(context: context)
        return outcome
    }

    private static func existingFoodKeys(context: ModelContext) -> Set<String> {
        Set(((try? context.fetch(FetchDescriptor<IntakeEntry>())) ?? []).map { foodKey(date: $0.date, name: $0.name, kcal: $0.kcal) })
    }

    /// The minute, the name and the calories: what the export keeps of an entry's identity.
    nonisolated static func foodKey(date: Date, name: String, kcal: Double) -> String {
        "\(Int(date.timeIntervalSince1970 / 60))|\(name)|\(Int(kcal.rounded()))"
    }
}
