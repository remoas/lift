import SwiftUI
import SwiftData
import LiftCore

/// Quick setup: Welcome → Days → Build Push → Build Pull → Build Legs → Today.
struct SetupFlow: View {
    var onFinish: () -> Void
    /// Debug fixtures open the flow part-way through.
    var startAt: [Step] = []

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Query(sort: \Routine.order) private var routines: [Routine]
    @State private var path: [Step] = []

    enum Step: Hashable { case days, build(Int) }

    var body: some View {
        NavigationStack(path: $path) {
            WelcomeStep { path.append(.days) }
                .navigationDestination(for: Step.self) { step in
                    switch step {
                    case .days:
                        DaysStep { path.append(.build(0)) }
                    case .build(let i):
                        if i < routines.count {
                            let isLast = i == min(routines.count, 3) - 1
                            BuildDayView(routine: routines[i],
                                         context: .setup(step: i + 2, total: 4, nextDay: isLast ? nil : routines[i + 1].name),
                                         onDone: { advance(from: i, isLast: isLast) },
                                         onSkip: { advance(from: i, isLast: isLast) })
                        }
                    }
                }
        }
        .tint(Theme.Colors.accent)
        .onAppear {
            LiftStore.ensureRoutines(context)
            if path.isEmpty, !startAt.isEmpty { path = startAt }
        }
    }

    private func advance(from i: Int, isLast: Bool) {
        if isLast {
            settings.hasOnboarded = true
            onFinish()
        } else {
            path.append(.build(i + 1))
        }
    }
}

private struct WelcomeStep: View {
    var onStart: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
            Spacer()
            Text("Lift").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            VStack(alignment: .leading, spacing: 0) {
                Text("Your split, your")
                HStack(spacing: 0) {
                    Text("lifts").theBar()
                    Text(".")
                }
            }
            .font(Theme.Fonts.display)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.bottom, Theme.Spacing.s2)
            Text("Set up Push, Pull and Legs with the exercises you actually do. About two minutes, and you can change anything later.")
                .font(.body).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Button("Get started", action: onStart).buttonStyle(PrimaryButtonStyle())
        }
        .screenMargins()
        .padding(.bottom, Theme.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.bgCanvas)
    }
}

struct DaysStep: View {
    var onPicked: () -> Void
    var eyebrow: String? = "1 of 4"

    @Environment(AppSettings.self) private var settings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picked: Int?

    var body: some View {
        @Bindable var settings = settings
        VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
            if let eyebrow { Text(eyebrow).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary) }
            Text("How many days a week?").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
            HStack(spacing: Theme.Spacing.s3) {
                ForEach(3...6, id: \.self) { n in
                    let on = (picked ?? settings.daysPerWeek) == n && picked != nil
                    Button {
                        Haptics.step()
                        withAnimation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.springTick) { picked = n }
                        settings.daysPerWeek = n
                        Task {
                            try? await Task.sleep(for: .seconds(0.25))
                            onPicked()
                        }
                    } label: {
                        Text("\(n)")
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(on ? Theme.Colors.bgCanvas : Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 64)
                            .background(on ? Theme.Colors.textPrimary : Theme.Colors.bgSunken, in: .continuous(Theme.Radius.button))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(n) days a week")
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            Text("Tap one to carry on. Push, Pull, Legs in order; 6 runs each twice. Miss a day and the next one just slides.")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: Theme.Spacing.s1) {
                Text("Weights in \(settings.unit.symbol).").font(.body).foregroundStyle(Theme.Colors.textSecondary)
                Menu {
                    Picker("Weights in", selection: $settings.unit) {
                        ForEach(WeightUnit.allCases) { Text($0.symbol).tag($0) }
                    }
                } label: {
                    Text("Change").font(.body.weight(.semibold)).foregroundStyle(Theme.Colors.accent).frame(minHeight: Theme.Size.hit)
                }
            }
            Spacer()
        }
        .screenMargins()
        .padding(.top, Theme.Spacing.s4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Colors.bgCanvas)
    }
}
