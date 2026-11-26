import SwiftUI
import WatchKit
import LiftCore

// Watch screens (engine-first; CDO's watch spec will restyle these).
// Ben's rules: tabular numbers, undo instead of confirm, no spinners, haptic
// on target hit (WatchStore.log).

struct WatchRoot: View {
    @Environment(WatchStore.self) private var store
    let frame: WatchFixtures.Frame?
    @State private var page = 0
    @State private var adding = false
    @State private var finishing = false

    private var count: Int { store.live.exercises.count }

    var body: some View {
        NavigationStack {
            if store.live.exercises.isEmpty {
                EmptyLogView(onAdd: { adding = true })
            } else {
                TabView(selection: $page) {
                    ForEach(Array(store.live.exercises.enumerated()), id: \.element.id) { i, ex in
                        ExercisePage(exercise: ex, index: i, count: count,
                                     startCounting: frame?.counting == true && i == page,
                                     go: go, onAdd: { adding = true })
                            .tag(i)
                    }
                    EndPage(onAdd: { adding = true }, onFinish: { finishing = true }, onBack: { go(count - 1) })
                        .tag(count)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
        }
        .overlay(alignment: .bottom) { UndoToast() }
        .sheet(isPresented: $adding) {
            AddExerciseView { ex in
                store.add(ex)
                if let i = store.live.exercises.firstIndex(where: { $0.id == ex.id }) { page = i }
            }
        }
        .fullScreenCover(isPresented: $finishing) {
            FinishSummaryView(onDone: {
                finishing = false
                page = 0
            })
        }
        .onAppear {
            page = frame?.page ?? store.current
            adding = frame?.adding == true
            finishing = frame?.finishing == true
        }
    }

    private func go(_ i: Int) {
        withAnimation { page = max(0, min(count, i)) }
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: Empty

struct EmptyLogView: View {
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(Date().formatted(.dateTime.weekday(.wide))).font(.headline)
                Text("Log what you lift. Lift remembers it for next time.")
                    .font(.footnote).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add exercise", systemImage: "plus", action: onAdd)
                    .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: Exercise page

struct ExercisePage: View {
    @Environment(WatchStore.self) private var store
    let exercise: LiveExercise
    let index: Int
    let count: Int
    var startCounting = false
    let go: (Int) -> Void
    let onAdd: () -> Void

    enum Field: Hashable { case weight, reps }
    @State private var weight = 0.0
    @State private var reps = 0.0
    @FocusState private var focus: Field?
    @State private var counting = false
    @State private var pickingRest = false

    /// Changes when the set to log next changes (after a log, undo or sync).
    private var draftKey: String {
        "\(exercise.doneSets.count)-\(exercise.sets.first { !$0.isDone }?.id.uuidString ?? "")-\(exercise.target.map { "\($0.weight)x\($0.reps)" } ?? "")"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                header
                if let rest = store.live.rest, !rest.isOver(at: Date()) {
                    RestRow(rest: rest)
                } else if store.restUp {
                    Text("Rest's up").font(.footnote.weight(.semibold)).foregroundStyle(.tint)
                }
                Text(exercise.name).font(.headline).lineLimit(2)
                if let last = BeatItText.last(exercise.last, date: exercise.lastDate) {
                    Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(2).monospacedDigit()
                }
                targetLine
                values
                actions
                logged
                Button { pickingRest = true } label: {
                    Label("Rest \(WatchText.rest(exercise.restSeconds))", systemImage: "timer").monospacedDigit()
                }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add exercise", systemImage: "plus", action: onAdd)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous exercise", systemImage: "chevron.left") { go(index - 1) }
                    .disabled(index == 0)
                Spacer()
                Button("Next exercise", systemImage: "chevron.right") { go(index + 1) }
            }
        }
        .sheet(isPresented: $counting) {
            CountView(exercise: exercise, weight: weight) { n in
                reps = Double(n)
                store.log(exercise: exercise, weight: weight, reps: n)
            }
        }
        .sheet(isPresented: $pickingRest) { RestPicker(exercise: exercise) }
        .onAppear {
            load()
            if startCounting { counting = true }
        }
        .onChange(of: draftKey) { _, _ in load() }
    }

    private var header: some View {
        HStack {
            Text("\(index + 1) of \(count)").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if let hr = store.workout.heartRate {
                Label("\(hr)", systemImage: "heart.fill").font(.caption2).foregroundStyle(.red).monospacedDigit()
            }
        }
    }

    @ViewBuilder private var targetLine: some View {
        if let t = exercise.target {
            if exercise.targetHit {
                Label("Target hit", systemImage: "checkmark").font(.footnote.weight(.semibold)).foregroundStyle(.green)
            } else {
                Text("Beat it · \(BeatItText.number(t, bodyweight: exercise.bodyweight))")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tint).monospacedDigit()
            }
        }
    }

    private var values: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if !exercise.bodyweight || weight > 0 {
                field(UnitMath.format(weight), unit: exercise.unit.symbol, .weight)
                    .digitalCrownRotation($weight, from: 0, through: 1500, by: exercise.step, sensitivity: .low,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                Text("×").foregroundStyle(.secondary)
            }
            field("\(Int(reps))", unit: "reps", .reps)
                .digitalCrownRotation($reps, from: 0, through: 100, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
        }
    }

    private func field(_ text: String, unit: String, _ f: Field) -> some View {
        VStack(spacing: 0) {
            Text(text).font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                .minimumScaleFactor(0.6).lineLimit(1)
            Text(unit).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 8).fill(focus == f ? Color.accentColor.opacity(0.25) : Color.white.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(focus == f ? Color.accentColor : .clear, lineWidth: 1.5))
        .focusable(true)
        .focused($focus, equals: f)
        .onTapGesture { focus = f }
        .accessibilityLabel(f == .weight ? "Weight \(text) \(unit)" : "\(text) reps")
        .accessibilityHint("Turn the Digital Crown to change")
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button { counting = true } label: { Image(systemName: "waveform.path.ecg") }
                .accessibilityLabel("Start set and count reps")
                .frame(maxWidth: 52)
            Button {
                store.log(exercise: exercise, weight: weight, reps: Int(reps))
                focus = nil
            } label: {
                Label("Log", systemImage: "checkmark").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(reps < 1)
        }
    }

    @ViewBuilder private var logged: some View {
        let done = exercise.doneSets
        if !done.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(done.enumerated()), id: \.element.id) { i, s in
                    HStack {
                        Text("\(i + 1)").foregroundStyle(.secondary)
                        Text(exercise.bodyweight && s.weight <= 0 ? "\(s.reps) reps" : "\(UnitMath.format(s.weight)) × \(s.reps)")
                        Spacer()
                        if s.source == "watch" { Image(systemName: "applewatch").foregroundStyle(.secondary).font(.caption2) }
                    }
                    .font(.footnote).monospacedDigit()
                }
            }
            .padding(.top, 2)
        }
    }

    private func load() {
        let next = exercise.nextSet
        weight = UnitMath.convert(next.weight, from: next.unit, to: exercise.unit)
        reps = Double(next.reps)
    }
}

