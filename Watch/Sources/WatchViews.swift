import SwiftUI
import WatchKit
import LiftCore

// Watch screens to CDO's watch.md (§3) and AC 69–82. Dark only.
// One exercise per vertical page; the last page is Add exercise.

struct WatchRoot: View {
    @Environment(WatchStore.self) private var store
    let frame: WatchFixtures.Frame?
    @State private var page = 0
    @State private var adding = false
    @State private var finishing = false
    @State private var pickingRestFor: LiveExercise?

    private var exercises: [LiveExercise] { store.live.exercises }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    EmptyLogView(onAdd: { adding = true })
                } else {
                    TabView(selection: $page) {
                        ForEach(Array(exercises.enumerated()), id: \.element.id) { i, ex in
                            ExercisePage(exercise: ex, isCurrent: i == (store.live.currentIndex ?? 0),
                                         onFinish: { finishing = true },
                                         onRest: { pickingRestFor = ex })
                                .tag(i)
                        }
                        AddPage(onAdd: { adding = true }).tag(exercises.count)
                    }
                    .tabViewStyle(.verticalPage)
                }
            }
            .navigationDestination(isPresented: $adding) {
                AddExerciseView { added in
                    if let first = added.first, let i = store.live.exercises.firstIndex(where: { $0.id == first }) { page = i }
                }
            }
            .navigationDestination(item: $pickingRestFor) { ex in RestPicker(exercise: ex) }
        }
        .overlay(alignment: .bottom) { ToastBar() }
        .fullScreenCover(isPresented: $finishing) {
            FinishView(onDone: { finishing = false; page = 0 }, onBack: { finishing = false })
        }
        .environment(\.watchDimmed, store.forceDimmed)
        .onAppear {
            page = frame?.page ?? store.current
            adding = frame?.adding == true
            finishing = frame?.finishing == true
            if frame?.restPicker == true { pickingRestFor = store.live.exercises.first }
            store.showPage(store.live.exercises[safe: page])
        }
        .onChange(of: page) { _, i in store.showPage(store.live.exercises[safe: i]) }
    }
}

private struct DimmedKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    /// Always-On (or its w11 preview).
    var watchDimmed: Bool {
        get { self[DimmedKey.self] }
        set { self[DimmedKey.self] = newValue }
    }
}

// MARK: 3.1 Empty

