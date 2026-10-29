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
    @State private var confirmDemo = false
    @State private var exportFiles: ExportFiles?
    @State private var exportError: String?
    @Query(sort: \BodyweightEntry.date) private var weights: [BodyweightEntry]
    /// The trend weight, as the Nutrition tab uses it, so the protein grams here match.
    private var currentWeightKg: Double {
        NutritionEngine.trend(weights.map { DatedValue(date: $0.date, value: $0.kg) }).last?.value ?? settings.assumedWeightKg
    }
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
                    settings.lastAdjustmentDate = .now   // a new goal gets a clean week before its first check
                    settings.proteinPerKgOverride = nil  // and its own protein (2.2 g/kg on a cut), DESIGN.md §3.4
                }
                if settings.goal != .maintain {
                    let range = settings.goal.rateRange
                    VStack(alignment: .leading) {
                        Text("Rate: \(Units.percent(settings.goalRatePercentPerWeek)) of bodyweight per week")
                        Slider(value: $settings.goalRatePercentPerWeek, in: range, step: 0.05)
                            // A changed rate is a changed goal (DESIGN.md §3.3): the first check against it
                            // waits a week, rather than judging last week's trend by the new rate.
                            .onChange(of: settings.goalRatePercentPerWeek) { _, _ in settings.lastAdjustmentDate = .now }
                            .accessibilityLabel("Rate of \(settings.goal.label.lowercased())")
                            .accessibilityValue("\(Units.percent(settings.goalRatePercentPerWeek)) of bodyweight per week")
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
                        Text("\(Units.number(settings.proteinPerKg)) g/kg · \(Units.number(settings.proteinPerKg * currentWeightKg, maxFraction: 0)) g")
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
                    ProfileNumberField("Height", value: $settings.heightCm, unit: "cm", range: 120...230)
                } else {
                    HeightPickerRow(heightCm: $settings.heightCm)
                }
                ProfileNumberField("Age", value: Binding(get: { Double(settings.ageYears) },
                                                         set: { settings.ageYears = Int($0.rounded()) }),
                                   unit: "years", range: 14...100)
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
                    ProfileNumberField("Starting weight", value: $settings.assumedWeightKg, unit: "kg", range: 35...250, fraction: 1)
                } else {
                    ProfileNumberField("Starting weight",
                                       value: Binding(get: { Units.lb(fromKg: settings.assumedWeightKg) },
                                                      set: { settings.assumedWeightKg = Units.kg(fromLb: $0) }),
                                       unit: "lb", range: 80...550)
                }
            } header: {
                Text("Profile")
            } footer: {
                Text("Used only for the provisional calorie estimate before the app has measured your expenditure. Tap a number to type it.")
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
                    // Turning the toggle back off after a refusal re-enters here with `on == false`;
                    // that must not clear the hint that explains the refusal.
                    guard on else { LogReminders.refresh(context: context); return }
                    if await LogReminders.requestAuthorization() {
                        notificationsAllowed = true
                        LogReminders.refresh(context: context)
                    } else {
                        notificationsAllowed = false
                        settings.remindersEnabled = false
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

            Section {
                Button("Export to CSV", systemImage: "square.and.arrow.up") { export() }
                NavigationLink("Import from Strong or Hevy") { WorkoutImportView() }
                NavigationLink("Import weigh-ins or food") { NutritionImportView() }
                Button("Load demo data (8 weeks)") { confirmDemo = true }
                Button("Reset everything", role: .destructive) { confirmReset = true }
            } header: {
                Text("Data")
            } footer: {
                Text("Export writes workouts, weigh-ins, food, readiness and weekly checks as CSV files. The workouts, weigh-in and food files import back into this app, so the export is also a backup.")
            }
        }
        .confirmationDialog("Add eight weeks of made-up workouts, weigh-ins and food? Days you have already logged are kept as they are.",
                            isPresented: $confirmDemo, titleVisibility: .visible) {
            Button("Load demo data") { DemoData.load(context: context, exercises: exercises, settings: settings) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete all workouts, weights and food?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Delete everything", role: .destructive) { Seeder.resetAll(context: context) }
        }
        .sheet(item: $exportFiles) { files in
            ShareSheet(items: files.urls)
        }
        .alert("Export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
    }

    private func export() {
        do {
            let urls = try CSVExport.writeFiles(context: context)
            guard !urls.isEmpty else { exportError = "There is nothing logged yet."; return }
            exportFiles = ExportFiles(urls: urls)
        } catch {
            exportError = error.localizedDescription
        }
    }
}

private struct ExportFiles: Identifiable {
    var urls: [URL]
    var id: String { urls.map(\.path).joined() }
}

/// The system share sheet, for handing the export files to Files, AirDrop or mail.
private struct ShareSheet: UIViewControllerRepresentable {
    var items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A number typed in place with its unit beside it, clamped to `range` when editing ends.
/// Steppers made a height or a bodyweight a long press away from the default; here it is the
/// number and Done.
private struct ProfileNumberField: View {
    var label: String
    @Binding var value: Double
    var unit: String
    var range: ClosedRange<Double>
    var fraction = 0
    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ label: String, value: Binding<Double>, unit: String, range: ClosedRange<Double>, fraction: Int = 0) {
        self.label = label
        _value = value
        self.unit = unit
        self.range = range
        self.fraction = fraction
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, text: $text)
                .keyboardType(fraction > 0 ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(width: 84)
                .focused($focused)
                .accessibilityLabel("\(label) in \(unit)")
            Text(unit).foregroundStyle(.secondary)
        }
        .onAppear { text = formatted(value) }
        .onChange(of: value) { _, newValue in if !focused { text = formatted(newValue) } }
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused {
                    Spacer()
                    Button("Done") { focused = false }
                }
            }
        }
    }

    private func formatted(_ number: Double) -> String { Units.number(number, maxFraction: fraction) }

    private func commit() {
        if let typed = Double(text.replacingOccurrences(of: ",", with: ".")) {
            value = min(max(typed, range.lowerBound), range.upperBound)
        }
        text = formatted(value)
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
