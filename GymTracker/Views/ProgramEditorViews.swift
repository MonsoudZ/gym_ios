import SwiftUI
import SwiftData

// MARK: - All programs

struct ProgramsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query private var settingsList: [UserSettings]
    @State private var newName = ""
    @State private var showNew = false
    @State private var programToDelete: Program?

    private var settings: UserSettings? { settingsList.first }

    var body: some View {
        List {
            ForEach(programs, id: \.persistentModelID) { program in
                NavigationLink(value: program) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(program.name)
                            Text("\(program.days.count) days").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if settings?.activeProgram(in: programs)?.id == program.id {
                            Text("Active").font(.caption).foregroundStyle(.tint)
                        }
                    }
                }
            }
            .onDelete { offsets in programToDelete = offsets.first.map { programs[$0] } }
            Section {
                Button("New program", systemImage: "plus") { newName = ""; showNew = true }
            } footer: {
                Text("A new program starts empty. Or open a built-in one and change it.")
            }
        }
        .navigationTitle("Programs")
        // The destination for Program is declared once, on the Settings stack root. Declaring it
        // here as well made SwiftUI push the editor and pop it straight back.
        .alert("New program", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog(Text("Delete \(programToDelete?.name ?? "program")?"),
                            isPresented: Binding(get: { programToDelete != nil }, set: { if !$0 { programToDelete = nil } }),
                            titleVisibility: .visible, presenting: programToDelete) { program in
            Button("Delete program and \(program.days.count) day\(program.days.count == 1 ? "" : "s")", role: .destructive) { delete(program) }
            Button("Keep", role: .cancel) {}
        } message: { program in
            Text(settings?.activeProgram(in: programs)?.id == program.id
                 ? "This is your active program. Past workouts are kept; another program becomes active."
                 : "Past workouts are kept.")
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let program = Program(name: name)
        context.insert(program)
        settings?.activeProgramID = program.id
        context.saveOrLog()
    }

    private func delete(_ program: Program) {
        context.delete(program)
        if settings?.activeProgramID == program.id {
            settings?.activeProgramID = programs.first { $0.id != program.id }?.id
        }
        context.saveOrLog()
    }
}

// MARK: - One program: its days

struct ProgramEditorView: View {
    @Bindable var program: Program
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @State private var newDayName = ""
    @State private var showNewDay = false

    private var settings: UserSettings? { settingsList.first }
    private var isActive: Bool { settings?.activeProgram(in: programs)?.id == program.id }

