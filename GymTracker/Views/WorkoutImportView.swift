import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Data → Import from Strong or Hevy. Pick the export, check how each of its
/// exercise names lands in the library, import. Nothing is written until the last button.
struct WorkoutImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var settingsList: [UserSettings]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]

    @State private var showingPicker = false
    @State private var fileText: String?
    @State private var fileName = ""
    @State private var unit: WeightUnit = .lb
    /// The unit is seeded from Settings once. The Form reappears every time a mapping picker
    /// pops, and re-seeding there threw away the unit the lifter had just chosen.
    @State private var unitSeeded = false
    @State private var parsed: WorkoutImport?
    @State private var mapping: [String: WorkoutImportService.Target] = [:]
    @State private var alreadyImported = 0
    @State private var errorMessage: String?
    @State private var outcome: WorkoutImportService.Outcome?

    private var metric: Bool { settingsList.first?.usesMetric ?? false }

    var body: some View {
        Form {
            if let outcome {
                doneSection(outcome)
            } else {
                howToSection
                if let parsed {
                    fileSection(parsed)
                    exercisesSection(parsed)
                    importSection(parsed)
                }
            }
        }
        .navigationTitle("Import workouts")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !unitSeeded else { return }
            unitSeeded = true
            unit = metric ? .kg : .lb
        }
        .fileImporter(isPresented: $showingPicker, allowedContentTypes: [.commaSeparatedText, .plainText, .text, .data]) { result in
            switch result {
            case .success(let url): load(url)
            case .failure(let error): errorMessage = error.localizedDescription
            }
        }
        .alert("Could not read the file", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var howToSection: some View {
        Section {
            Button(parsed == nil ? "Choose a CSV export" : "Choose a different file", systemImage: "doc.badge.plus") {
                showingPicker = true
            }
        } header: {
            Text("File")
        } footer: {
            Text("Strong: Profile → Settings → Export data. Hevy: Profile → Settings → Export & import data → Export workouts. Both give a CSV with one row per set. Workouts come in as finished sessions, so the Progress tab and personal records include them. Importing the same file twice adds nothing.")
        }
    }

    private func fileSection(_ parsed: WorkoutImport) -> some View {
        Section {
            LabeledContent("Source", value: "\(parsed.source.rawValue) · \(fileName)")
            LabeledContent("Workouts", value: "\(parsed.workouts.count)")
            LabeledContent("Sets", value: "\(parsed.setCount)")
            if let range = parsed.dateRange {
                LabeledContent("Dates", value: "\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted))")
            }
            if alreadyImported > 0 {
                LabeledContent("Already imported", value: "\(alreadyImported)")
            }
            if !parsed.unitFromFile {
                Picker("Weights in the file are in", selection: $unit) {
                    ForEach(WeightUnit.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: unit) { _, _ in reparse() }
            }
        } footer: {
            if !parsed.unitFromFile {
                Text("\(parsed.source.rawValue)'s export does not say which unit it used. Pick the unit the app was set to; weights are stored in kg and shown in your units.")
            } else if parsed.skippedRows > 0 {
                Text("\(parsed.skippedRows) rows without reps (timed or distance work) were left out.")
            }
        }
    }

    private func exercisesSection(_ parsed: WorkoutImport) -> some View {
        Section {
            ForEach(sortedExerciseCounts(parsed), id: \.name) { entry in
                Picker(selection: binding(for: entry.name)) {
                    Text("New exercise “\(entry.name)”").tag(WorkoutImportService.Target.create)
                    Text("Skip these sets").tag(WorkoutImportService.Target.skip)
                    Section("Your exercises") {
                        ForEach(exercises) { exercise in
                            Text(exercise.name).tag(WorkoutImportService.Target.existing(exercise.id))
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                        Text(isUnmatched(entry.name) ? "\(entry.sets) sets · not in the library" : "\(entry.sets) sets")
                            .font(.caption)
                            .foregroundStyle(isUnmatched(entry.name) ? .orange : .secondary)
                    }
                }
                .pickerStyle(.navigationLink)
            }
        } header: {
            Text("Exercises")
        } footer: {
            Text("Each name in the file becomes sets of one of your exercises. Names the app could not match are marked in orange: pick the matching exercise, keep them as a new exercise, or skip them.")
        }
    }

    private func importSection(_ parsed: WorkoutImport) -> some View {
        let toAdd = parsed.workouts.count - alreadyImported
        return Section {
            Button(toAdd > 0 ? "Import \(toAdd) workouts" : "Nothing new to import") { runImport(parsed) }
                .disabled(toAdd <= 0)
        }
    }

    private func doneSection(_ outcome: WorkoutImportService.Outcome) -> some View {
        Section {
            EmptyState("Imported", systemImage: "checkmark.circle",
                       description: summary(outcome)) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: Helpers

    private func summary(_ outcome: WorkoutImportService.Outcome) -> String {
        var parts = ["\(outcome.sessionsAdded) workouts and \(outcome.setsAdded) sets are now in your history."]
        if outcome.sessionsSkipped > 0 { parts.append("\(outcome.sessionsSkipped) were already here.") }
        if !outcome.exercisesCreated.isEmpty {
            parts.append("New exercises: \(outcome.exercisesCreated.joined(separator: ", ")). Set their muscles and rep range from any program day.")
        }
        return parts.joined(separator: " ")
    }

    private func sortedExerciseCounts(_ parsed: WorkoutImport) -> [(name: String, sets: Int)] {
        // Unmatched names first, so what needs a decision is at the top.
        parsed.exerciseCounts.sorted { a, b in
            let ua = isUnmatched(a.name), ub = isUnmatched(b.name)
            return ua != ub ? ua : (a.sets != b.sets ? a.sets > b.sets : a.name < b.name)
        }
    }

    private func isUnmatched(_ name: String) -> Bool {
        if case .create = mapping[name] ?? .create { return true }
        return false
    }

    private func binding(for name: String) -> Binding<WorkoutImportService.Target> {
        Binding(get: { mapping[name] ?? .create }, set: { mapping[name] = $0 })
    }

    private func load(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "The file could not be opened."
            return
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            errorMessage = "The file is not text."
            return
        }
        fileName = url.lastPathComponent
        fileText = text
        reparse(resetMapping: true)
    }

    private func reparse(resetMapping: Bool = false) {
        guard let fileText else { return }
        do {
            let result = try WorkoutImportParser.parse(fileText, assumedUnit: unit)
            parsed = result
            let keys = WorkoutImportService.importedKeys(context: context)
            alreadyImported = result.workouts.filter { keys.contains($0.key) }.count
            if resetMapping || mapping.isEmpty {
                mapping = WorkoutImportService.defaultMapping(for: result.exerciseCounts.map(\.name), exercises: exercises)
            }
        } catch {
            parsed = nil
            errorMessage = error.localizedDescription
        }
    }

    private func runImport(_ parsed: WorkoutImport) {
        outcome = WorkoutImportService.apply(parsed, mapping: mapping, exercises: exercises, metric: metric, context: context)
    }
}
