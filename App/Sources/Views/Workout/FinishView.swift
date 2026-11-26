import SwiftUI
import SwiftData
import LiftCore

/// Finish summary (§3.6).
struct FinishView: View {
    let workout: Workout
    var onDone: () -> Void

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
    @State private var naming = false
    @State private var routineName = ""
    @State private var noting = false
    @State private var bests: [Best] = []

    enum HealthLine: Equatable { case idle, ask, saving, saved, failed, denied, unavailable }

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
    private var next: Routine? { LiftStore.nextRoutine(routines: routines, finished: finished) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                Text(eyebrow).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                Text("\(workout.routineName), done.").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
                lede.font(.body).foregroundStyle(Theme.Colors.textSecondary).fixedSize(horizontal: false, vertical: true)

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
                        ForEach(workout.groups, id: \.exercise.id) { g in
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
                                "\(Week.count(finished.map(\.startedAt), inWeekOf: Date())) of \(settings.daysPerWeek) this week"
                            }
                        }
                    }
                }

                healthLine.padding(.top, Theme.Spacing.s2)

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
                    .padding(.top, Theme.Spacing.s3)
                }
            }
            .screenMargins()
            .padding(.top, Theme.Spacing.s7)
            .padding(.bottom, 160)
        }
        .background(Theme.Colors.bgCanvas)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                Button("Done", action: done).buttonStyle(PrimaryButtonStyle())
                if isBlank {
                    Button("Save as routine") {
                        routineName = "Workout \(workout.startedAt.formatted(.dateTime.day().month(.abbreviated)))"
                        naming = true
                    }
                    .buttonStyle(TextActionStyle())
                } else {
                    Button("Add a note") { noting = true }.buttonStyle(TextActionStyle())
                }
            }
            .screenMargins()
            .padding(.vertical, Theme.Spacing.s2)
            .background(Theme.Colors.bgCanvas)
        }
        .alert("Save as routine", isPresented: $naming) {
            TextField("Name", text: $routineName)
            Button("Save") {
                let name = routineName.trimmingCharacters(in: .whitespaces)
                _ = LiftStore.saveAsRoutine(workout, name: name.isEmpty ? "Workout" : name, context: context)
                toasts.show("\(name.isEmpty ? "Workout" : name) saved as a routine")
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Add a note", isPresented: $noting) {
            TextField("Note", text: Binding(get: { workout.note }, set: { workout.note = $0 }))
            Button("Save") { _ = LiftStore.save(context) }
        }
        .onAppear(perform: prepare)
    }

    // MARK: Pieces

    private var eyebrow: String {
        let minutes = max(1, Int(((workout.endedAt ?? Date()).timeIntervalSince(workout.startedAt) / 60).rounded()))
        return "\(workout.startedAt.formatted(.dateTime.weekday(.wide))) · \(minutes) min · \(workout.doneSets.count) sets"
    }

    @ViewBuilder private var lede: some View {
        if isBlank {
            Text("\(workout.groups.count) exercises, ") + Text("\(volumeText(workout.volumeKg))").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                + Text(" moved. Your rotation still has ") + Text(next?.name ?? "Push").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary) + Text(" next.")
        } else if isFirstOfRoutine {
            Text("First \(workout.routineName) logged. These are your numbers to beat.")
        } else if !bests.isEmpty {
            Text("\(countWord(bests.count)) new best\(bests.count == 1 ? "" : "s") today") + volumeLede
        } else {
            let (matched, total) = matchedCount
            Text("Solid. ") + Text("\(matched) of \(total)").fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary) + Text(" sets matched or beat last time.")
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
        case .saved:
            Label("Saved to Apple Health", systemImage: "checkmark").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.success)
        case .saving:
            Text("Saving to Apple Health…").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
        case .ask:
            HStack(spacing: Theme.Spacing.s4) {
                Button("Save workouts to Apple Health") { Task { await askHealth() } }.buttonStyle(TextActionStyle())
                Button("Not now") { settings.healthEnabled = false; health = .idle }
                    .buttonStyle(TextActionStyle()).foregroundStyle(Theme.Colors.textSecondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 0) {
                Text("Couldn't save to Apple Health. Your workout is safe in Lift.").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.danger)
                Button("Try again") { Task { await saveHealth() } }.buttonStyle(TextActionStyle())
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
        #if DEBUG
        if Fixtures.requested == "14-health-error" {
            changes = []
            computeBests()
            health = .failed
            return
        }
        #endif
        changes = workout.routineID == nil ? [] : (routine.map { RoutineDiff.changes(routine: LiftStore.slots(of: $0), workout: LiftStore.slots(of: workout)) } ?? [])
        computeBests()
        switch settings.healthEnabled {
        case nil: health = HealthService.shared.isAvailable ? .ask : .unavailable
        case true?: Task { await saveHealth() }
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
        if ok { await saveHealth() } else { health = .denied }
    }

    private func saveHealth() async {
        health = .saving
        let result = await HealthService.shared.save(start: workout.startedAt, end: workout.endedAt ?? Date(), routineName: workout.routineName, workoutID: workout.id)
        switch result {
        case .saved(let id):
            workout.healthKitID = id.uuidString
            _ = LiftStore.save(context)
            health = .saved
        case .denied: health = .denied
        case .failed: health = .failed
        case .unavailable: health = .unavailable
        }
    }

    private func done() {
        if updateRoutine, let routine {
            if LiftStore.update(routine, from: workout, context: context) {
                toasts.show("\(routine.name) routine updated")
            } else {
                toasts.show("Couldn't update \(routine.name). Today's workout is saved.")
            }
        }
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
