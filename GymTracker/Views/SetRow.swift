import SwiftUI
import SwiftData

/// One set during a workout or in the session editor: weight and reps as − / + steppers
/// that snap to the lift's plate increment (hold to repeat), with the number itself tappable
/// to type; an RPE menu that says how many reps were left; and the done tick that starts
/// the rest. Nothing here needs the keyboard, and the keyboard has a Done bar when it does.
struct SetRow: View {
    @Bindable var set: SetEntry
    /// Position among the exercise's working sets, 1-based.
    var displayNumber: Int
    var unit: String
    var metric: Bool
    /// Hidden when correcting a finished session, where ticking a set done means nothing.
    var showsDoneButton = true
    /// Called when the set is ticked done, not when it is un-ticked.
    var onComplete: () -> Void = {}

    private static let rpeValues: [Double] = stride(from: 6.0, through: 10.0, by: 0.5).map { $0 }

    private enum Field: Hashable { case weight, reps }
    @FocusState private var focused: Field?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Bumped on every stepper tap so the haptic fires once per step.
    @State private var steps = 0

    // `self.` is needed: a bare `set` inside a computed property reads as a setter keyword.
    private var isDone: Bool { self.set.completedAt != nil }
    private var canComplete: Bool { self.set.reps > 0 }

    /// Zero means "no weight chosen yet" (an exercise with no history), shown as an empty field.
    private var displayWeight: Binding<Double?> {
        Binding(get: { set.weight > 0 ? Units.display(set.weight, metric: metric) : nil },
                set: { set.weight = max(0, $0.map { metric ? $0 : Units.kg(fromLb: $0) } ?? 0) })
    }

    /// Zero means "not logged yet", shown as an empty field so typing does not append to a 0.
    private var displayReps: Binding<Int?> {
        Binding(get: { set.reps > 0 ? set.reps : nil },
                set: { set.reps = max(0, $0 ?? 0) })
    }