struct EmptyLogView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Date().formatted(.dateTime.weekday(.wide))).font(.title3.weight(.semibold))
            Text("Log what you lift. Lift remembers it for next time.")
                .font(.footnote).foregroundStyle(WatchTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("Add exercise", action: onAdd).buttonStyle(WatchPrimaryStyle())
        }
        .padding(.horizontal, WatchTheme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: 3.2–3.5, 3.8, 3.11 Exercise page

struct ExercisePage: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var aod
    @Environment(\.watchDimmed) private var previewDimmed
    let exercise: LiveExercise
    /// The lift being done: the only page with the bar on its target.
    let isCurrent: Bool
    let onFinish: () -> Void
    let onRest: () -> Void

    enum Field: Hashable { case weight, reps, count }
    @State private var weight = 0.0
    @State private var reps = 0.0
    @FocusState private var focus: Field?
    @State private var showingOptions = false

    private var dimmed: Bool { aod || previewDimmed }
    private var resting: RestState? {
        guard let r = store.live.rest, !r.isOver(at: Date()), isCurrent || r.exercise == exercise.name else { return nil }
        return r
    }

    /// Changes when the set to log next changes (after a log or a sync).
    private var draftKey: String {
        let n = exercise.nextSet
        return "\(exercise.doneSets.count)-\(n.id)-\(n.weight)-\(n.reps)"
    }

    var body: some View {
        Group {
            if let best = store.newBest, best.exerciseID == exercise.id {
                newBestView(best.text)
            } else if let rest = resting {
                RestView(rest: rest, exercise: exercise, onEdit: onRest)
            } else if store.restUpFor == exercise.id {
                RestUpView(exercise: exercise, onLog: log)
            } else {
                logView
            }
        }
        .opacity(dimmed ? 0.6 : 1)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showingOptions = true } label: { Image(systemName: "ellipsis") }
                    .accessibilityLabel("\(exercise.name) options")
            }
            if !store.live.doneSets.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish", action: onFinish)
                        .foregroundStyle(WatchTheme.textPrimary)
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .sheet(isPresented: $showingOptions) {
            List {
                Button("Rest · \(RestChoices.label(exercise.restSeconds))") { showingOptions = false; onRest() }
                    .monospacedDigit()
                Button("Discard workout", role: .destructive) { showingOptions = false; store.discard() }
            }
        }
        .onAppear(perform: load)
        .onChange(of: draftKey) { _, _ in load() }
    }

    // The log state: Last, Beat it with the bar, the value, Log set.
    private var logView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(exercise.name).font(.system(size: WatchTheme.isLarge ? 19 : 17, weight: .semibold)).lineLimit(2)
            if let count = store.liveCount(for: exercise) {
                countingBody(count)
            } else {
                if let last = BeatItText.last(exercise.last, date: exercise.lastDate) {
                    Text(last).font(.caption2).foregroundStyle(WatchTheme.textSecondary).monospacedDigit()
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                if !exercise.countable || !store.motionAvailable {
                    Text("Counting off.").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                }
                targetBlock
            }
            statusLine
            Spacer(minLength: 2)
            if WatchTheme.isLarge {
                Text("Double tap to log.").font(.caption2).foregroundStyle(WatchTheme.textTertiary)
            }
            logButton
        }
        .padding(.horizontal, WatchTheme.inset)
        .padding(.top, WatchTheme.toolbarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var targetBlock: some View {
        if exercise.target == nil {
            // 3.5 First time: no Last, no bar; Crown sets the weight.
            Text("First time. Log what you do.").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
            if weight <= 0 && !exercise.bodyweight && focus != .weight {
                Button { focus = .weight } label: {
                    Text("Add weight").font(WatchTheme.hero(22)).foregroundStyle(WatchTheme.ember)
                }
                .buttonStyle(.plain)
            } else {
                valueRow(bar: false)
            }
            Text("\(Int(reps)) reps · Crown to set").font(.caption2).foregroundStyle(WatchTheme.textSecondary).monospacedDigit()
        } else {
            if exercise.targetHit {
                Label("Target hit", systemImage: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(WatchTheme.ember)
            } else {
                Text("Beat it").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
            }
            valueRow(bar: isCurrent && !exercise.targetHit)
        }
    }

    /// "185 × 9": tap the weight or the reps, then the Crown changes it.
    private func valueRow(bar: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !exercise.bodyweight || weight > 0 {
                Text(UnitMath.format(weight))
                    .focusable(true).focused($focus, equals: .weight)
                    .digitalCrownRotation($weight, from: 0, through: 1500, by: exercise.step, sensitivity: .low,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                    .onTapGesture { focus = .weight }
                    .foregroundStyle(focus == .weight ? WatchTheme.ember : WatchTheme.textPrimary)
                Text(" × ")
            }
            Text("\(Int(reps))\(exercise.bodyweight && weight <= 0 ? " reps" : "")")
                .focusable(true).focused($focus, equals: .reps)
                .digitalCrownRotation($reps, from: 1, through: 100, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .onTapGesture { focus = .reps }
                .foregroundStyle(focus == .reps ? WatchTheme.ember : WatchTheme.textPrimary)
        }
        .font(WatchTheme.hero(24))
        .theBar(bar, dimmed: dimmed)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Beat it, \(UnitMath.format(weight)) \(exercise.unit.symbol) times \(Int(reps))")
        .accessibilityHint("Tap the weight or the reps, then turn the Digital Crown")
    }

    // 3.3 Live count: the bar moves under the estimate; Crown corrects it.
    private func countingBody(_ count: Int) -> some View {
        let target = exercise.target?.reps ?? Int(reps)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(UnitMath.format(weight)) \(exercise.unit.symbol) · Beat \(target)")
                .font(.caption2).foregroundStyle(WatchTheme.textSecondary).monospacedDigit()
            Text("\(count)")
                .font(WatchTheme.hero(48))
                .contentTransition(.numericText())
                .focusable(true)
                .focused($focus, equals: .count)
                .onAppear { focus = .count }
                .digitalCrownRotation(Binding(get: { Double(count) }, set: { store.countOffset = Int($0.rounded()) - store.motion.count }),
                                      from: 0, through: 100, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .theBar(dimmed: dimmed)
                .accessibilityLabel("\(count) reps counted, an estimate")
            Text("of \(target) · Crown to correct").font(.caption2).foregroundStyle(WatchTheme.textSecondary).monospacedDigit()
        }
    }

    @ViewBuilder private var statusLine: some View {
        if !store.phoneReachable {
            Text("On this Watch only.").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
        } else if store.healthOff {
            Text("Apple Health is off. Your sets are safe in Lift.").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logButton: some View {
        Button("Log set") { log() }
            .buttonStyle(WatchPrimaryStyle())
            .modifier(DoubleTapLogs())
    }

    private func newBestView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).font(.system(size: WatchTheme.isLarge ? 19 : 17, weight: .semibold)).lineLimit(2)
            Text("New best").font(.caption2.weight(.semibold)).foregroundStyle(WatchTheme.ember)
            Text(text).font(WatchTheme.hero(30)).theBar(dimmed: dimmed)
            Spacer()
        }
        .padding(.horizontal, WatchTheme.inset)
        .padding(.top, WatchTheme.toolbarClearance)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Never blocked: logs whatever is on screen (the live count if counting).
    private func log() {
        let r = store.liveCount(for: exercise) ?? Int(reps)
        store.log(exercise: exercise, weight: weight, reps: max(r, 1))
        focus = nil
    }

    private func load() {
        let next = exercise.nextSet
        weight = UnitMath.convert(next.weight, from: next.unit, to: exercise.unit)
        reps = Double(max(next.reps, 1))
    }
}

/// Double Tap logs on Series 9 / Ultra 2 and later (watchOS 11 API).
struct DoubleTapLogs: ViewModifier {
    func body(content: Content) -> some View {
        if #available(watchOS 11, *) {
            content.handGestureShortcut(.primaryAction)
        } else {
            content
        }
    }
}

// MARK: 3.8 Rest

struct RestView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.isLuminanceReduced) private var aod
    @Environment(\.watchDimmed) private var previewDimmed
    let rest: RestState
    let exercise: LiveExercise
    let onEdit: () -> Void

    var body: some View {
        let dimmed = aod || previewDimmed
        // Steps once a second (Always-On and Reduce Motion alike).
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let left = rest.remaining(at: ctx.date)
            VStack(spacing: 2) {
                ZStack {
                    Circle().stroke(WatchTheme.separator, lineWidth: 4)
                    Circle()
                        .trim(from: 0, to: rest.countdown.progress(at: ctx.date))
                        .stroke(WatchTheme.ember.opacity(dimmed ? 0.5 : 1), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(RestCountdown.format(left))
                        .font(WatchTheme.hero(30))
                        .foregroundStyle(dimmed ? WatchTheme.textSecondary : WatchTheme.textPrimary)
                        .accessibilityLabel("Rest, \(Int(left.rounded(.up))) seconds left")
                }
                .frame(width: WatchTheme.isLarge ? 92 : 76, height: WatchTheme.isLarge ? 92 : 76)
                .onLongPressGesture(perform: onEdit)
                if let next = rest.next {
                    Text("Next").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                    Text(next).font(.body.weight(.semibold)).monospacedDigit().theBar(dimmed: dimmed)
                }
                if !dimmed {
                    HStack(spacing: 6) {
                        Button("+30s") { store.addRest(30) }.buttonStyle(WatchChipStyle())
                            .accessibilityLabel("30 seconds more, this break only")
                        Button("Skip") { store.skipRest() }.buttonStyle(WatchChipStyle(accent: true))
                    }
                }
            }
            .padding(.horizontal, WatchTheme.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct RestUpView: View {
    @Environment(WatchStore.self) private var store
    let exercise: LiveExercise
    let onLog: () -> Void

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(WatchTheme.separator, lineWidth: 4)
                Text("Rest’s up").font(.body.weight(.semibold))
            }
            .frame(width: WatchTheme.isLarge ? 92 : 76, height: WatchTheme.isLarge ? 92 : 76)
            .onTapGesture { store.dismissRestUp() }
            Text("Next").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
            Text(BeatItText.number(exercise.prefill, bodyweight: exercise.bodyweight)).font(.body.weight(.semibold)).monospacedDigit().theBar()
            Button("Log set", action: onLog).buttonStyle(WatchPrimaryStyle()).modifier(DoubleTapLogs())
        }
        .padding(.horizontal, WatchTheme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: 3.10 Rest picker

struct RestPicker: View {
    @Environment(WatchStore.self) private var store
    let exercise: LiveExercise
    @State private var value = 0

    var body: some View {
        VStack(spacing: 4) {
            Text("\(exercise.name) · 15 s steps").font(.caption2).foregroundStyle(WatchTheme.textSecondary).lineLimit(1)
            Picker("Rest", selection: $value) {
                ForEach(RestChoices.all(including: exercise.restSeconds), id: \.self) { s in
                    Text(RestChoices.label(s)).font(WatchTheme.hero(22)).tag(s)
                }
            }
            .pickerStyle(.wheel)
            .labelsHidden()
            Text("Crown to adjust · Off to 5:00").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
        }
        .navigationTitle("Rest")
        .onAppear { value = exercise.restSeconds }
        .onDisappear { if value != exercise.restSeconds { store.setRest(exercise, seconds: value) } }
    }
}

// MARK: 3.6 Add exercise

struct AddPage: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Add exercise").font(.title3.weight(.semibold))
            Text("Recents first.").font(.footnote).foregroundStyle(WatchTheme.textSecondary)
            Spacer(minLength: 4)
            Button("Add exercise", action: onAdd).buttonStyle(WatchPrimaryStyle())
        }
        .padding(.horizontal, WatchTheme.inset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct AddExerciseView: View {
    @Environment(WatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let onDone: ([UUID]) -> Void
    @State private var query = ""
    @State private var added: [UUID] = []

    var body: some View {
        let rows = store.pickerRows(query: query)
        List {
            if !rows.recents.isEmpty {
                Section("Recents") { ForEach(rows.recents) { row($0, meta: ago($0.lastDate)) } }
            }
            Section("All") { ForEach(rows.all) { row($0, meta: nil) } }
        }
        .searchable(text: $query, prompt: "Search")
        .navigationTitle("Add exercise")
        .toolbar {
            if !added.isEmpty {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone(added); dismiss() }
                }
            }
        }
    }

    private func row(_ ex: LiveExercise, meta: String?) -> some View {
        let isAdded = added.contains(ex.id) || store.live.exercises.contains { $0.id == ex.id }
        return Button {
            guard !isAdded else { return }
            store.add(ex)
            added.append(ex.id)
            WKInterfaceDevice.current().play(.click)
        } label: {
            HStack {
                Text(ex.name).lineLimit(2)
                Spacer(minLength: 4)
                if isAdded {
                    Image(systemName: "checkmark").foregroundStyle(WatchTheme.ember)
                } else if let meta {
                    Text(meta).font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                }
            }
            .frame(minHeight: 44)
        }
    }

    /// "2d ago" within a week, else the weekday.
    private func ago(_ d: Date?) -> String? {
        guard let d else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d), to: Calendar.current.startOfDay(for: Date())).day ?? 0
        if days <= 0 { return "Today" }
        if days < 3 { return "\(days)d ago" }
        return d.formatted(.dateTime.weekday(.abbreviated))
    }
}

