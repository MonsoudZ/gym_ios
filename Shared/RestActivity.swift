import ActivityKit
import AppIntents
import Foundation

/// The rest countdown as a Live Activity on the lock screen and in the Dynamic Island.
/// One activity lives for the whole workout and is updated for each rest, so the island
/// does not flash in and out between sets.
nonisolated struct RestActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var exerciseName: String
        var startedAt: Date
        var endsAt: Date

        var totalSeconds: Int { Int(endsAt.timeIntervalSince(startedAt).rounded()) }
        var isDone: Bool { endsAt <= .now }
    }

    /// The program day, shown as the activity's title.
    var dayName: String
}

/// Buttons on the Live Activity. These run in the app's process (that is what
/// `LiveActivityIntent` is for), so they drive the same `RestTimer` the in-app bar uses.
/// The extension compiles them only so its buttons can name them.
nonisolated struct AddRestTimeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add 30 seconds of rest"
    static let isDiscoverable = false

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RestTimer.shared.addTime()
        #endif
        return .result()
    }
}

nonisolated struct SkipRestIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let isDiscoverable = false

    init() {}

    @MainActor func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        RestTimer.shared.skip()
        #endif
        return .result()
    }
}
