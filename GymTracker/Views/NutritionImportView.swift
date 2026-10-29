import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Settings → Data → Import weigh-ins or food: brings a `bodyweight.csv` or `food.csv` from
/// this app's export back into the store. Nothing is written until the last button.
struct NutritionImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var showingPicker = false
    @State private var fileName = ""
    @State private var parsed: NutritionImport?
    @State private var alreadyPresent = 0
    @State private var errorMessage: String?
    @State private var outcome: NutritionImportService.Outcome?

    var body: some View {
        Form {
            if let outcome, let parsed {
                doneSection(outcome, parsed)
            } else {
                howToSection
                if let parsed {
                    fileSection(parsed)
                    importSection(parsed)
                }
            }
        }
        .navigationTitle("Import weigh-ins or food")
        .navigationBarTitleDisplayMode(.inline)
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

    private var howToSection: some View {
        Section {
            Button(parsed == nil ? "Choose bodyweight.csv or food.csv" : "Choose a different file", systemImage: "doc.badge.plus") {
                showingPicker = true
            }
        } header: {
            Text("File")
        } footer: {
            Text("The files Export to CSV writes. A day that already has a weigh-in keeps it; a food entry already here is not added again. Importing the same file twice adds nothing.")
        }
    }

    private func fileSection(_ parsed: NutritionImport) -> some View {
        Section {
            LabeledContent("Contents", value: "\(parsed.kind.rawValue) · \(fileName)")
            LabeledContent("Entries", value: "\(parsed.count)")
            if let range = parsed.dateRange {
                LabeledContent("Dates", value: "\(range.lowerBound.formatted(date: .abbreviated, time: .omitted)) – \(range.upperBound.formatted(date: .abbreviated, time: .omitted))")
            }
            if alreadyPresent > 0 {
                LabeledContent("Already here", value: "\(alreadyPresent)")
            }
        } footer: {
            if parsed.skippedRows > 0 {
                Text("\(parsed.skippedRows) rows without a date or a number were left out.")
            }
        }
    }

    private func importSection(_ parsed: NutritionImport) -> some View {
        let toAdd = parsed.count - alreadyPresent
        return Section {
            Button(toAdd > 0 ? "Import \(toAdd) entries" : "Nothing new to import") {
                outcome = NutritionImportService.apply(parsed, context: context)
            }
            .disabled(toAdd <= 0)
        }
    }

    private func doneSection(_ outcome: NutritionImportService.Outcome, _ parsed: NutritionImport) -> some View {
        Section {
            EmptyState("Imported", systemImage: "checkmark.circle",
                       description: "\(outcome.added) \(parsed.kind.rawValue.lowercased()) entries are now in your history."
                           + (outcome.skipped > 0 ? " \(outcome.skipped) were already here." : "")) {
                Button("Done") { dismiss() }
            }
        }
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
        do {
            let result = try NutritionImportParser.parse(text)
            parsed = result
            alreadyPresent = NutritionImportService.alreadyPresent(result, context: context)
        } catch {
            parsed = nil
            errorMessage = error.localizedDescription
        }
    }
}
