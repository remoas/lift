import SwiftUI
import WatchKit
import LiftCore

// Watch screens to CDO's watch.md (§3) and AC 69–82, with CDO's watch QA 1
// fixes. Dark only. One exercise per vertical page; the last page is Add.

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
        // Exercise pages show their own toast in place of Log set (QA 1, item 8).
        .overlay(alignment: .bottom) {
            if exercises.isEmpty { ToastBar().padding(.horizontal, WatchTheme.inset).padding(.bottom, WatchTheme.bottomGap) }
        }
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
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text(Date().formatted(.dateTime.weekday(.wide))).watchTitle()
                Text("Log what you lift. Lift remembers it for next time.")
                    .font(.footnote).foregroundStyle(WatchTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, WatchTheme.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinnedBottom { Button("Add exercise", action: onAdd).buttonStyle(WatchPrimaryStyle()) }
    }
}

// MARK: Top-leading chrome (QA 1, item 1)

/// ••• and Finish on the leading edge of the status row, clear of the
/// system time on the trailing edge; hidden on Always-On.
struct PageChrome: View {
    let label: String
    let showFinish: Bool
    let onMore: () -> Void
    let onFinish: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: onMore) {
                Image(systemName: "ellipsis").font(.footnote.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(WatchTheme.raised, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(label) options")
            if showFinish {
                Button(action: onFinish) {
                    Text("Finish").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(WatchTheme.raised, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(WatchTheme.textPrimary)
        .padding(.leading, WatchTheme.isLarge ? 12 : 10)
        .padding(.top, 4)
        .ignoresSafeArea(edges: .top)
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
    /// The field the user tapped; only it can take the Crown (no default focus).
    @State private var active: Field?
    @State private var showingOptions = false
    @State private var idle: Task<Void, Never>?

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
        .overlay(alignment: .topLeading) {
            if !dimmed {
                PageChrome(label: exercise.name, showFinish: !store.live.doneSets.isEmpty,
                           onMore: { showingOptions = true }, onFinish: onFinish)
            }
        }
        .sheet(isPresented: $showingOptions) {
            List {
                Button("Rest · \(RestChoices.label(exercise.restSeconds))") { showingOptions = false; onRest() }
                    .monospacedDigit()
                Button("Discard workout", role: .destructive) { showingOptions = false; store.discard() }
            }
        }
        .onAppear {
            load()
            if store.fixtureFocusWeight && isCurrent { take(.weight) }
        }
        .onChange(of: draftKey) { _, _ in load() }
        .onChange(of: focus) { _, f in
            // Focus lost elsewhere (a swipe, a sheet): hand the Crown back.
            if f == nil, active != nil, !store.isFixture { active = nil }
            armIdle()
        }
        .onChange(of: weight) { _, _ in armIdle() }
        .onChange(of: reps) { _, _ in armIdle() }
    }

    // The log state: name, Last, Beat it with the bar, the prefill, Log set.
    private var logView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: WatchTheme.isLarge ? 3 : 1) {
                Text(exercise.name).watchTitle()
                if let count = store.liveCount(for: exercise) {
                    countingBody(count)
                } else {
                    if let last = BeatItText.last(exercise.last, date: exercise.lastDate, compact: !WatchTheme.isLarge) {
                        // Wraps at set boundaries, never mid-number (§3.2).
                        // 40/41 mm: one line, so the prefill stays above Log set.
                        Text(last.replacingOccurrences(of: "×", with: "\u{2060}×\u{2060}")).watchCaption()
                            .lineLimit(WatchTheme.isLarge ? nil : 1)
                            .minimumScaleFactor(WatchTheme.isLarge ? 1 : 0.7)
                    }
                    if !exercise.countable || !store.motionAvailable {
                        Text("Counting off.").watchCaption()
                    }
                    targetBlock
                }
                statusLine
                if WatchTheme.isLarge && store.liveCount(for: exercise) == nil {
                    Text("Double tap to log.").watchCaption(WatchTheme.textTertiary)
                }
            }
            .padding(.leading, WatchTheme.inset)
            .padding(.trailing, WatchTheme.trailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinnedBottom {
            VStack(spacing: 6) {
                if store.toast != nil { ToastBar() }
                // 40/41 mm: the toast takes Log set's place while it's up.
                if store.toast == nil || WatchTheme.isLarge { logButton }
            }
        }
    }

    @ViewBuilder private var targetBlock: some View {
        if let target = exercise.target {
            if exercise.targetHit {
                // AC 74: quieter than New best, no bar.
                Label("Target hit", systemImage: "checkmark")
                    .font(.caption2.weight(.semibold)).foregroundStyle(WatchTheme.textPrimary)
            } else {
                // The target keeps the bar until a set beats it (Ben 2:16pm).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("Beat it").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                    Text(BeatItText.number(target, bodyweight: exercise.bodyweight))
                        .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                        .theBar(isCurrent, dimmed: dimmed)
                }
                .accessibilityElement(children: .combine)
            }
            valueRow
                .padding(.top, WatchTheme.isLarge ? 2 : 0)
        } else {
            // 3.5 First time: no Last, no bar; Crown sets the weight.
            Text("First time. Log what you do.").watchCaption()
            if weight <= 0 && !exercise.bodyweight && active != .weight {
                Button { take(.weight) } label: {
                    Text("Add weight").font(WatchTheme.hero(22)).foregroundStyle(WatchTheme.textPrimary)
                }
                .buttonStyle(.plain)
            } else {
                valueRow
            }
            Text("\(Int(reps)) reps · Crown to set").watchCaption()
        }
    }

    /// What will be logged: tap the weight or the reps, then the Crown changes it.
    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if !exercise.bodyweight || weight > 0 {
                Text(UnitMath.format(weight))
                    .modifier(CrownFocusRing(on: active == .weight))
                    .focusable(active == .weight).focused($focus, equals: .weight)
                    .focusEffectDisabled()
                    .digitalCrownRotation($weight, from: 0, through: 1500, by: exercise.step, sensitivity: .low,
                                          isContinuous: false, isHapticFeedbackEnabled: true)
                    .onTapGesture { take(.weight) }
                Text("×").padding(.horizontal, 2)
            }
            Text("\(Int(reps))\(exercise.bodyweight && weight <= 0 ? " reps" : "")")
                .modifier(CrownFocusRing(on: active == .reps))
                .focusable(active == .reps).focused($focus, equals: .reps)
                .focusEffectDisabled()
                .digitalCrownRotation($reps, from: 1, through: 100, by: 1, sensitivity: .low,
                                      isContinuous: false, isHapticFeedbackEnabled: true)
                .onTapGesture { take(.reps) }
        }
        .font(WatchTheme.hero(WatchTheme.isLarge ? 26 : 24))
        .foregroundStyle(WatchTheme.textPrimary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This set, \(UnitMath.format(weight)) \(exercise.unit.symbol) times \(Int(reps))")
        .accessibilityHint("Tap the weight or the reps, then turn the Digital Crown")
    }

    // 3.3 Live count: the bar moves under the estimate; Crown corrects it.
    private func countingBody(_ count: Int) -> some View {
        let target = exercise.target?.reps ?? Int(reps)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(UnitMath.format(weight)) \(exercise.unit.symbol) · Beat \(target)").watchCaption()
            Text("\(count)")
                .font(WatchTheme.hero(56))
                .foregroundStyle(WatchTheme.textPrimary)
                .contentTransition(.numericText())
                .focusable(true)
                .focused($focus, equals: .count)
                .focusEffectDisabled()
                .onAppear { focus = .count }
                .digitalCrownRotation(Binding(get: { Double(count) }, set: { store.countOffset = Int($0.rounded()) - store.motion.count }),
                                      from: 0, through: 100, by: 1, sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
                .theBar(dimmed: dimmed)
                .accessibilityLabel("\(count) reps counted, an estimate")
            Text("of \(target) · Crown to correct").watchCaption()
        }
    }

    @ViewBuilder private var statusLine: some View {
        if !store.phoneReachable {
            Text("On this Watch only.").watchCaption()
        } else if store.healthOff {
            Text("Apple Health is off. Your sets are safe in Lift.").watchCaption()
        }
    }

    private var logButton: some View {
        Button("Log set") { log() }
            .buttonStyle(WatchPrimaryStyle())
            .modifier(DoubleTapLogs())
    }

    private func newBestView(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(exercise.name).watchTitle()
            Text("New best").font(.caption2.weight(.semibold)).foregroundStyle(WatchTheme.ember)
            Text(text).font(WatchTheme.hero(30)).foregroundStyle(WatchTheme.textPrimary).theBar(dimmed: dimmed)
            Spacer()
        }
        .padding(.leading, WatchTheme.inset)
        .padding(.trailing, WatchTheme.trailingInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// Never blocked: logs whatever is on screen (the live count if counting).
    /// The Crown goes back to moving between exercises afterwards.
    private func log() {
        let r = store.liveCount(for: exercise) ?? Int(reps)
        store.log(exercise: exercise, weight: weight, reps: max(r, 1))
        release()
    }

    private func take(_ f: Field) {
        active = f
        DispatchQueue.main.async { focus = f }
    }

    private func release() {
        idle?.cancel()
        active = nil
        focus = nil
    }

    /// 3 s with no Crown input hands the Crown back to the pages (CDO).
    private func armIdle() {
        idle?.cancel()
        guard active != nil, !store.isFixture else { return }
        idle = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { release() }
        }
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

    private var ring: CGFloat { WatchTheme.isLarge ? 92 : 64 }

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
                    // Always-On keeps m:ss at full text colour (QA 1, item 16).
                    Text(RestCountdown.format(left))
                        .font(WatchTheme.hero(WatchTheme.isLarge ? 30 : 25))
                        .foregroundStyle(WatchTheme.textPrimary)
                        .accessibilityLabel("Rest, \(Int(left.rounded(.up))) seconds left")
                }
                .frame(width: ring, height: ring)
                .onLongPressGesture(perform: onEdit)
                if let next = rest.next {
                    Text("Next").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                    Text(next).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                        .theBar(dimmed: dimmed)
                }
            }
            // Clear of the ••• / Finish row (QA 1, item 1).
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .pinnedBottom {
                if !dimmed {
                    HStack(spacing: 6) {
                        Button("+30s") { store.addRest(30) }.buttonStyle(WatchChipStyle())
                            .accessibilityLabel("30 seconds more, this break only")
                        Button("Skip") { store.skipRest() }.buttonStyle(WatchChipStyle())
                    }
                }
            }
        }
    }
}

