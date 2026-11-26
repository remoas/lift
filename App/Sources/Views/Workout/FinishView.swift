import SwiftUI
import SwiftData
import LiftCore

/// Finish summary (quick-log §3): targets beaten, volume against the last time
/// you did these same exercises, the Health line, Done.
struct FinishView: View {
    let workout: Workout
    var onDone: () -> Void
    /// "Back to workout": nothing has been saved yet, so this just returns.
    var onBack: () -> Void = {}
    /// Done with nothing logged: nothing is saved and nothing goes to Health.
    var onDiscard: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL

    @State private var health: HealthLine = .idle
    @State private var noting = false
    @FocusState private var noteFocused: Bool
    @State private var beaten: [Beaten] = []
    @State private var targetCount = 0

    /// Health is written at Done (nothing is final before that).
    enum HealthLine: Equatable { case idle, ask, willSave, denied, unavailable }

    struct Beaten: Identifiable {
        /// "Last time 110 × 8 · New best" (QA quick-log 12): New best only for an all-time best.
        var detail: String {
            [lastTop.map { "Last time \($0)" }, isAllTimeBest ? "New best" : nil].compactMap { $0 }.joined(separator: " · ")
        }
        let id: UUID
        let exercise: Exercise
        let best: String
        /// Last session's top set ("110 × 8"), never the target itself.
        let lastTop: String?
        let isAllTimeBest: Bool
    }

    private var unit: WeightUnit { settings.unit }
    /// Still open until Done.
    private var isPending: Bool { workout.endedAt == nil }
    private var unlogged: Int { workout.allSets.filter { !$0.isDone }.count }
    private var loggedGroups: [(exercise: Exercise, sets: [SetEntry])] {
        workout.groups.compactMap { g in
            let done = g.sets.filter(\.isDone)
            return done.isEmpty ? nil : (g.exercise, done)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                Text(eyebrow).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                Text("\(workout.startedAt.formatted(.dateTime.weekday(.wide))), done.").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
                lede.font(.body).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                if isPending, unlogged > 0 {
                    Button("Back to workout", action: onBack)
                        .buttonStyle(TextActionStyle())
                        .frame(minHeight: Theme.Size.hit)
                }

                if !beaten.isEmpty {
                    section("Targets beaten") {
                        ForEach(Array(beaten.enumerated()), id: \.element.id) { i, b in
                            row {
                                HStack(spacing: 0) {
                                    Text("\(b.exercise.name), ")
                                    if i == 0 { Text(b.best).theBar() } else { Text(b.best) }
                                }
                                .font(.body.monospacedDigit())
                                .padding(.bottom, i == 0 ? Theme.Spacing.s1 : 0)
                            } detail: { b.detail }
                        }
                    }
                }

                if !loggedGroups.isEmpty {
                    section("Volume") {
                        row { Text("\(volumeText(workout.volumeKg)) moved").font(.body.monospacedDigit()) } detail: { volumeDetail }
                    }
                }

                healthLine.padding(.top, Theme.Spacing.s2)

                if noting {
                    TextField("Note for this workout", text: Binding(get: { workout.note }, set: { workout.note = $0 }), axis: .vertical)
                        .focused($noteFocused)
                        .frame(minHeight: Theme.Size.hit)
                        .padding(.horizontal, Theme.Spacing.s3)
                        .background(Theme.Colors.bgSunken, in: .continuous(Theme.Radius.control))
                        .padding(.top, Theme.Spacing.s3)
                }
            }
            .screenMargins()
            .padding(.top, Theme.Spacing.s7)
            .padding(.bottom, Theme.Spacing.s6)
        }
        .background(Theme.Colors.bgCanvas)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Button("Done", action: done).buttonStyle(PrimaryButtonStyle())
                if !noting {
                    Button("Add a note") { noting = true; noteFocused = true }.buttonStyle(TextActionStyle(secondary: true))
                }
            }
            .screenMargins()
            .padding(.top, Theme.Spacing.s3)
            .padding(.bottom, Theme.Spacing.s2)
            .background(alignment: .top) {
                Theme.Colors.bgCanvas
                    .overlay(alignment: .top) { Divider().overlay(Theme.Colors.separator) }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear(perform: prepare)
    }

    // MARK: Pieces

    private var eyebrow: String {
        let end = workout.endedAt ?? workout.doneSets.compactMap(\.doneAt).max() ?? workout.startedAt
        let minutes = max(1, Int((end.timeIntervalSince(workout.startedAt) / 60).rounded()))
        return "\(minutes) min · \(workout.doneSets.count) sets"
    }

    @ViewBuilder private var lede: some View {
        if isPending, unlogged > 0 {
            // AC 45 copy, exactly.
            Text("\(unlogged) set\(unlogged == 1 ? "" : "s") not logged, so \(unlogged == 1 ? "it won't" : "they won't") be saved. ")
                + Text(workout.doneSets.isEmpty ? "Nothing was ticked yet." : "Everything you ticked is.")
        } else if targetCount == 0 {
            Text("First time on these. Next time, they're your numbers to beat.")
        } else {
            Text("\(beaten.count) of \(targetCount)").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                + Text(" targets beaten.")
        }
    }

    /// Volume of the last session of each of these same exercises.
    private var previousVolumeKg: Double? {
        var total = 0.0, any = false
        for g in loggedGroups {
            let last = LiftStore.lastSessionSets(for: g.exercise, excluding: workout).filter { $0.kind != .warmup }
            if !last.isEmpty { any = true }
            total += last.reduce(0) { $0 + $1.snapshot.volumeKg }
        }
        return any ? total : nil
    }

    private var volumeDetail: String {
        guard let prev = previousVolumeKg, prev > 0 else { return "First time on these, so this is the number to beat" }
        let word = workout.volumeKg >= prev ? "Up" : "Down"
        return "\(word) from \(volumeNumber(prev)) the last time you did these"
    }

    @ViewBuilder private var healthLine: some View {
        switch health {
        case .willSave:
            Label("Saves to Apple Health when you tap Done", systemImage: "heart").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
        case .ask:
            HStack(spacing: Theme.Spacing.s4) {
                Button("Save workouts to Apple Health") { Task { await askHealth() } }.buttonStyle(TextActionStyle())
                Button("Not now") { settings.healthEnabled = false; health = .idle }
                    .buttonStyle(TextActionStyle(secondary: true))
            }
        case .denied:
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text("Apple Health is off for Lift. Turn it on in Settings.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    .frame(minHeight: Theme.Size.hit, alignment: .leading)
            }
        case .idle, .unavailable:
            EmptyView()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).sectionLabel().padding(.bottom, Theme.Spacing.s2)
            content()
        }
        .padding(.top, Theme.Spacing.section - Theme.Spacing.s3)
    }

    private func row<Title: View>(@ViewBuilder title: () -> Title, detail: () -> String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            title().foregroundStyle(Theme.Colors.textPrimary)
            Text(detail()).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.setRow, alignment: .leading)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.Colors.separator).frame(height: 0.5) }
    }

    // MARK: Logic

    private func prepare() {
        // Gone before the Finish screen lands, never via Rest over (AC 108).
        if !workout.isBackLog { RestActivityController.shared.end() }
        computeBeaten()
        switch settings.healthEnabled {
        case nil: health = HealthService.shared.isAvailable ? .ask : .unavailable
        case true?: health = .willSave
        case false?: health = .idle
        }
    }

    private func computeBeaten() {
        let bestIDs = LiftStore.bestSetIDs(in: workout)
        var out: [Beaten] = []
        var count = 0
        for g in loggedGroups {
            let u = g.exercise.unit(global: unit)
            guard let t = LiftStore.beatIt(for: g.exercise, excluding: workout, unit: u).target else { continue }
            count += 1
            let hits = g.sets.filter { s in
                s.kind != .warmup && Target.isHit(weight: UnitMath.convert(s.weight, from: s.unit, to: u), reps: s.reps, target: t)
            }
            guard let best = hits.max(by: { ($0.snapshot.weightKg, $0.reps) < ($1.snapshot.weightKg, $1.reps) }) else { continue }
            let beat = LiftStore.beatIt(for: g.exercise, excluding: workout, unit: u)
            let top = beat.topIndex.map { beat.last[$0] }
            out.append(Beaten(id: best.id, exercise: g.exercise,
                              best: "\(UnitMath.format(best.weight)) × \(best.reps)",
                              lastTop: top.map { "\(UnitMath.format($0.weight)) × \($0.reps)" },
                              isAllTimeBest: bestIDs.contains(best.id)))
        }
        beaten = out
        targetCount = count
    }

    private func askHealth() async {
        let ok = await HealthService.shared.requestAccess()
        settings.healthEnabled = ok
        health = ok ? .willSave : .denied
    }

    /// The only place a workout becomes final.
    private func done() {
        noteFocused = false
        guard !workout.doneSets.isEmpty else {
            onDiscard(workout)
            return
        }
        if isPending { LiftStore.finish(workout, context: context) } else { _ = LiftStore.save(context) }
        HealthSync.saveIfOwned(workout, healthEnabled: settings.healthEnabled, context: context, toasts: toasts)
        onDone()
    }

    private func volumeNumber(_ kg: Double) -> String {
        Int(UnitMath.convert(kg, from: .kg, to: unit).rounded()).formatted(.number)
    }

    private func volumeText(_ kg: Double) -> String { "\(volumeNumber(kg)) \(unit.symbol)" }
}

