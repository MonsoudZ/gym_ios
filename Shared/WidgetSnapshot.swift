import Foundation

/// What the home and lock screen widgets show, written by the app whenever something is
/// saved and read by the widget extension. The widgets never open the database: the app
/// pre-formats every line, so the extension only lays text out.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    var lift: LiftSnapshot?
    var nutrition: NutritionWidgetSnapshot?
    var updatedAt: Date

    static let empty = WidgetSnapshot(lift: nil, nutrition: nil, updatedAt: .distantPast)
}

/// Today's lift: the next program day and its plan, or the workout that is under way.
nonisolated struct LiftSnapshot: Codable, Hashable, Sendable {
    nonisolated struct Line: Codable, Hashable, Sendable, Identifiable {
        var name: String
        /// "100 kg · 3 × 8–12", already in the lifter's units.
        var detail: String
        /// "Deload", "Progressed", shown as a small badge when set.
        var badge: String?
        var id: String { name }
    }

    var dayName: String
    var lines: [Line]
    /// The lift the Today tab leads with, and why.
    var headline: Line?
    var headlineReason: String?
    /// Set when a workout is in progress; the plan then reads "Continue".
    var inProgress: Bool
}

/// Today's calories and protein against the target. `dayStart` lets the widget zero the
/// eaten amounts at midnight before the app has had a chance to write a new snapshot.
nonisolated struct NutritionWidgetSnapshot: Codable, Hashable, Sendable {
    var dayStart: Date
    var eatenKcal: Double
    var targetKcal: Double
    var eatenProtein: Double
    var targetProtein: Double
    var isProvisional: Bool

    func zeroed(for day: Date) -> NutritionWidgetSnapshot {
        var copy = self
        copy.dayStart = day
        copy.eatenKcal = 0
        copy.eatenProtein = 0
        return copy
    }
}

/// The snapshot file in the app group container, shared between the app and its widgets.
nonisolated enum WidgetStore {
    static let appGroup = "group.com.monsoudzanaty.GymTracker"
    static let fileName = "widget-snapshot.json"

    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appending(path: fileName)
    }

    static func load() -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    static func save(_ snapshot: WidgetSnapshot) throws {
        guard let url else { return }
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Deep links the widgets open; `ContentView` switches to the matching tab.
nonisolated enum WidgetLink {
    static let scheme = "gymtracker"
    static let today = URL(string: "\(scheme)://today")!
    static let nutrition = URL(string: "\(scheme)://nutrition")!
}
