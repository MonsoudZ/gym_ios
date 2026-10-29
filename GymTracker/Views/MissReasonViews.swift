import SwiftUI
import SwiftData

/// "Why was it missed?" for one lift. "No reason" is an ordinary miss and counts as one.
struct MissReasonPicker: View {
    @Binding var reason: MissReason?

    var body: some View {
        Picker("Why was it missed?", selection: $reason) {
            Text("No reason").tag(MissReason?.none)
            ForEach(MissReason.allCases, id: \.self) { reason in
                Text(reason.label + (reason.excusesTheMiss ? " · doesn't count" : "")).tag(MissReason?.some(reason))
            }
        }
    }
}

/// Shown once after a workout in which a lift was missed. Each missed lift gets a reason, or
/// none. Sick or injured, out of time and equipment busy leave the session out of that lift's
/// stall count; the others count like any miss (DESIGN.md §2.3).
struct MissReasonsSheet: View {
    @Bindable var session: WorkoutSession
    var missed: [Exercise]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(missed, id: \.persistentModelID) { exercise in
                        MissReasonPicker(reason: Binding(get: { session.missReason(for: exercise) },
                                                         set: { session.setMissReason($0, for: exercise) }))
                            .pickerStyle(.navigationLink)
                            .overlay(alignment: .leading) { EmptyView() }
                            .accessibilityLabel("Why was \(exercise.name) missed?")
                    }
                } header: {
                    Text(missed.count == 1 ? "\(missed[0].name) was missed" : "\(missed.count) lifts were missed")
                } footer: {
                    Text("A reason that was not about the load (sick or injured, out of time, equipment busy) leaves the session out of that lift's stall count. Feeling weak, short sleep and technique count like any miss. You can change this later from the session.")
                }
            }
            .navigationTitle("Missed lifts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        context.saveOrLog()
                        dismiss()
                    }
                }
            }
            .interactiveDismissDisabled()
        }
    }
}

/// The reason under a Missed badge in history, with whether it counted.
struct MissReasonLabel: View {
    var annotation: SessionAnnotation

    var body: some View {
        if let reason = annotation.missReason, annotation.verdict == .failed {
            Label(annotation.isExcused ? "\(reason.label) · not counted" : reason.label, systemImage: "text.bubble")
                .font(.caption.weight(.medium))
                .foregroundStyle(annotation.isExcused ? Color.secondary : Color.red)
        }
    }
}