// MARK: Rest

struct RestRow: View {
    @Environment(WatchStore.self) private var store
    let rest: RestState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Rest").font(.caption2).foregroundStyle(.secondary)
                    Text(RestCountdown.format(rest.remaining(at: ctx.date)))
                        .font(.system(size: 24, weight: .semibold, design: .rounded)).monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                }
                HStack(spacing: 6) {
                    Button("+30s") { store.addRest(30) }
                    Button("Skip") { store.skipRest() }
                }
                .font(.footnote)
                .controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

struct RestPicker: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: LiveExercise

    var body: some View {
        List(RestChoices.all(including: exercise.restSeconds), id: \.self) { s in
            Button {
                store.setRest(exercise, seconds: s)
                dismiss()
            } label: {
                HStack {
                    Text(WatchText.rest(s)).monospacedDigit()
                    Spacer()
                    if s == exercise.restSeconds { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
        }
        .navigationTitle("Rest")
    }
}

// MARK: Counting

/// Start set → live count from the wrist → Crown corrects → Log.
struct CountView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let exercise: LiveExercise
    let weight: Double
    let onLog: (Int) -> Void

    @State private var offset = 0
    @State private var stopped = false
    @State private var final = 0
    @FocusState private var crown: Bool

    private var shown: Int { max(0, (stopped ? final : store.motion.count) + offset) }

    var body: some View {
        VStack(spacing: 4) {
            Text(stopped ? "Reps" : "Counting reps").font(.footnote).foregroundStyle(.secondary)
            Text("\(shown)")
                .font(.system(size: 64, weight: .bold, design: .rounded)).monospacedDigit()
                .contentTransition(.numericText())
                .focusable(true)
                .focused($crown)
                .digitalCrownRotation(Binding(get: { Double(shown) }, set: { offset = Int($0.rounded()) - (stopped ? final : store.motion.count) }),
                                      from: 0, through: 100, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .accessibilityLabel("\(shown) reps")
            if !store.motion.isAvailable && !stopped {
                Text("Motion isn't available. Turn the Crown to count.").font(.caption2).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if !stopped {
                Text("Turn the Crown to correct").font(.caption2).foregroundStyle(.secondary)
            }
            if stopped {
                Button {
                    onLog(shown)
                    dismiss()
                } label: {
                    Text(exercise.bodyweight && weight <= 0 ? "Log \(shown) reps" : "Log \(UnitMath.format(weight)) × \(shown)").monospacedDigit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(shown < 1)
            } else {
                Button("Done") {
                    final = store.motion.stop()
                    stopped = true
                    WKInterfaceDevice.current().play(.stop)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .onAppear {
            store.startSessionIfNeeded()
            store.motion.start()
            #if DEBUG
            if let n = WatchFixtures.requested?.countedReps { offset = n }
            #endif
            crown = true
            WKInterfaceDevice.current().play(.start)
        }
        .onDisappear { store.motion.stop() }
    }
}

// MARK: Add exercise

struct AddExerciseView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onPick: (LiveExercise) -> Void
    @State private var query = ""

    var body: some View {
        let rows = store.pickerRows(query: query)
        NavigationStack {
            List {
                if !rows.recents.isEmpty {
                    Section("Recents") { ForEach(rows.recents) { row($0) } }
                }
                Section(query.isEmpty ? "All exercises" : "Results") {
                    ForEach(rows.all) { row($0) }
                }
            }
            .searchable(text: $query, prompt: "Search")
            .navigationTitle("Add")
        }
    }

    private func row(_ ex: LiveExercise) -> some View {
        Button {
            onPick(ex)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(ex.name).lineLimit(2)
                if let last = BeatItText.last(ex.last, date: ex.lastDate) {
                    Text(last).font(.caption2).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                }
            }
        }
    }
}

// MARK: End page and finish

struct EndPage: View {
    @Environment(WatchStore.self) private var store
    let onAdd: () -> Void
    let onFinish: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                let t = store.live.targetsBeaten
                if t.of > 0 {
                    (Text("\(t.beaten) of \(t.of)").fontWeight(.semibold) + Text(" targets beaten."))
                        .font(.footnote).monospacedDigit()
                }
                Text("\(store.live.doneSets.count) sets logged").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                Button("Add exercise", systemImage: "plus", action: onAdd)
                Button("Finish", action: onFinish)
                    .buttonStyle(.borderedProminent)
                    .disabled(store.live.doneSets.isEmpty)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous exercise", systemImage: "chevron.left", action: onBack)
                Spacer()
            }
        }
    }
}

/// Finish shows the summary at once and saves after 5 s or on Done; Resume
/// inside that window undoes it (no confirm alert).
struct FinishSummaryView: View {
    @Environment(WatchStore.self) private var store
    let onDone: () -> Void
    @State private var committed = false
    @State private var commitTask: Task<Void, Never>?
    @State private var summary: (beaten: Int, of: Int, sets: Int, minutes: Int)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(store.live.startedAt.formatted(.dateTime.weekday(.wide)))'s workout").font(.headline)
                if let s = summary {
                    if s.of == 0 {
                        Text("First time on these. Next time, they're your numbers to beat.").font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        (Text("\(s.beaten) of \(s.of)").fontWeight(.semibold) + Text(" targets beaten.")).font(.footnote).monospacedDigit()
                    }
                    Text("\(s.minutes) min · \(s.sets) sets").font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Done") {
                    commit()
                    store.startFresh()
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                if !committed {
                    Button("Resume") {
                        commitTask?.cancel()
                        onDone()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            let w = store.live
            let end = w.doneSets.compactMap(\.doneAt).max() ?? Date()
            summary = (w.targetsBeaten.beaten, w.targetsBeaten.of, w.doneSets.count, max(1, Int(end.timeIntervalSince(w.startedAt) / 60)))
            #if DEBUG
            if WatchFixtures.requested != nil { return }
            #endif
            commitTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                commit()
            }
        }
    }

    private func commit() {
        guard !committed else { return }
        committed = true
        commitTask?.cancel()
        store.finish()
        WKInterfaceDevice.current().play(.success)
    }
}

struct UndoToast: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let u = store.undo {
            HStack(spacing: 6) {
                Text(u.text).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                Button("Undo") { store.undoLast() }
                    .font(.caption2.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.thinMaterial))
            .padding(.bottom, 2)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
