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
                    Picker("Rep ranges", selection: $settings.repStyle) {
                        ForEach(RepStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.inline).labelsHidden()
                } header: {
                    Text("How you train")
                } footer: {
                    Text(settings.repStyle.summary + " Changeable in Settings, and per exercise.")
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
        Seeder.applyRepStyle(from: .balanced, to: settings.repStyle, context: context)
        settings.hasCompletedOnboarding = true
        context.saveOrLog()
        dismiss()
    }
}