struct RestUpView: View {
    @Environment(WatchStore.self) private var store
    let exercise: LiveExercise
    let onLog: () -> Void

    private var ring: CGFloat { WatchTheme.isLarge ? 92 : 64 }

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().stroke(WatchTheme.separator, lineWidth: 4)
                Text("Rest’s up").font(WatchTheme.isLarge ? .body.weight(.semibold) : .footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.textPrimary).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(width: ring, height: ring)
            .onTapGesture { store.dismissRestUp() }
            Text("Next").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
            Text(BeatItText.number(exercise.prefill, bodyweight: exercise.bodyweight))
                .font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary).theBar()
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .pinnedBottom { Button("Log set", action: onLog).buttonStyle(WatchPrimaryStyle()).modifier(DoubleTapLogs()) }
    }
}

// MARK: 3.10 Rest picker (Crown wheel, raised selected row, no system ring)

struct RestPicker: View {
    @Environment(WatchStore.self) private var store
    let exercise: LiveExercise
    @State private var crown = 0.0
    @FocusState private var focused: Bool

    private var choices: [Int] { RestChoices.all(including: exercise.restSeconds) }
    private var index: Int { min(max(Int(crown.rounded()), 0), choices.count - 1) }

    var body: some View {
        VStack(spacing: 3) {
            Text("Rest").font(.headline).foregroundStyle(WatchTheme.textPrimary)
            Text("\(exercise.name) · 15 s steps")
                .font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.9)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 2) {
                Text(index > 0 ? RestChoices.label(choices[index - 1]) : " ")
                    .onTapGesture { crown = Double(max(index - 1, 0)) }
                Text(RestChoices.label(choices[index]))
                    .font(WatchTheme.hero(24)).foregroundStyle(WatchTheme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(WatchTheme.raised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(index + 1 < choices.count ? RestChoices.label(choices[index + 1]) : " ")
                    .onTapGesture { crown = Double(min(index + 1, choices.count - 1)) }
            }
            .font(.body.monospacedDigit()).foregroundStyle(WatchTheme.textSecondary)
            .focusable(true).focused($focused)
            .focusEffectDisabled()
            .digitalCrownRotation($crown, from: 0, through: Double(choices.count - 1), by: 1, sensitivity: .low,
                                  isContinuous: false, isHapticFeedbackEnabled: true)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rest for \(exercise.name)")
            .accessibilityValue(RestChoices.label(choices[index]))
            .accessibilityAdjustableAction { dir in
                crown = Double(dir == .increment ? min(index + 1, choices.count - 1) : max(index - 1, 0))
            }
            Text("Crown to adjust · Off to 5:00").watchCaption()
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, WatchTheme.inset)
        .onAppear {
            crown = Double(choices.firstIndex(of: exercise.restSeconds) ?? 0)
            focused = true
        }
        .onDisappear {
            let v = choices[index]
            if v != exercise.restSeconds { store.setRest(exercise, seconds: v) }
        }
    }
}

