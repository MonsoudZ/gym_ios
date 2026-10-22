import Foundation

/// A parsed CSV file: a header and rows of fields, looked up by column name. Handles quoted
/// fields with embedded delimiters, quotes and line breaks, CRLF line endings, a byte-order
/// mark, and comma, semicolon or tab delimiters (picked from the header line), since Strong's
/// older exports used semicolons in some locales.
nonisolated struct CSVTable: Sendable {
    let header: [String]
    let rows: [[String]]
    let delimiter: Character
    private let columnIndex: [String: Int]

    init(text: String) {
        var text = text
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        delimiter = Self.detectDelimiter(in: text)
        var records = Self.records(in: text, delimiter: delimiter)
        let header = records.isEmpty ? [] : records.removeFirst()
        self.header = header.map(Self.columnName)
        rows = records.filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        var index: [String: Int] = [:]
        for (i, name) in self.header.enumerated() where index[name] == nil { index[name] = i }
        columnIndex = index
    }

    func hasColumn(_ name: String) -> Bool { columnIndex[Self.columnName(name)] != nil }

    /// The trimmed value of `column` in `row`, or nil when the column is missing or the row is short.
    func value(_ row: [String], _ column: String) -> String? {
        guard let i = columnIndex[Self.columnName(column)], i < row.count else { return nil }
        let value = row[i].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// A number as Strong or Hevy write it, accepting a decimal comma.
    static func number(_ text: String?) -> Double? {
        guard var text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if !text.contains("."), text.contains(",") { text = text.replacingOccurrences(of: ",", with: ".") }
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func columnName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func detectDelimiter(in text: String) -> Character {
        let firstLine = text.prefix { $0 != "\n" && $0 != "\r" }
        let counts: [(Character, Int)] = [",", ";", "\t"].map { d in (d, firstLine.filter { $0 == d }.count) }
        return counts.max { $0.1 < $1.1 }.map { $0.1 > 0 ? $0.0 : "," } ?? ","
    }

    /// Walks Unicode scalars rather than Characters, since Swift folds "\r\n" into one Character.
    private static func records(in text: String, delimiter: Character) -> [[String]] {
        let delimiter = delimiter.unicodeScalars.first!
        let quote: Unicode.Scalar = "\""
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        var atFieldStart = true
        let scalars = Array(text.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let c = scalars[i]
            if inQuotes {
                if c == quote {
                    if i + 1 < scalars.count, scalars[i + 1] == quote {
                        field.unicodeScalars.append(quote)
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else if c == quote, atFieldStart {
                inQuotes = true
            } else if c == delimiter {
                record.append(field)
                field = ""
                atFieldStart = true
                i += 1
                continue
            } else if c == "\n" || c == "\r" {
                if c == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
                record.append(field)
                records.append(record)
                record = []
                field = ""
                atFieldStart = true
                i += 1
                continue
            } else {
                field.unicodeScalars.append(c)
            }
            atFieldStart = false
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}