    var body: some View {
        List {
            Section {
                TextField("Program name", text: $program.name)
                if isActive {
                    Label("Active program", systemImage: "checkmark.circle.fill").foregroundStyle(.tint)
                } else {
                    Button("Make this the active program") {
                        settings?.activeProgramID = program.id
                        context.saveOrLog()
                    }
                }
            }
            Section {
                ForEach(program.orderedDays, id: \.persistentModelID) { day in
                    NavigationLink(value: day) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name)
                            let names = day.exercises(from: exercises).map(\.name)
                            Text(names.isEmpty ? "No exercises yet" : names.joined(separator: ", "))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
                .onDelete(perform: deleteDays)
                .onMove(perform: moveDays)
                Button("Add day", systemImage: "plus") { newDayName = ""; showNewDay = true }
            } header: {
                Text("Days")
            } footer: {
                Text("Days run in this order and repeat. Drag to reorder.")
            }
        }
        .navigationTitle(program.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .navigationDestination(for: ProgramDay.self) { DayEditorView(day: $0) }
        .alert("New day", isPresented: $showNewDay) {
            TextField("e.g. Upper body", text: $newDayName)
            Button("Add") {
                let name = newDayName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let day = program.addDay(named: name)
                context.insert(day)
                context.saveOrLog()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteDays(at offsets: IndexSet) {
        let days = program.orderedDays
        for index in offsets { context.delete(days[index]) }
        program.renumberDays()
        context.saveOrLog()
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        var days = program.orderedDays
        days.move(fromOffsets: source, toOffset: destination)
        for (index, day) in days.enumerated() { day.order = index }
        context.saveOrLog()
    }
}

// MARK: - One day: its exercises

struct DayEditorView: View {
    @Bindable var day: ProgramDay
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]

    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    var body: some View {
        List {
            Section {
                TextField("Day name", text: $day.name)
            }
            Section {
                ForEach(day.exerciseIDs, id: \.self) { exerciseID in
                    if let exercise = exercises.first(where: { $0.id == exerciseID }) {
                        NavigationLink(value: exercise) { ExerciseSummaryRow(exercise: exercise, metric: metric) }
                    } else {
                        Text("Missing exercise").foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in day.exerciseIDs.remove(atOffsets: offsets); context.saveOrLog() }
                .onMove { source, destination in day.exerciseIDs.move(fromOffsets: source, toOffset: destination); context.saveOrLog() }
                NavigationLink {
                    ExercisePickerView(day: day)
                } label: {
                    Label("Add exercises", systemImage: "plus")
                }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Tap an exercise to change its sets, rep range, or plate step. Those settings follow the exercise everywhere it appears.")
            }
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0) }
    }
}

struct ExerciseSummaryRow: View {
    var exercise: Exercise
    var metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text("\(exercise.setCount) × \(exercise.repRangeLow)–\(exercise.repRangeHigh) · +\(Units.weight(exercise.increment, metric: metric))\(musclesText)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
    }

    private var musclesText: String {
        let primary = exercise.muscles.filter { $0.weight >= 1 }.map(\.muscle.displayName)
        return primary.isEmpty ? "" : " · \(primary.joined(separator: ", "))"
    }
}

// MARK: - Pick exercises (library or new)

/// Exercises bucketed by their main muscle, in `Muscle` declaration order, "Other" last.
struct ExerciseGroup {
    var title: String
    var exercises: [Exercise]

    static func grouping(_ exercises: [Exercise]) -> [ExerciseGroup] {
        var byMuscle: [Muscle?: [Exercise]] = [:]
        for exercise in exercises { byMuscle[exercise.primaryMuscle, default: []].append(exercise) }
        var groups = Muscle.allCases.compactMap { muscle -> ExerciseGroup? in
            guard let list = byMuscle[muscle] else { return nil }
            return ExerciseGroup(title: muscle.displayName, exercises: list)
        }
        if let other = byMuscle[Muscle?.none] { groups.append(ExerciseGroup(title: "Other", exercises: other)) }
        return groups
    }
}

/// Pushed from a day. Tapping a row adds it to the day at once and ticks it; tapping again
/// removes it, so several exercises can be added without leaving the screen.
struct ExercisePickerView: View {
    @Bindable var day: ProgramDay

    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]
    @State private var query = ""
    @State private var newExercise: Exercise?
    @State private var showingGuide: Exercise?

    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter { q.isEmpty || $0.name.lowercased().contains(q)
            || $0.muscles.contains { $0.muscle.displayName.lowercased().contains(q) } }
    }

    /// One section per main muscle, in the order `Muscle` declares them (chest, back, shoulders,
    /// arms, legs, abs), so a list of a hundred exercises stays scannable without searching.
    /// Custom exercises with no muscle set come last under "Other".
    private var grouped: [ExerciseGroup] {
        ExerciseGroup.grouping(filtered)
    }

    var body: some View {
        List {
            Section {
                Button("New exercise…", systemImage: "plus.circle") {
                    newExercise = Exercise(name: query.trimmingCharacters(in: .whitespaces), metric: metric)
                }
            }
            ForEach(grouped, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.exercises, id: \.persistentModelID) { exercise in
                        let added = day.exerciseIDs.contains(exercise.id)
                        HStack {
                            Button { toggle(exercise) } label: {
                                HStack {
                                    ExerciseSummaryRow(exercise: exercise, metric: metric)
                                    Spacer()
                                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle")
                                        .foregroundStyle(added ? Color.green : Color.accentColor)
                                        .contentTransition(.symbolEffect(.replace))
                                }
                            }
                            .foregroundStyle(.primary)
                            .accessibilityLabel(added ? "\(exercise.name), added. Double tap to remove." : "Add \(exercise.name)")
                            Button { showingGuide = exercise } label: { Image(systemName: "info.circle") }
                                .accessibilityLabel("How to do \(exercise.name)")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
        .searchable(text: $query, prompt: "Search by name or muscle")
        .navigationTitle(day.exerciseIDs.isEmpty ? "Add to \(day.name)" : "\(day.name) · \(day.exerciseIDs.count) added")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $showingGuide) { ExerciseGuideSheet(exercise: $0) }
        .sheet(item: $newExercise) { exercise in
            NavigationStack {
                ExerciseEditorView(exercise: exercise, isNew: true) {
                    context.insert(exercise)
                    day.exerciseIDs.append(exercise.id)
                    context.saveOrLog()
                }
            }
        }
    }

    private func toggle(_ exercise: Exercise) {
        if let index = day.exerciseIDs.firstIndex(of: exercise.id) {
            day.exerciseIDs.remove(at: index)
        } else {
            day.exerciseIDs.append(exercise.id)
        }
        context.saveOrLog()
    }
}

// MARK: - Edit an exercise's config

struct ExerciseEditorView: View {
    @Bindable var exercise: Exercise
    var isNew = false
    var onSave: (() -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    private var metric: Bool { settingsList.first?.usesMetric ?? false }
    private var unit: String { metric ? "kg" : "lb" }
    private static let rpeCaps: [Double] = [8, 8.5, 9, 9.5, 10]

    /// The name the exercise had when the editor opened, restored if the lifter leaves it on a
    /// name another exercise already has: names are unique in the store, so saving one would
    /// fail and leave the context unable to save anything else.
    @State private var originalName = ""

    private var nameTaken: Bool {
        exercises.contains { $0 !== exercise && $0.name.caseInsensitiveCompare(exercise.name) == .orderedSame }
    }

    private var incrementDisplay: Binding<Double> {
        Binding(get: { Units.display(exercise.increment, metric: metric) },
                set: { exercise.increment = metric ? $0 : Units.kg(fromLb: $0) })
    }

    private var startingDisplay: Binding<Double?> {
        Binding(get: { exercise.startingWeight.map { Units.display($0, metric: metric) } },
                set: { exercise.startingWeight = $0.map { metric ? $0 : Units.kg(fromLb: $0) } })
    }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $exercise.name)
                if nameTaken { Text("An exercise with this name already exists\(isNew ? "." : "; the old name will be kept.")").font(.caption).foregroundStyle(.red) }
            }

            Section {
                TextField("Seat height, grip, what to watch for…", text: Binding(
                    get: { exercise.notes ?? "" },
                    set: { exercise.notes = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }),
                    axis: .vertical)
                    .lineLimit(1...5)
                    .accessibilityLabel("Notes")
            } header: {
                Text("Notes")
            } footer: {
                Text("Shown under the exercise during a workout and on its guide.")
            }

            Section {
                Stepper("Sets: \(exercise.setCount)", value: $exercise.setCount, in: 1...8)
                Stepper("Reps from \(exercise.repRangeLow)", value: $exercise.repRangeLow, in: 1...30)
                    .onChange(of: exercise.repRangeLow) { _, low in if exercise.repRangeHigh < low { exercise.repRangeHigh = low } }
                Stepper("Reps to \(exercise.repRangeHigh)", value: $exercise.repRangeHigh, in: 1...30)
                    .onChange(of: exercise.repRangeHigh) { _, high in if exercise.repRangeLow > high { exercise.repRangeLow = high } }
                Picker("RPE cap", selection: $exercise.rpeCap) {
                    ForEach(Self.rpeCaps, id: \.self) { Text(Units.number($0)).tag($0) }
                }
                Stepper(value: $exercise.restSeconds, in: RestRule.minimumSeconds...RestRule.maximumSeconds, step: RestRule.stepSeconds) {
                    HStack { Text("Rest between sets"); Spacer(); Text(RestRule.label(exercise.restSeconds)).monospacedDigit().foregroundStyle(.secondary) }
                }
            } header: {
                Text("Targets")
            } footer: {
                Text("Progress when every set hits the top of the range at or under the RPE cap. 3–6 reps for strength, 6–12 for size, 12–20 for isolation. Rest 3 min on heavy lifts, 2 min on lighter work; a timer starts when you tick a set done.")
            }

            Section {
                Stepper(value: incrementDisplay, in: metric ? 0.5...20 : 1...50, step: metric ? 0.5 : 0.5) {
                    HStack { Text("Add when progressing"); Spacer(); Text("\(Units.number(incrementDisplay.wrappedValue)) \(unit)").monospacedDigit().foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Starting weight")
                    Spacer()
                    TextField("optional", value: startingDisplay, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                        .font(.body.monospacedDigit())
                    Text(unit).foregroundStyle(.secondary)
                }
            } header: {
                Text("Load")
            } footer: {
                Text("Typical steps: 5 lb for upper-body barbell lifts, 10 lb for lower-body, 2.5 lb for isolation.")
            }

            Section {
                ForEach(Muscle.allCases) { muscle in
                    Picker(muscle.displayName, selection: muscleBinding(muscle)) {
                        Text("—").tag(0.0)
                        Text("Stabiliser").tag(0.25)
                        Text("Secondary").tag(0.5)
                        Text("Primary").tag(1.0)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text("Primary counts as a full hard set toward weekly volume, secondary as half, a stabiliser as a quarter. The muscle map is coloured by these tiers.")
            }
        }
        .navigationTitle(isNew ? "New exercise" : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave?(); dismiss() }
                        .disabled(exercise.name.trimmingCharacters(in: .whitespaces).isEmpty || nameTaken)
                }
            }
        }
        .onAppear { originalName = exercise.name }
        .onDisappear {
            guard !isNew else { return }
            if nameTaken || exercise.name.trimmingCharacters(in: .whitespaces).isEmpty { exercise.name = originalName }
            context.saveOrLog()
        }
    }

    private func muscleBinding(_ muscle: Muscle) -> Binding<Double> {
        Binding(get: { exercise.muscles.first { $0.muscle == muscle }?.weight ?? 0 },
                set: { weight in
                    exercise.muscles.removeAll { $0.muscle == muscle }
                    if weight > 0 { exercise.muscles.append(MuscleWeight(muscle: muscle, weight: weight)) }
                })
    }
}
