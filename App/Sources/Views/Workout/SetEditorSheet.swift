import SwiftUI
import LiftCore

/// Set editor: −/+ steppers at the plate step, keypad on tap, no dials.
/// Edits apply live, so swiping the sheet away keeps them without logging.
struct SetEditorSheet: View {
    @Bindable var entry: SetEntry
    let title: String
    let lastTime: String?
    var onLog: () -> Void

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 56
    @FocusState private var focus: Field?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var weightText = ""
    @State private var repsText = ""

    enum Field { case weight, reps }

    private var exercise: Exercise? { entry.exercise }
    private var step: Double { exercise?.step(for: entry.unit) ?? entry.unit.defaultStep }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            // Title gets the full width; kg|lb sits on the Weight row (QA quick-log 20).
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Fonts.title).foregroundStyle(Theme.Colors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lastTime.map { "Last time \($0)" } ?? "First time")
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }

            HStack(spacing: Theme.Spacing.s3) {
                Text("Weight").sectionLabel()
                Spacer()
                Menu {
                    Picker("Set type", selection: $entry.kindRaw) {
                        ForEach(SetKind.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } label: {
                    Text("\(entry.kind.label) set ▾").font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                        .frame(minHeight: Theme.Size.hit)
                }
                Picker("Unit", selection: unitBinding) {
                    ForEach(WeightUnit.allCases) { Text($0.symbol).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 96)
                .accessibilityLabel("Unit for \(exercise?.name ?? "this exercise")")
            }

            HStack {
                StepperCircle(symbol: "minus", label: "Less weight") { adjustWeight(-step) }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s1) {
                    TextField("0", text: $weightText)
                        .keyboardType(.decimalPad)
                        .focused($focus, equals: .weight)
                        .font(Theme.Fonts.numeralHero(heroSize))
                        .multilineTextAlignment(.center)
                        .fixedSize()
                        .theBar()
                        .onChange(of: weightText) { _, new in
                            if let v = Double(new.replacingOccurrences(of: ",", with: ".")), v >= 0 { entry.weight = v }
                        }
                    Text(entry.unit.symbol).font(.title3).foregroundStyle(Theme.Colors.textSecondary)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Weight, \(UnitMath.format(entry.weight)) \(entry.unit == .lb ? "pounds" : "kilograms")")
                .accessibilityAdjustableAction { dir in adjustWeight(dir == .increment ? step : -step) }
                Spacer()
                StepperCircle(symbol: "plus", label: "More weight") { adjustWeight(step) }
            }

            if exercise?.equipment.usesPlates == true, entry.weight > 0 {
                Text(WeightText.plateLine(target: entry.weight, plates: settings.plates(for: entry.unit)))
                    .font(Theme.Fonts.secondary)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
            }

            Text("Reps").sectionLabel()
            HStack {
                StepperCircle(symbol: "minus", label: "Fewer reps") { adjustReps(-1) }
                Spacer()
                TextField("0", text: $repsText)
                    .keyboardType(.numberPad)
                    .focused($focus, equals: .reps)
                    .font(Theme.Fonts.numeralHero(heroSize))
                    .multilineTextAlignment(.center)
                    .fixedSize()
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .onChange(of: repsText) { _, new in if let v = Int(new), v >= 0 { entry.reps = v } }
                    .accessibilityLabel("Reps, \(entry.reps)")
                    .accessibilityAdjustableAction { dir in adjustReps(dir == .increment ? 1 : -1) }
                Spacer()
                StepperCircle(symbol: "plus", label: "More reps") { adjustReps(1) }
            }

            if exercise != nil, entry.kind != .warmup {
                HStack {
                    Text("Rest for \(exercise?.name ?? "this exercise")").font(Theme.Fonts.body).foregroundStyle(Theme.Colors.textPrimary)
                    Spacer()
                    Picker("Rest for \(exercise?.name ?? "this exercise")", selection: restBinding) {
                        ForEach(RestChoices.all(including: restBinding.wrappedValue), id: \.self) {
                            Text(RestCountdown.format(TimeInterval($0))).tag($0)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(Theme.Fonts.bodyNumber)
                }
                .frame(minHeight: Theme.Size.hit)
            }

            Spacer(minLength: 0)
            Button(entry.isDone ? "Save set" : "Log set") {
                focus = nil
                onLog()
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(entry.reps <= 0)
        }
        .padding(.horizontal, Theme.Spacing.s5)
        .padding(.top, Theme.Spacing.s6)
        .padding(.bottom, Theme.Spacing.s4)
        .background(Theme.Colors.bgRaised)
        // Tall enough for title, units, both steppers, rest and Log set (QA 05).
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.height(680), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.Colors.bgRaised)
        .onAppear {
            syncTexts()
            if entry.needsWeight { focus = .weight }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focus = nil }
            }
        }
    }

    /// Rest is the exercise's own: changing it here updates the exercise and
    /// this workout's unlogged sets of it, never other exercises.
    private var restBinding: Binding<Int> {
        Binding(get: { exercise?.restSec ?? entry.restSeconds }, set: { v in
            exercise?.restSec = v
            entry.restSeconds = v
            for s in entry.workout?.allSets ?? [] where s.exercise === exercise && !s.isDone && s.kind != .warmup {
                s.restSeconds = v
            }
        })
    }

    private var unitBinding: Binding<WeightUnit> {
        Binding(get: { entry.unit }, set: { newUnit in
            guard newUnit != entry.unit else { return }
            // Converts the shown value; never rewrites saved sets.
            entry.weight = UnitMath.convertLoadable(entry.weight, from: entry.unit, to: newUnit, step: newUnit.defaultStep)
            entry.unit = newUnit
            exercise?.unitOverride = newUnit == settings.unit ? nil : newUnit
            exercise?.plateStep = nil
            syncTexts()
        })
    }

    private func adjustWeight(_ delta: Double) {
        Haptics.step()
        entry.weight = max(0, UnitMath.round(entry.weight + delta, toStep: min(step, abs(delta))))
        syncTexts()
    }

    private func adjustReps(_ delta: Int) {
        Haptics.step()
        entry.reps = max(0, entry.reps + delta)
        syncTexts()
    }

    private func syncTexts() {
        weightText = entry.weight > 0 ? UnitMath.format(entry.weight) : ""
        repsText = "\(entry.reps)"
    }
}

/// 64 pt circular stepper; holding repeats at 8 Hz after 0.4 s.
struct StepperCircle: View {
    let symbol: String
    let label: String
    var action: () -> Void
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        Image(systemName: symbol)
            .font(.title2.weight(.semibold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(width: Theme.Size.stepper, height: Theme.Size.stepper)
            .background(Theme.Colors.bgSunken, in: Circle())
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .onLongPressGesture(minimumDuration: 0.4, maximumDistance: 30, perform: {}, onPressingChanged: { pressing in
                repeatTask?.cancel()
                guard pressing else { return }
                repeatTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(0.4))
                    while !Task.isCancelled {
                        action()
                        try? await Task.sleep(for: .milliseconds(125))
                    }
                }
            })
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }
}