/// Writes a finished workout to Apple Health after Done. Outlives the summary;
/// a failure is reported in a toast and never affects the saved workout.
@MainActor
enum HealthSync {
    /// Skips a workout the watch ran a session for: the watch saves that one
    /// (with heart rate), so Health gets it exactly once.
    static func saveIfOwned(_ workout: Workout, healthEnabled: Bool?, context: ModelContext, toasts: ToastCenter?) {
        guard HealthOwnership.phoneShouldSave(healthEnabled: healthEnabled, watchRanSession: workout.device == "Watch",
                                              watchSaveFailed: false, alreadySaved: workout.healthKitID != nil) else { return }
        save(workout, context: context, toasts: toasts)
    }

    static func save(_ workout: Workout, context: ModelContext, toasts: ToastCenter?) {
        let start = workout.startedAt, end = workout.endedAt ?? Date(), name = workout.routineName, id = workout.id
        Task { @MainActor in
            switch await HealthService.shared.save(start: start, end: end, routineName: name, workoutID: id) {
            case .saved(let hk):
                workout.healthKitID = hk.uuidString
                _ = LiftStore.save(context)
            case .failed:
                toasts?.show("Couldn't save to Apple Health. Your workout is safe in Lift.")
            case .denied:
                toasts?.show("Apple Health is off for Lift. Turn it on in Settings.")
            case .unavailable:
                break
            }
        }
    }
}
