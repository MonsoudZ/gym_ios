import ActivityKit
import Foundation
import Observation

/// The rest between sets, started when a working set is ticked done. One shared instance,
/// so the in-app bar, the lock-screen notification and the Live Activity's buttons all act
/// on the same countdown, and a rest keeps running if the workout screen is left.
@Observable
final class RestTimer {
    static let shared = RestTimer()

    struct Rest: Equatable {
        var startedAt: Date
        var endsAt: Date
        var exerciseName: String
        var seconds: Int { Int(endsAt.timeIntervalSince(startedAt).rounded()) }
    }

    private(set) var rest: Rest?
    private var dayName = ""

    private init() {
        // A Live Activity left over from a workout the app was killed during.
        Task { await RestActivityController.end() }
    }

    func start(seconds: Int, exerciseName: String, dayName: String) {
        let now = Date.now
        let rest = Rest(startedAt: now, endsAt: now.addingTimeInterval(TimeInterval(seconds)), exerciseName: exerciseName)
        self.rest = rest
        self.dayName = dayName
        // Rings when the phone is locked; in the foreground the bar and haptic do the job.
        Task { await RestNotifier.schedule(endsAt: rest.endsAt, exerciseName: exerciseName) }
        Task { await showActivity(rest) }
    }

    func addTime(_ seconds: TimeInterval = 30) {
        guard var rest, !isDone else { return }
        rest.endsAt.addTimeInterval(seconds)
        self.rest = rest
        Task { await RestNotifier.schedule(endsAt: rest.endsAt, exerciseName: rest.exerciseName) }
        Task { await showActivity(rest) }
    }

    /// Dismisses the countdown, finished or not.
    func skip() {
        rest = nil
        RestNotifier.cancel()
        Task { await endActivity() }
    }

    /// The workout is over: nothing left to rest for.
    func finishWorkout() { skip() }

    var isDone: Bool { rest.map { $0.endsAt <= .now } ?? true }

    // MARK: Live Activity

    private func showActivity(_ rest: Rest) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let state = RestActivityAttributes.ContentState(exerciseName: rest.exerciseName, startedAt: rest.startedAt, endsAt: rest.endsAt)
        await RestActivityController.show(dayName: dayName, state: state)
    }

    private func endActivity() async {
        await RestActivityController.end()
    }
}

/// Talks to ActivityKit off the main actor: `Activity` is not Sendable, so it is looked up
/// and used within one call rather than held by the timer.
nonisolated enum RestActivityController {
    @concurrent static func show(dayName: String, state: RestActivityAttributes.ContentState) async {
        // Stale once the rest is over, which is how the activity knows to say "Rest done"
        // without the app being awake to tell it.
        let content = ActivityContent(state: state, staleDate: state.endsAt, relevanceScore: 100)
        if let activity = Activity<RestActivityAttributes>.activities.first(where: { $0.activityState == .active }) {
            await activity.update(content)
        } else {
            _ = try? Activity.request(attributes: RestActivityAttributes(dayName: dayName), content: content)
        }
    }

    @concurrent static func end() async {
        for activity in Activity<RestActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
