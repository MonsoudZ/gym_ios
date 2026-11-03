import SwiftUI
import SwiftData

/// Create or edit one of your own foods: nutrition as the label gives it (per serving or per
/// 100 g), plus what a cup and a piece of it weigh so it can be logged in those. Saved under
/// "Your foods" and offered for logging straight away.
struct NewFoodView: View {
    /// The saved food being edited, or nil for a new one.
    var editing: FoodItem?
    var onSaved: (FoodDraft) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private enum Basis: String, CaseIterable, Identifiable {
        case serving, hundredGrams
        var id: String { rawValue }
        var label: String { self == .serving ? "1 serving" : "100 g" }
    }

    @State private var name = ""
    @State private var brand = ""
    @State private var basis: Basis = .serving
    @State private var servingGrams: Double?
    @State private var servingDescription = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var fibre: Double?
    @State private var gramsPerCup: Double?
    @State private var pieceGrams: Double?
    @State private var pieceName = ""

    private var basisGrams: Double? { basis == .hundredGrams ? 100 : servingGrams }
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (basisGrams ?? 0) > 0
            && (kcal != nil || protein != nil || carbs != nil || fat != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Brand (optional)", text: $brand)
                }
                Section {
                    Picker("Nutrition is per", selection: $basis) {
                        ForEach(Basis.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if basis == .serving {
                        numberField("Serving weight", $servingGrams, unit: "g")
                        TextField("Serving is called (e.g. 1 scoop, 1 bar)", text: $servingDescription)
                    }
                    numberField("Calories", $kcal, unit: "kcal")
                    numberField("Protein", $protein, unit: "g")
                    numberField("Carbs", $carbs, unit: "g")
                    numberField("Fat", $fat, unit: "g")
                    numberField("Fibre", $fibre, unit: "g")
                } header: {
                    Text("Nutrition")
                } footer: {
                    Text(basis == .serving
                         ? "As the label gives it. The serving weight is on the label too, usually in brackets after the serving size."
                         : "Per 100 g, as most labels outside the US give it.")
                }
                Section {
                    numberField("1 cup weighs", $gramsPerCup, unit: "g")
                    HStack {
                        TextField("1 piece is called (e.g. slice, egg)", text: $pieceName)
                        TextField("g", value: $pieceGrams, format: .number)
                            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 70)
                            .accessibilityLabel("Piece weight in grams")
                    }
                } header: {
                    Text("Measures (optional)")
                } footer: {
                    Text("With a cup weight it can be logged in cups, tablespoons and teaspoons; with a piece weight, by the piece. Leave blank to log by weight or serving.")
                }
            }
            .navigationTitle(editing == nil ? "New food" : "Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(!canSave) }
            }
            .onAppear(perform: load)
        }
    }

    private func numberField(_ label: String, _ value: Binding<Double?>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 90)
                .accessibilityLabel(label)
            Text(unit).foregroundStyle(.secondary)
        }
    }

    /// A saved food comes back the way it was entered: per serving when it has one, else per 100 g.
    private func load() {
        guard let editing else { return }
        let d = editing.draft
        name = d.name
        brand = d.brand
        if let serving = d.servingGrams, serving > 0 {
            basis = .serving
            servingGrams = serving
            servingDescription = d.servingDescription ?? ""
            let m = d.macros(forGrams: serving)
            (kcal, protein, carbs, fat, fibre) = (m.kcal.rounded(), m.protein, m.carbs, m.fat, m.fibre)
        } else {
            basis = .hundredGrams
            (kcal, protein, carbs, fat, fibre) = (d.kcalPer100g, d.proteinPer100g, d.carbsPer100g, d.fatPer100g, d.fibrePer100g)
        }
        gramsPerCup = d.gramsPerCup
        pieceGrams = d.pieceGrams
        pieceName = d.pieceName ?? ""
    }

    private func save() {
        guard let basisGrams else { return }
        let p = protein ?? 0, c = carbs ?? 0, f = fat ?? 0
        let draft = FoodDraft.from(
            name: name.trimmingCharacters(in: .whitespaces), brand: brand.trimmingCharacters(in: .whitespaces),
            basisGrams: basisGrams, kcal: kcal ?? (4 * p + 4 * c + 9 * f), protein: p, carbs: c, fat: f, fibre: fibre ?? 0,
            servingGrams: basis == .serving ? servingGrams : nil,
            servingDescription: basis == .serving && !servingDescription.isEmpty ? servingDescription : nil,
            gramsPerCup: (gramsPerCup ?? 0) > 0 ? gramsPerCup : nil,
            pieceGrams: (pieceGrams ?? 0) > 0 ? pieceGrams : nil,
            pieceName: (pieceGrams ?? 0) > 0 ? (pieceName.isEmpty ? "piece" : pieceName) : nil)
        if let editing {
            editing.update(from: draft)
            // A measure cleared in the form is cleared on the food too; update(from:) keeps old values for nil.
            editing.servingGrams = draft.servingGrams
            editing.servingDescription = draft.servingDescription
            editing.gramsPerCup = draft.gramsPerCup
            editing.pieceGrams = draft.pieceGrams
            editing.pieceName = draft.pieceName
        } else {
            context.insert(FoodItem(draft: draft))
        }
        context.saveOrLog()
        dismiss()
        onSaved(draft)
    }
}