// MARK: 3.6 Add exercise

struct AddPage: View {
    let onAdd: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add exercise").watchTitle()
                Text("Recents first.").font(.footnote).foregroundStyle(WatchTheme.textSecondary)
            }
            .padding(.leading, WatchTheme.inset)
            .padding(.trailing, WatchTheme.trailingInset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinnedBottom { Button("Add exercise", action: onAdd).buttonStyle(WatchPrimaryStyle()) }
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
            Text("Add exercise").font(.headline).foregroundStyle(WatchTheme.textPrimary)
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            // 49 / 45 mm show the field (dictation and Scribble); 40–42 mm pull down to search.
            if WatchTheme.isLarge {
                TextField("Search", text: $query)
                    .foregroundStyle(WatchTheme.textPrimary)
            }
            if !rows.recents.isEmpty {
                Section("Recents") { ForEach(rows.recents) { row($0, meta: ago($0.lastDate)) } }
            }
            Section {
                ForEach(rows.all) { row($0, meta: nil) }
            } header: { Text("All") } footer: {
                if query.isEmpty { Text("Search for more.").foregroundStyle(WatchTheme.textSecondary) }
            }
        }
        .modifier(SmallScreenSearch(query: $query))
        .tint(WatchTheme.textPrimary)
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
                Text(ex.name).lineLimit(2).minimumScaleFactor(0.9).foregroundStyle(WatchTheme.textPrimary)
                Spacer(minLength: 4)
                if isAdded {
                    Image(systemName: "checkmark").foregroundStyle(WatchTheme.textPrimary)
                        .accessibilityLabel("Added")
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

/// Pull-down search on small watches, where the field row would crowd the list.
struct SmallScreenSearch: ViewModifier {
    @Binding var query: String
    func body(content: Content) -> some View {
        if WatchTheme.isLarge { content } else { content.searchable(text: $query, prompt: "Search") }
    }
}

// MARK: 3.7 Finish (Done pinned; QA 1, item 2)

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
                    Text("First time on these. Next time, they’re your numbers to beat.").watchTitle()
                } else {
                    Text("\(t.beaten) of \(t.of) targets beaten.").watchTitle().monospacedDigit()
                }
                ForEach(Array(beaten.enumerated()), id: \.element.exercise.id) { i, b in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.exercise.name).font(.footnote).foregroundStyle(WatchTheme.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.9)
                        Text(BeatItText.number(b.best, bodyweight: b.exercise.bodyweight))
                            .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                            .theBar(i == 0)
                    }
                }
                if let v = w.volumeComparison {
                    Text(volumeLine(v, unit: w.unit, lastDate: w.exercises.compactMap(\.lastDate).max())).watchCaption()
                }
                if w.unloggedCount > 0 {
                    let n = w.unloggedCount
                    Text("\(n) set\(n == 1 ? "" : "s") not logged, so \(n == 1 ? "it won’t" : "they won’t") be saved.").watchCaption()
                    Button("Back to workout", action: onBack)
                        .buttonStyle(.plain)
                        .font(.footnote.weight(.semibold)).foregroundStyle(WatchTheme.textPrimary)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, WatchTheme.inset)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .pinnedBottom {
            Button("Done") {
                store.finish()
                WKInterfaceDevice.current().play(.success)
                store.startFresh()
                onDone()
            }
            .buttonStyle(WatchPrimaryStyle())
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

// MARK: Toast (3.12): 44 pt dark bar, Undo in Ember

struct ToastBar: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let t = store.toast {
            HStack {
                Text(t.text).font(.footnote).foregroundStyle(WatchTheme.textPrimary).lineLimit(1).minimumScaleFactor(0.9)
                Spacer(minLength: 4)
                Button("Undo") { store.undoToast() }
                    .buttonStyle(.plain)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(WatchTheme.ember)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .padding(.leading, 12)
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(WatchTheme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
