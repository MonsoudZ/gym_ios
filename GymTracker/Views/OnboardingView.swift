import SwiftUI
import SwiftData

/// First launch only: units, goal and starting split, then an optional demo history. Everything
/// here can be changed later in Settings, and the sheet says so.
struct OnboardingView: View {
    @Bindable var settings: UserSettings
    var programs: [Program]
    var exercises: [Exercise]
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var loadDemo = false

    private var builtIns: [Program] {
        BuiltInPrograms.all.compactMap { builtIn in programs.first { $0.name == builtIn.name } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Three questions, then you are on the Today screen. All of this can be changed in Settings.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Units") {
                    Picker("Units", selection: $settings.usesMetric) {
                        Text("Pounds, feet and inches").tag(false)
                        Text("Kilograms and centimetres").tag(true)
                    }
                    .pickerStyle(.inline).labelsHidden()
                }
                Section {
                    Picker("Goal", selection: $settings.goal) {
                        ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: settings.goal) { _, goal in
                        settings.goalRatePercentPerWeek = goal.defaultRatePercentPerWeek
                    }
                } header: {
                    Text("Goal")
                } footer: {
                    Text(goalFooter)
                }
                Section {
                    ForEach(builtIns, id: \.id) { program in
                        Button {
                            settings.activeProgramID = program.id
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(program.name)
                                    Text(splitSummary(program)).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if settings.activeProgram(in: programs)?.id == program.id {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                } header: {
                    Text("Starting split")
                } footer: {
                    Text("Every split hits each muscle at least twice a week. You can edit the days and exercises, or build your own, later.")
                }
                Section {
                    Toggle("Load 8 weeks of demo history", isOn: $loadDemo)
                } footer: {
                    Text("Fills every screen with plausible lifts, weigh-ins and meals so you can see how the app reads. Reset everything in Settings when you want a clean start.")
                }
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { finish() }
                }
            }
            .interactiveDismissDisabled()
        }
    }

    private var goalFooter: String {
        switch settings.goal {
        case .cut: "Lose about 0.5% of bodyweight a week; protein 2.2 g/kg. Slower loss keeps more muscle."
        case .maintain: "Hold weight while lifts go up; protein 1.8 g/kg."
        case .leanGain: "Gain about 0.25% of bodyweight a week; protein 1.8 g/kg. Faster than 0.5% is mostly fat."
        }
    }

    private func splitSummary(_ program: Program) -> String {
        let days = program.orderedDays
        return "\(days.count) days: " + days.map(\.name).joined(separator: ", ")
    }

    private func finish() {
        Seeder.applyUnits(metric: settings.usesMetric, context: context)
        if loadDemo {
            DemoData.load(context: context, exercises: exercises, settings: settings)
        }
        settings.hasCompletedOnboarding = true
        context.saveOrLog()
        dismiss()
    }
}