// MARK: 3.7 Finish

struct FinishView: View {
    @Environment(WatchStore.self) private var store
    let onDone: () -> Void
    let onBack: () -> Void

    var body: some View {
        let w = store.live
        let t = w.targetsBeaten
        let beaten = w.beaten
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                if t.of == 0 {
                    Text("First time on these. Next time, they’re your numbers to beat.").font(.body.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("\(t.beaten) of \(t.of) targets beaten.").font(.title3.weight(.semibold)).monospacedDigit()
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(beaten.enumerated()), id: \.element.exercise.id) { i, b in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.exercise.name).font(.footnote).lineLimit(1)
                        Text(BeatItText.number(b.best, bodyweight: b.exercise.bodyweight)).font(.footnote.weight(.semibold)).monospacedDigit()
                            .theBar(i == 0)
                    }
                }
                if let v = w.volumeComparison {
                    Text(volumeLine(v, unit: w.unit, lastDate: w.exercises.compactMap(\.lastDate).max()))
                        .font(.caption2).foregroundStyle(WatchTheme.textSecondary).monospacedDigit()
                }
                if w.unloggedCount > 0 {
                    let n = w.unloggedCount
                    Text("\(n) set\(n == 1 ? "" : "s") not logged, so \(n == 1 ? "it won’t" : "they won’t") be saved.")
                        .font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Done") {
                    store.finish()
                    WKInterfaceDevice.current().play(.success)
                    store.startFresh()
                    onDone()
                }
                .buttonStyle(WatchPrimaryStyle())
                if w.unloggedCount > 0 {
                    Button("Back to workout", action: onBack).buttonStyle(.plain).foregroundStyle(WatchTheme.ember)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, WatchTheme.inset)
        }
    }

    private func volumeLine(_ v: (today: Double, last: Double), unit: WeightUnit, lastDate: Date?) -> String {
        let total = "\(Int(v.today.rounded()).formatted(.number)) \(unit.symbol)"
        guard v.last > 0 else { return total }
        let pct = Int(((v.today - v.last) / v.last * 100).rounded())
        let day = lastDate.map { " from \($0.formatted(.dateTime.weekday(.wide)))" } ?? ""
        if pct == 0 { return "\(total) · same as\(day.replacingOccurrences(of: " from", with: ""))" }
        return "\(total) · \(pct > 0 ? "up" : "down") \(abs(pct))%\(day)"
    }
}

// MARK: Toast (3.12): 44 pt bar, raised fill, Undo in Ember

struct ToastBar: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let t = store.toast {
            HStack {
                Text(t.text).font(.footnote).foregroundStyle(WatchTheme.textPrimary).lineLimit(1)
                Spacer(minLength: 4)
                Button("Undo") { store.undoToast() }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.ember)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(WatchTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 4)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
