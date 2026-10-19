import SwiftUI
import SwiftData

// MARK: - All programs

struct ProgramsListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @Query private var settingsList: [UserSettings]
    @State private var newName = ""
    @State private var showNew = false

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
            .onDelete(perform: delete)
            Section {
                Button("New program", systemImage: "plus") { newName = ""; showNew = true }
            } footer: {
                Text("A new program starts empty. Or open a built-in one and change it.")
            }
        }
        .navigationTitle("Programs")
        .navigationDestination(for: Program.self) { ProgramEditorView(program: $0) }
        .alert("New program", isPresented: $showNew) {
            TextField("Name", text: $newName)
            Button("Create") { create() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func create() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let program = Program(name: name)
        context.insert(program)
        settings?.activeProgramID = program.id
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let program = programs[index]
            context.delete(program)
            if settings?.activeProgramID == program.id {
                settings?.activeProgramID = programs.first { $0.id != program.id }?.id
            }
        }
        try? context.save()
    }
}

// MARK: - One program: its days

struct ProgramEditorView: View {
    @Bindable var program: Program
    @Environment(\.modelContext) private var context
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Program.createdAt) private var programs: [Program]
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
                        try? context.save()
                    }
                }
            }
            Section {
                ForEach(program.orderedDays, id: \.persistentModelID) { day in
                    NavigationLink(value: day) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.name)
                            Text(day.exerciseNames.isEmpty ? "No exercises yet" : day.exerciseNames.joined(separator: ", "))
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
                try? context.save()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func deleteDays(at offsets: IndexSet) {
        let days = program.orderedDays
        for index in offsets { context.delete(days[index]) }
        program.renumberDays()
        try? context.save()
    }

    private func moveDays(from source: IndexSet, to destination: Int) {
        var days = program.orderedDays
        days.move(fromOffsets: source, toOffset: destination)
        for (index, day) in days.enumerated() { day.order = index }
        try? context.save()
    }
}

// MARK: - One day: its exercises

struct DayEditorView: View {
    @Bindable var day: ProgramDay
    @Environment(\.modelContext) private var context
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]
    @State private var showPicker = false

    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    var body: some View {
        List {
            Section {
                TextField("Day name", text: $day.name)
            }
            Section {
                ForEach(day.exerciseNames, id: \.self) { name in
                    if let exercise = exercises.first(where: { $0.name == name }) {
                        NavigationLink(value: exercise) { ExerciseSummaryRow(exercise: exercise, metric: metric) }
                    } else {
                        Text(name).foregroundStyle(.secondary)
                    }
                }
                .onDelete { offsets in day.exerciseNames.remove(atOffsets: offsets); try? context.save() }
                .onMove { source, destination in day.exerciseNames.move(fromOffsets: source, toOffset: destination); try? context.save() }
                Button("Add exercise", systemImage: "plus") { showPicker = true }
            } header: {
                Text("Exercises")
            } footer: {
                Text("Tap an exercise to change its sets, rep range, or plate step. Those settings follow the exercise everywhere it appears.")
            }
        }
        .navigationTitle(day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .navigationDestination(for: Exercise.self) { ExerciseEditorView(exercise: $0) }
        .sheet(isPresented: $showPicker) {
            ExercisePickerView(excluding: Set(day.exerciseNames)) { exercise in
                day.exerciseNames.append(exercise.name)
                try? context.save()
            }
        }
    }
}

struct ExerciseSummaryRow: View {
    var exercise: Exercise
    var metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
            Text("\(exercise.setCount) × \(exercise.repRangeLow)–\(exercise.repRangeHigh) · +\(Units.weight(exercise.increment, metric: metric))\(musclesText)")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var musclesText: String {
        let primary = exercise.muscles.filter { $0.weight >= 1 }.map(\.muscle.displayName)
        return primary.isEmpty ? "" : " · \(primary.joined(separator: ", "))"
    }
}

// MARK: - Pick an exercise (library or new)

struct ExercisePickerView: View {
    var excluding: Set<String>
    var onPick: (Exercise) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query private var settingsList: [UserSettings]
    @State private var query = ""
    @State private var newExercise: Exercise?

    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    private var filtered: [Exercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return exercises.filter { !excluding.contains($0.name) && (q.isEmpty || $0.name.lowercased().contains(q)
            || $0.muscles.contains { $0.muscle.displayName.lowercased().contains(q) }) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button("New exercise…", systemImage: "plus.circle") {
                        newExercise = Exercise(name: query.trimmingCharacters(in: .whitespaces), metric: metric)
                    }
                }
                Section("Library") {
                    ForEach(filtered, id: \.persistentModelID) { exercise in
                        Button { onPick(exercise); dismiss() } label: { ExerciseSummaryRow(exercise: exercise, metric: metric) }
                            .foregroundStyle(.primary)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search by name or muscle")
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $newExercise) { exercise in
                NavigationStack {
                    ExerciseEditorView(exercise: exercise, isNew: true) {
                        context.insert(exercise)
                        try? context.save()
                        onPick(exercise)
                        dismiss()
                    }
                }
            }
        }
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

    private var nameTaken: Bool {
        isNew && exercises.contains { $0.name.caseInsensitiveCompare(exercise.name) == .orderedSame }
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
                if nameTaken { Text("An exercise with this name already exists.").font(.caption).foregroundStyle(.red) }
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
            } header: {
                Text("Targets")
            } footer: {
                Text("Progress when every set hits the top of the range at or under the RPE cap. 3–6 reps for strength, 6–12 for size, 12–20 for isolation.")
            }

            Section {
                Stepper(value: incrementDisplay, in: metric ? 0.5...20 : 1...50, step: metric ? 0.5 : 0.5) {
                    HStack { Text("Add when progressing"); Spacer(); Text("\(Units.number(incrementDisplay.wrappedValue)) \(unit)").foregroundStyle(.secondary) }
                }
                HStack {
                    Text("Starting weight")
                    Spacer()
                    TextField("optional", value: startingDisplay, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
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
                        Text("Secondary").tag(0.5)
                        Text("Primary").tag(1.0)
                    }
                    .pickerStyle(.menu)
                }
            } header: {
                Text("Muscles")
            } footer: {
                Text("Primary counts as a full hard set toward weekly volume, secondary as half.")
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
        .onDisappear { if !isNew { try? context.save() } }
    }

    private func muscleBinding(_ muscle: Muscle) -> Binding<Double> {
        Binding(get: { exercise.muscles.first { $0.muscle == muscle }?.weight ?? 0 },
                set: { weight in
                    exercise.muscles.removeAll { $0.muscle == muscle }
                    if weight > 0 { exercise.muscles.append(MuscleWeight(muscle: muscle, weight: weight)) }
                })
    }
}