    /// The lift's plate step in display units: 5 lb on a barbell, 2.5 kg, 2 kg on dumbbells.
    private var weightStep: Double {
        let kg = self.set.exercise?.increment ?? 2.5
        let step = metric ? kg : Units.lb(fromKg: kg)
        return (step * 100).rounded() / 100
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                // One line cannot hold two steppers, a menu and a button at these sizes.
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        leading
                        weightStepper
                    }
                    HStack(spacing: 8) {
                        repsStepper
                        rpeMenu
                    }
                }
            } else {
                HStack(spacing: 5) {
                    leading
                    weightStepper
                    repsStepper
                    Spacer(minLength: 0)
                    rpeMenu
                }
            }
        }
        .opacity(showsDoneButton && isDone ? 0.55 : 1)
        .listRowBackground(showsDoneButton && isDone ? Color.green.opacity(0.08) : nil)
        .animation(.snappy, value: isDone)
        .sensoryFeedback(.selection, trigger: steps)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focused != nil {
                    Spacer()
                    Button("Done") { focused = nil }
                }
            }
        }
    }

    /// The set number, which during a workout is also the done button: tap it once the reps
    /// are in and it fills green, dims the row and starts the rest.
    private var leading: some View {
        Group {
            if showsDoneButton {
                doneButton
            } else {
                setNumber.frame(width: 30, height: 30)
            }
        }
    }

    private var setNumber: some View {
        Group {
            if set.isWarmup {
                Image(systemName: "flame").font(.caption).foregroundStyle(.orange)
                    .accessibilityLabel("Warm-up set")
            } else {
                Text("\(displayNumber)").font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.secondary)
                    .accessibilityLabel("Set \(displayNumber)")
            }
        }
    }

    // MARK: Steppers

    private var weightStepper: some View {
        StepField(decrease: { stepWeight(.down) }, increase: { stepWeight(.up) },
                  decreaseLabel: "\(Units.number(weightStep)) \(unit) less",
                  increaseLabel: "\(Units.number(weightStep)) \(unit) more") {
            TextField("—", value: displayWeight, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .focused($focused, equals: .weight)
                .frame(minWidth: 40)
                .accessibilityLabel("Weight in \(unit)")
            Text(unit).font(.caption2).foregroundStyle(.secondary).fixedSize()
        }
    }

    private var repsStepper: some View {
        StepField(decrease: { stepReps(.down) }, increase: { stepReps(.up) },
                  decreaseLabel: "One rep fewer", increaseLabel: "One rep more") {
            TextField("—", value: displayReps, format: .number)
                .keyboardType(.numberPad)
                .focused($focused, equals: .reps)
                .frame(minWidth: 24)
                .accessibilityLabel("Reps")
            Text("reps").font(.caption2).foregroundStyle(.secondary).fixedSize()
        }
    }

    private func stepWeight(_ direction: SetStepRule.Direction) {
        let next = SetStepRule.weight(displayWeight.wrappedValue, step: weightStep, direction: direction, start: startingWeight)
        displayWeight.wrappedValue = next
        steps += 1
    }

    private func stepReps(_ direction: SetStepRule.Direction) {
        displayReps.wrappedValue = SetStepRule.reps(displayReps.wrappedValue, direction: direction, start: startingReps)
        steps += 1
    }

    /// Where + starts from an empty weight: this session's last working set of the lift, else
    /// last session's top set, else one plate step.
    private var startingWeight: Double {
        guard let exercise = self.set.exercise else { return weightStep }
        let thisSession = self.set.session?.sets(for: exercise)
            .filter { $0.persistentModelID != self.set.persistentModelID && !$0.isWarmup && $0.weight > 0 }
        if let last = thisSession?.last { return Units.display(last.weight, metric: metric) }
        if let previous = exercise.sessionResults().last?.sets.filter({ !$0.isWarmup }).map(\.weight).max(), previous > 0 {
            return Units.display(previous, metric: metric)
        }
        return weightStep
    }

    /// Where + starts from empty reps: the set before, else last session's top set, else the
    /// top of the lift's rep range (DESIGN.md §4).
    private var startingReps: Int {
        guard let exercise = self.set.exercise else { return 8 }
        if let previous = self.set.session?.sets(for: exercise)
            .filter({ $0.persistentModelID != self.set.persistentModelID && !$0.isWarmup && $0.reps > 0 }).last {
            return previous.reps
        }
        if let topSet = exercise.sessionResults().last?.sets.filter({ !$0.isWarmup && $0.reps > 0 }).max(by: { $0.weight < $1.weight }) {
            return topSet.reps
        }
        return exercise.repRangeHigh
    }

    // MARK: RPE

    private var rpeMenu: some View {
        Menu {
            ForEach(Self.rpeValues, id: \.self) { value in
                Button {
                    set.rpe = value
                } label: {
                    if set.rpe == value {
                        Label(Units.rpeLabel(value), systemImage: "checkmark")
                    } else {
                        Text(Units.rpeLabel(value))
                    }
                }
            }
            if set.rpe != nil {
                Divider()
                Button("Clear RPE", role: .destructive) { set.rpe = nil }
            }
        } label: {
            HStack(spacing: 2) {
                Text(set.rpe.map { "RPE \(Units.number($0))" } ?? "RPE")
                    .font(.footnote.monospacedDigit())
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(set.rpe == nil ? Color.secondary : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .fixedSize()
        .accessibilityLabel(set.rpe.map { Units.rpeLabel($0) } ?? "RPE not set")
        .accessibilityHint("How hard the set felt, 6 to 10, as reps left in the tank")
    }

    // MARK: Done

    private var doneButton: some View {
        Button {
            toggleDone()
        } label: {
            ZStack {
                if isDone {
                    Circle().fill(Color.green)
                    Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(canComplete ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5)
                    setNumber.foregroundStyle(canComplete ? Color.accentColor : Color.secondary)
                }
            }
            .frame(width: 30, height: 30)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!isDone && !canComplete)
        .accessibilityLabel(isDone ? "Set \(displayNumber) done" : "Mark set \(displayNumber) done")
        .accessibilityHint(isDone ? "Double tap to un-mark" : !canComplete ? "Enter reps first" : set.isWarmup ? "Warm-up, no rest timer" : "Starts the rest timer")
    }

    private func toggleDone() {
        if isDone {
            set.completedAt = nil
        } else {
            set.completedAt = .now
            focused = nil
            onComplete()
        }
    }
}

/// A − value + capsule. The buttons repeat while held and get wide hit areas; the middle is
/// whatever field the caller puts there.
private struct StepField<Content: View>: View {
    var decrease: () -> Void
    var increase: () -> Void
    var decreaseLabel: String
    var increaseLabel: String
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) {
            stepButton("minus", action: decrease, label: decreaseLabel)
            HStack(spacing: 3) { content }
                .multilineTextAlignment(.center)
                .font(.body.monospacedDigit())
                .padding(.horizontal, 2)
            stepButton("plus", action: increase, label: increaseLabel)
        }
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void, label: String) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .frame(width: 28, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .buttonRepeatBehavior(.enabled)
        .foregroundStyle(Color.accentColor)
        .accessibilityLabel(label)
    }
}
