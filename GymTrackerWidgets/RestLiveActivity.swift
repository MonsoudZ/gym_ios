import ActivityKit
import SwiftUI
import WidgetKit

/// The rest countdown on the lock screen and in the Dynamic Island, with the same +30 s and
/// Skip controls as the in-app bar. The activity goes stale at the end of the rest, and the
/// stale view says so until the next set is ticked or the workout is finished.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            RestLockScreenView(dayName: context.attributes.dayName, state: context.state, isDone: context.isStale || context.state.isDone)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.85))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let done = context.isStale || context.state.isDone
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(done ? "Rest done" : "Resting").font(.headline)
                        Text(done ? "Next set of \(context.state.exerciseName)" : "After \(context.state.exerciseName)")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context.state, done: done)
                        .font(.title2.weight(.semibold).monospacedDigit())
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 10) {
                        if !done {
                            Button(intent: AddRestTimeIntent()) { Label("+30 s", systemImage: "plus") }
                                .tint(.secondary)
                        }
                        Button(intent: SkipRestIntent()) {
                            Label(done ? "Go" : "Skip", systemImage: done ? "play.fill" : "forward.end.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(done ? .green : .accentColor)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 4)
                }
            } compactLeading: {
                Image(systemName: done ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(done ? .green : WidgetTheme.accent)
            } compactTrailing: {
                countdown(context.state, done: done)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: done ? "checkmark.circle.fill" : "timer")
                    .foregroundStyle(done ? .green : WidgetTheme.accent)
            }
            .widgetURL(WidgetLink.today)
        }
    }

    @ViewBuilder private func countdown(_ state: RestActivityAttributes.ContentState, done: Bool) -> some View {
        if done {
            Text("Done")
        } else {
            Text(timerInterval: state.startedAt...state.endsAt, countsDown: true)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct RestLockScreenView: View {
    var dayName: String
    var state: RestActivityAttributes.ContentState
    var isDone: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDone ? "Rest done" : "Resting").font(.headline)
                    Text(isDone ? "Next set of \(state.exerciseName)." : "After \(state.exerciseName) · \(dayName)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if isDone {
                    Image(systemName: "checkmark.circle.fill").font(.title).foregroundStyle(.green)
                } else {
                    Text(timerInterval: state.startedAt...state.endsAt, countsDown: true)
                        .font(.system(.title, design: .rounded).weight(.semibold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: 90)
                }
            }
            if !isDone {
                ProgressView(timerInterval: state.startedAt...state.endsAt, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(WidgetTheme.accent)
            }
            HStack(spacing: 10) {
                if !isDone {
                    Button(intent: AddRestTimeIntent()) { Label("+30 s", systemImage: "plus").frame(maxWidth: .infinity) }
                        .tint(.secondary)
                }
                Button(intent: SkipRestIntent()) {
                    Label(isDone ? "Go" : "Skip", systemImage: isDone ? "play.fill" : "forward.end.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(isDone ? .green : WidgetTheme.accent)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
    }
}
