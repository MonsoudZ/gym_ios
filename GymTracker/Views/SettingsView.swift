import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var confirmReset = false

    var body: some View {
        NavigationStack {
            Group {
                if let settings = settingsList.first {
                    SettingsForm(settings: settings, exercises: exercises, programs: programs, confirmReset: $confirmReset)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Settings")
            // Declared once, unconditionally, at the stack root: inside the `if let` it could be
            // torn down on a query update and pop the pushed editor.
            .navigationDestination(for: Program.self) { ProgramEditorView(program: $0) }
        }
    }
}

private struct SettingsForm: View {
    @Bindable var settings: UserSettings
    var exercises: [Exercise]
    var programs: [Program]
    @Binding var confirmReset: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    /// False after the lifter has refused notifications in iOS Settings.
    @State private var notificationsAllowed = true
    /// False on devices without Health, where the heart-rate toggle cannot stay on.
    @State private var healthAvailable = HealthService.isAvailable

    private var reminderTime: Binding<Date> {
        Binding(get: { Calendar.current.date(byAdding: .minute, value: settings.reminderMinutes, to: Calendar.current.startOfDay(for: .now))! },
                set: { date in
                    let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                    settings.reminderMinutes = (c.hour ?? 10) * 60 + (c.minute ?? 0)
                })
    }

    /// Turning a Health feature on asks for that type's permission (types already decided are
    /// not asked again) and pulls what it reads; turning one off clears what it had filled in.
    private func healthToggled(_ on: Bool, revert: @escaping () -> Void) {
        Task {
            if on, !(await HealthService.requestAuthorization(for: settings)) {
                healthAvailable = false
                revert()
            }
            await HealthService.refresh(context: context)
        }
    }

    var body: some View {
        Form {
            Section {
                Picker("Active program", selection: Binding(
                    get: { settings.activeProgram(in: programs)?.id ?? UUID() },
                    set: { settings.activeProgramID = $0 })) {
                    ForEach(programs, id: \.id) { Text($0.name).tag($0.id) }
                }
                if let active = settings.activeProgram(in: programs) {
                    NavigationLink(value: active) {
                        Label("Edit \(active.name)", systemImage: "pencil")
                    }
                }
                NavigationLink { ProgramsListView() } label: {
                    Label("All programs", systemImage: "list.bullet.rectangle")
                }
            } header: {
                Text("Program")
            } footer: {
                Text("Programs are yours to edit: rename days, add or remove exercises, or build one from scratch.")
            }

            Section {
                Picker("Units", selection: $settings.usesMetric) {
                    Text("Pounds, feet and inches").tag(false)
                    Text("Kilograms and centimetres").tag(true)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .onChange(of: settings.usesMetric) { _, metric in
                    Seeder.applyUnits(metric: metric, context: context)
                }
            } header: {
                Text("Units")
            } footer: {
                Text("Weights are stored in kilograms and shown in your unit. Lift increments follow the unit: 5 lb and 10 lb plates, or 2.5 kg and 5 kg.")
            }

            Section("Goal") {
                Picker("Goal", selection: $settings.goal) {
                    ForEach(Goal.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .onChange(of: settings.goal) { _, goal in
                    settings.goalRatePercentPerWeek = goal.defaultRatePercentPerWeek
                    settings.cumulativeAdjustmentKcal = 0
                }
                if settings.goal != .maintain {
                    let range = settings.goal.rateRange
                    VStack(alignment: .leading) {
                        Text("Rate: \(Units.percent(settings.goalRatePercentPerWeek)) of bodyweight per week")
                        Slider(value: $settings.goalRatePercentPerWeek, in: range, step: 0.05)
                        Text(settings.goal == .cut
                             ? "Slower loss keeps more muscle (Garthe 2011). 0.5% is the default."
                             : "Faster than 0.5%/week is mostly fat in trained lifters.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Stepper(value: Binding(get: { settings.proteinPerKg },
                                       set: { settings.proteinPerKgOverride = $0 }),
                        in: 1.2...3.0, step: 0.1) {
                    HStack {
                        Text("Protein")
                        Spacer()
                        Text("\(Units.number(settings.proteinPerKg)) g/kg · \(Units.number(settings.proteinPerKg * settings.assumedWeightKg, maxFraction: 0)) g")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                }
                if settings.proteinPerKgOverride != nil {
                    Button("Use the evidence-based default (\(Units.number(settings.goal.proteinPerKg)) g/kg)") {
                        settings.proteinPerKgOverride = nil
                    }
                    .font(.caption)
                }
            }

            Section {
                if settings.usesMetric {
                    Stepper("Height: \(Units.number(settings.heightCm, maxFraction: 0)) cm", value: $settings.heightCm, in: 120...230, step: 1)
                } else {
                    HeightPickerRow(heightCm: $settings.heightCm)
                }
                Stepper("Age: \(settings.ageYears)", value: $settings.ageYears, in: 14...100)
                Picker("Sex (for the formula)", selection: $settings.isMale) {
                    Text("Male").tag(true)
                    Text("Female").tag(false)
                }
                Picker("Activity outside training", selection: $settings.activityFactor) {
                    Text("Sedentary").tag(1.3)
                    Text("Light").tag(1.5)
                    Text("Moderate").tag(1.7)
                    Text("High").tag(1.9)
                }
                if settings.usesMetric {
                    Stepper("Starting weight: \(Units.number(settings.assumedWeightKg)) kg", value: $settings.assumedWeightKg, in: 35...250, step: 0.5)
                } else {
                    Stepper("Starting weight: \(Units.number(Units.lb(fromKg: settings.assumedWeightKg), maxFraction: 0)) lb",
                            value: Binding(get: { Units.lb(fromKg: settings.assumedWeightKg).rounded() },
                                           set: { settings.assumedWeightKg = Units.kg(fromLb: $0) }),
                            in: 80...550, step: 1)
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("Used only for the provisional calorie estimate before the app has measured your expenditure.")
            }

            Section {
                Toggle("Morning log reminder", isOn: $settings.remindersEnabled)
                if settings.remindersEnabled {
                    DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                }
                if !notificationsAllowed {
                    Button("Notifications are off for GymTracker. Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                    .font(.subheadline)
                }
            } header: {
                Text("Reminders")
            } footer: {
                Text("A nudge at that time on days when today's weight or food is still missing. The calorie target becomes adaptive faster when both are logged every day.")
            }
            .onChange(of: settings.remindersEnabled) { _, on in
                Task {
                    if on, !(await LogReminders.requestAuthorization()) {
                        notificationsAllowed = false
                        settings.remindersEnabled = false
                    } else {
                        notificationsAllowed = true
                        LogReminders.refresh(context: context)
                    }
                }
            }
            .onChange(of: settings.reminderMinutes) { _, _ in LogReminders.refresh(context: context) }

            Section {
                Toggle("Heart rate", isOn: $settings.heartReadinessEnabled)
                Toggle("Sleep", isOn: $settings.sleepFromHealthEnabled)
                Toggle("Bodyweight", isOn: $settings.bodyweightFromHealthEnabled)
                Toggle("Save workouts", isOn: $settings.saveWorkoutsToHealthEnabled)
                if !healthAvailable {
                    Text("Health is not available on this device.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            } header: {
                Text("Health")
            } footer: {
                Text("Heart rate reads HRV and resting heart rate; a morning clearly below your own 7-day baseline makes today 5% lighter, the same as short sleep or soreness, and never heavier. Sleep fills last night's hours on the check-in; what you type wins. Bodyweight fills days you did not weigh in here, from the last \(HealthService.bodyweightLookbackDays) days. Finished workouts are saved as strength training.")
            }
            .disabled(!healthAvailable)
            .onChange(of: settings.heartReadinessEnabled) { _, on in healthToggled(on) { settings.heartReadinessEnabled = false } }
            .onChange(of: settings.sleepFromHealthEnabled) { _, on in healthToggled(on) { settings.sleepFromHealthEnabled = false } }
            .onChange(of: settings.bodyweightFromHealthEnabled) { _, on in healthToggled(on) { settings.bodyweightFromHealthEnabled = false } }
            .onChange(of: settings.saveWorkoutsToHealthEnabled) { _, on in healthToggled(on) { settings.saveWorkoutsToHealthEnabled = false } }

            Section("Data") {
                NavigationLink("Import from Strong or Hevy") { WorkoutImportView() }
                Button("Load demo data (8 weeks)") {
                    DemoData.load(context: context, exercises: exercises, settings: settings)
                }
                Button("Reset everything", role: .destructive) { confirmReset = true }
            }
        }
        .confirmationDialog("Delete all workouts, weights and food?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Seeder.resetAll(context: context) }
        }
    }
}

private struct HeightPickerRow: View {
    @Binding var heightCm: Double

    private var feet: Binding<Int> {
        Binding(get: { Units.feetAndInches(fromCm: heightCm).feet },
                set: { heightCm = Units.cm(feet: $0, inches: Units.feetAndInches(fromCm: heightCm).inches) })
    }
    private var inches: Binding<Int> {
        Binding(get: { Units.feetAndInches(fromCm: heightCm).inches },
                set: { heightCm = Units.cm(feet: Units.feetAndInches(fromCm: heightCm).feet, inches: $0) })
    }

    var body: some View {
        HStack {
            Text("Height")
            Spacer()
            Picker("Feet", selection: feet) {
                ForEach(4...7, id: \.self) { Text("\($0) ft").tag($0) }
            }
            .labelsHidden()
            Picker("Inches", selection: inches) {
                ForEach(0...11, id: \.self) { Text("\($0) in").tag($0) }
            }
            .labelsHidden()
        }
    }
}
