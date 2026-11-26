import SwiftUI
import SwiftData
import LiftCore

/// Finish summary (§3.6).
struct FinishView: View {
    let workout: Workout
    var onDone: () -> Void
    /// "Back to workout": nothing has been saved yet, so this just returns.
    var onBack: () -> Void = {}
    /// Done with nothing logged: handled like Discard (Undo toast, then deleted).
    var onDiscard: (Workout) -> Void = { _ in }
    /// Debug fixture (frame 27) only.
    var startWithSaveAsRoutine = false

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.openURL) private var openURL
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]

    @State private var health: HealthLine = .idle
    @State private var updateRoutine = false
    @State private var changes: [String] = []
    @State private var saveAsRoutine = false
    @State private var routineName = ""
    @State private var noting = false
    @FocusState private var focus: Field?

    enum Field { case routineName, note }
    @State private var bests: [Best] = []

    /// Health is written at Done (nothing is final before that).
    enum HealthLine: Equatable { case idle, ask, willSave, denied, unavailable }

    struct Best: Identifiable {
        let id: UUID
        let exercise: Exercise
        let content: PRBannerContent
    }

    private var routine: Routine? { routines.first { $0.id == workout.routineID } }
    private var isBlank: Bool { workout.routineID == nil }
    private var previousSame: Workout? {
        finished.first { $0 !== workout && $0.startedAt < workout.startedAt && (isBlank ? false : $0.routineID == workout.routineID) }
    }
    private var unit: WeightUnit { settings.unit }
    /// Still open until Done.
    private var isPending: Bool { workout.endedAt == nil }
    private var unlogged: Int { workout.allSets.filter { !$0.isDone }.count }
    /// Counts this workout as finished, since that's what Done will do.
    private var finishedIncludingThis: [Workout] { (isPending ? [workout] : []) + finished.filter { $0 !== workout } }
    private var next: Routine? { LiftStore.nextRoutine(routines: routines, finished: finishedIncludingThis) }
    private var loggedGroups: [(exercise: Exercise, sets: [SetEntry])] {
        workout.groups.compactMap { g in
            let done = g.sets.filter(\.isDone)
            return done.isEmpty ? nil : (g.exercise, done)
        }
    }
    private var defaultRoutineName: String { RoutineNaming.defaultName(for: workout.startedAt) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                Text(eyebrow).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                Text("\(workout.routineName), done.").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
                lede.font(.body).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)
                if isPending, unlogged > 0 {
                    Button("Back to workout", action: onBack)
                        .buttonStyle(TextActionStyle())
                        .frame(minHeight: Theme.Size.hit)
                }

                if !bests.isEmpty {
                    section("New bests") {
                        ForEach(Array(bests.enumerated()), id: \.element.id) { i, best in
                            row {
                                HStack(spacing: 0) {
                                    Text("\(best.exercise.name), ")
                                    if i == 0 { Text(best.content.headline).theBar() } else { Text(best.content.headline) }
                                }
                                .font(.body.monospacedDigit())
                                .padding(.bottom, i == 0 ? Theme.Spacing.s1 : 0)
                            } detail: { short(best.content) }
                        }
                    }
                }

                if isBlank {
                    section("Exercises") {
                        ForEach(loggedGroups, id: \.exercise.id) { g in
                            row { Text(g.exercise.name).font(.body) } detail: {
                                "\(g.sets.count) sets" + (topText(g.sets).map { " · top \($0)" } ?? "")
                            }
                        }
                    }
                } else {
                    section(previousSame == nil ? "This \(workout.routineName)" : "Against last \(workout.routineName)") {
                        row { Text("\(volumeText(workout.volumeKg)) moved").font(.body.monospacedDigit()) } detail: { volumeDetail }
                        if let next {
                            row { Text("\(next.name) is next").font(.body) } detail: {
                                "\(Week.count(finishedIncludingThis.map(\.startedAt), inWeekOf: Date())) of \(settings.daysPerWeek) this week"
                            }
                        }
                    }
                }

                healthLine.padding(.top, Theme.Spacing.s2)

                if noting {
                    TextField("Note for this workout", text: Binding(get: { workout.note }, set: { workout.note = $0 }), axis: .vertical)
                        .focused($focus, equals: .note)
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
                routineSwitches
                Button("Done", action: done).buttonStyle(PrimaryButtonStyle())
                    .padding(.top, Theme.Spacing.s4)
                if !noting {
                    Button("Add a note") { noting = true; focus = .note }.buttonStyle(TextActionStyle())
                }
            }
            .screenMargins()
            .padding(.top, Theme.Spacing.s3)
            .padding(.bottom, Theme.Spacing.s2)
            .background(alignment: .top) {
                // Pinned bar sits clear of the scrolling summary (QA: "3 of 6" clipped).
                Theme.Colors.bgCanvas
                    .overlay(alignment: .top) { Divider().overlay(Theme.Colors.separator) }
                    .ignoresSafeArea(edges: .bottom)
            }
        }
        .onAppear {
            prepare()
            if startWithSaveAsRoutine { saveAsRoutine = true }
        }
    }

    // MARK: Pieces

    /// "Update {Routine}" (AC 30) or "Save as routine" (AC 47), pinned above Done.
    @ViewBuilder private var routineSwitches: some View {
                if !isBlank, !changes.isEmpty, routine != nil {
                    Toggle(isOn: $updateRoutine) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update \(workout.routineName) routine with today's changes").font(.body).foregroundStyle(Theme.Colors.textPrimary)
                            Text(RoutineDiff.summary(changes)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                    .tint(Theme.Colors.success)
                    .frame(minHeight: Theme.Size.groupedRow)
                }

                if isBlank, !workout.allSets.isEmpty {
                    Toggle("Save as routine", isOn: $saveAsRoutine)
                        .tint(Theme.Colors.success)
                        .frame(minHeight: Theme.Size.groupedRow)
                        .onChange(of: saveAsRoutine) { _, on in
                            if on {
                                if routineName.isEmpty { routineName = defaultRoutineName }
                                focus = .routineName
                            } else if focus == .routineName {
                                focus = nil
                            }
                        }
                    if saveAsRoutine {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
                            Text("Routine name").font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                            TextField("Routine name", text: $routineName, prompt: Text(defaultRoutineName))
                                .focused($focus, equals: .routineName)
                                .submitLabel(.done)
                                .onSubmit { focus = nil }
                                .frame(minHeight: Theme.Size.hit)
                                .padding(.horizontal, Theme.Spacing.s3)
                                .background(Theme.Colors.bgSunken, in: .continuous(Theme.Radius.control))
                                .accessibilityLabel("Routine name")
                            Text("Leave it empty to keep “\(defaultRoutineName)”.")
                                .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .padding(.bottom, Theme.Spacing.s2)   // never touches Done
                    }
                }

    }

    private var eyebrow: String {
        let minutes = max(1, Int(((workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt) / 60).rounded()))
        return "\(workout.startedAt.formatted(.dateTime.weekday(.wide))) · \(minutes) min · \(workout.doneSets.count) sets"
    }

    @ViewBuilder private var lede: some View {
        if isPending, unlogged > 0 {
            // AC 45 copy, exactly.
            Text("\(unlogged) set\(unlogged == 1 ? "" : "s") not logged, so \(unlogged == 1 ? "it won't" : "they won't") be saved. ")
                + Text(workout.doneSets.isEmpty ? "Nothing was ticked yet." : "Everything you ticked is.")
        } else {
            baseLede
        }
    }

    private var baseLede: Text {
        if isBlank {
            return Text("\(loggedGroups.count) exercises, ") + Text("\(volumeText(workout.volumeKg))").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                + Text(" moved. Your rotation still has ") + Text(next?.name ?? "Push").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary) + Text(" next.")
        } else if isFirstOfRoutine {
            return Text("First \(workout.routineName) logged. These are your numbers to beat.")
        } else if !bests.isEmpty {
            return Text("\(countWord(bests.count)) new best\(bests.count == 1 ? "" : "s") today") + volumeLede
        } else {
            let (matched, total) = matchedCount
            return Text("Solid. ") + Text("\(matched) of \(total)").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary) + Text(" sets matched or beat last time.")
        }
    }

    private var volumeLede: Text {
        guard let prev = previousSame, prev.volumeKg > 0 else { return Text(".") }
        let pct = Int(((workout.volumeKg - prev.volumeKg) / prev.volumeKg * 100).rounded())
        guard pct != 0 else { return Text(", and the same weight moved as last \(workout.routineName).") }
        return Text(", and ") + Text("\(abs(pct))% \(pct > 0 ? "more" : "less") weight moved").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
            + Text(" than last \(workout.routineName).")
    }

    private var volumeDetail: String {
        guard let prev = previousSame else { return "Your first one, so this is the number to beat" }
        let day = prev.startedAt.formatted(.dateTime.weekday(.wide))
        let word = workout.volumeKg >= prev.volumeKg ? "Up" : "Down"
        return "\(word) from \(volumeNumber(prev.volumeKg)) on \(day)"
    }

    private var isFirstOfRoutine: Bool {
        !finished.contains { $0 !== workout && $0.routineID == workout.routineID }
    }

    private var matchedCount: (Int, Int) {
        let done = workout.doneSets.filter { $0.kind.countsForRecords }
        var matched = 0
        for set in done {
            guard let ex = set.exercise else { continue }
            let last = LiftStore.lastSessionSets(for: ex, excluding: workout)
            let idx = workout.groups.first { $0.exercise === ex }?.sets.firstIndex { $0 === set } ?? 0
            if idx < last.count {
                let p = last[idx]
                if set.snapshot.weightKg >= p.snapshot.weightKg - 0.05 && (set.reps >= p.reps || set.snapshot.weightKg > p.snapshot.weightKg + 0.05) { matched += 1 }
            }
        }
        return (matched, done.count)
    }

    @ViewBuilder private var healthLine: some View {
        switch health {
        case .willSave:
            Label("Saves to Apple Health when you tap Done", systemImage: "heart").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
        case .ask:
            HStack(spacing: Theme.Spacing.s4) {
                Button("Save workouts to Apple Health") { Task { await askHealth() } }.buttonStyle(TextActionStyle())
                Button("Not now") { settings.healthEnabled = false; health = .idle }
                    .buttonStyle(TextActionStyle()).foregroundStyle(Theme.Colors.textSecondary)
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
        changes = workout.routineID == nil ? [] : (routine.map { RoutineDiff.changes(routine: LiftStore.slots(of: $0), workout: LiftStore.slots(of: workout)) } ?? [])
        computeBests()
        switch settings.healthEnabled {
        case nil: health = HealthService.shared.isAvailable ? .ask : .unavailable
        case true?: health = .willSave
        case false?: health = .idle
        }
    }

    private func computeBests() {
        let ids = LiftStore.bestSetIDs(in: workout)
        var out: [Best] = []
        for g in workout.groups {
            let bestSets = g.sets.filter { ids.contains($0.id) }
            let history = LiftStore.history(for: g.exercise).filter { $0.workout !== workout }.map(\.snapshot)
            let candidates: [(SetEntry, [RecordKind])] = bestSets.map { s in (s, PRDetector.newRecords(for: s.snapshot, history: history)) }
            guard let top = candidates.min(by: { rank($0.1) < rank($1.1) }),
                  let content = PRBannerContent.make(kinds: top.1, exercise: g.exercise.name, set: top.0.snapshot, history: history, unit: top.0.unit)
            else { continue }
            out.append(Best(id: top.0.id, exercise: g.exercise, content: content))
        }
        bests = out.sorted { rank([$0.content.kind]) < rank([$1.content.kind]) }
    }

    private func rank(_ kinds: [RecordKind]) -> Int {
        PRBannerContent.top(kinds).flatMap { RecordKind.allCases.firstIndex(of: $0) } ?? 99
    }

    private func short(_ c: PRBannerContent) -> String {
        switch c.kind {
        case .heaviestWeight: return c.why.components(separatedBy: " from ").first ?? c.why
        case .mostReps: return "Most reps at \(c.headline.components(separatedBy: " × ").first ?? "")"
        default: return c.why
        }
    }

    private func askHealth() async {
        let ok = await HealthService.shared.requestAccess()
        settings.healthEnabled = ok
        health = ok ? .willSave : .denied
    }

    /// The only place a workout becomes final.
    private func done() {
        focus = nil
        guard !workout.doneSets.isEmpty else {
            onDiscard(workout)
            return
        }
        // Structure first (planned sets, logged or not), then drop unlogged sets.
        if updateRoutine, let routine {
            if LiftStore.update(routine, from: workout, context: context) {
                toasts.show("\(routine.name) routine updated")
            } else {
                toasts.show("Couldn't update \(routine.name). Today's workout is saved.")
            }
        }
        if isBlank, saveAsRoutine {
            let name = RoutineNaming.resolve(routineName, prefill: defaultRoutineName, existing: routines.map(\.name))
            _ = LiftStore.saveAsRoutine(workout, name: name, context: context)
            toasts.show("\(name) saved as a routine")
        }
        if isPending { LiftStore.finish(workout, context: context) } else { _ = LiftStore.save(context) }
        if settings.healthEnabled == true { HealthSync.save(workout, context: context, toasts: toasts) }
        onDone()
    }

    private func volumeNumber(_ kg: Double) -> String {
        Int(UnitMath.convert(kg, from: .kg, to: unit).rounded()).formatted(.number)
    }

    private func volumeText(_ kg: Double) -> String { "\(volumeNumber(kg)) \(unit.symbol)" }

    private func topText(_ sets: [SetEntry]) -> String? {
        guard let top = sets.filter({ $0.isDone }).max(by: { $0.snapshot.weightKg < $1.snapshot.weightKg }) else { return nil }
        return "\(UnitMath.format(top.weight)) × \(top.reps)"
    }

    private func countWord(_ n: Int) -> String {
        ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"].indices.contains(n) ? ["Zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"][n] : "\(n)"
    }
}

/// Writes a finished workout to Apple Health after Done. Outlives the summary;
/// a failure is reported in a toast and never affects the saved workout.
@MainActor
enum HealthSync {
    static func save(_ workout: Workout, context: ModelContext, toasts: ToastCenter) {
        let start = workout.startedAt, end = workout.endedAt ?? Date(), name = workout.routineName, id = workout.id
        Task { @MainActor in
            switch await HealthService.shared.save(start: start, end: end, routineName: name, workoutID: id) {
            case .saved(let hk):
                workout.healthKitID = hk.uuidString
                _ = LiftStore.save(context)
            case .failed:
                toasts.show("Couldn't save to Apple Health. Your workout is safe in Lift.")
            case .denied:
                toasts.show("Apple Health is off for Lift. Turn it on in Settings.")
            case .unavailable:
                break
            }
        }
    }
}
