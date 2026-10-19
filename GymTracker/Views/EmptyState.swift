import SwiftUI

/// The one "nothing here yet" row for every tab: what is missing, why, and the single thing to do.
struct EmptyState<Action: View>: View {
    var title: String
    var systemImage: String
    var description: String
    @ViewBuilder var action: Action

    init(_ title: String, systemImage: String, description: String, @ViewBuilder action: () -> Action) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.action = action()
    }

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            action.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
    }
}

extension EmptyState where Action == EmptyView {
    init(_ title: String, systemImage: String, description: String) {
        self.init(title, systemImage: systemImage, description: description) { EmptyView() }
    }
}

/// The tabs, so an empty state on one tab can send the lifter to the one where the action lives.
enum AppTab: Hashable {
    case today, progress, nutrition, settings
}

extension EnvironmentValues {
    @Entry var switchTab: (AppTab) -> Void = { _ in }
}

/// "↑ Progressed": the verdict's word and symbol together, coloured as a bonus, never as the only cue.
struct VerdictBadge: View {
    var verdict: Verdict
    var font: Font = .caption

    private var color: Color {
        switch verdict {
        case .progressed: .green
        case .failed: .red
        case .held, .incomplete: .secondary
        }
    }

    var body: some View {
        Label(verdict.label, systemImage: verdict.systemImage)
            .font(font.weight(.medium))
            .foregroundStyle(color)
            .labelStyle(.titleAndIcon)
            .accessibilityLabel(verdict.label)
    }
}
