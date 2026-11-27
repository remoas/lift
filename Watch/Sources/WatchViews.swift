import SwiftUI
import WatchKit
import UIKit
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
                    // Our own short dots at the bottom replace the trailing system indicator (QA 2, item 4).
                    // Each page draws them under its pinned button, in the bottom gap (pinnedBottom).
                    .scrollIndicators(.hidden)
                    .environment(\.watchPageDots, store.toast == nil ? PageDotsInfo(count: exercises.count + 1, current: page) : nil)
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
struct PageDotsInfo: Equatable { let count: Int; let current: Int }
private struct PageDotsKey: EnvironmentKey { static let defaultValue: PageDotsInfo? = nil }

extension EnvironmentValues {
    var watchPageDots: PageDotsInfo? {
        get { self[PageDotsKey.self] }
        set { self[PageDotsKey.self] = newValue }
    }
    /// Always-On (or its w11 preview).
    var watchDimmed: Bool {
        get { self[DimmedKey.self] }
        set { self[DimmedKey.self] = newValue }
    }
}

/// The slot under a pager page's button; keeps its height while a toast hides the dots.
struct PageDotsSlot: View {
    @Environment(\.watchPageDots) private var dots
    var body: some View {
        ZStack {
            if let dots { PageDots(count: dots.count, current: dots.current) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: WatchTheme.dotSize)
    }
}

/// watch.md §1: a short row at the bottom; current textPrimary, the rest textTertiary.
struct PageDots: View {
    let count: Int
    let current: Int
    @Environment(\.isLuminanceReduced) private var aod
    @Environment(\.watchDimmed) private var previewDimmed
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i == current ? WatchTheme.textPrimary : WatchTheme.textTertiary.opacity(0.55))
                    .frame(width: WatchTheme.dotSize, height: WatchTheme.dotSize)
            }
        }
        .opacity(aod || previewDimmed ? 0.45 : 1)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

/// "✓ Target hit" with the check close to the words.
struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) { configuration.icon; configuration.title }
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
    /// The tapped-open Last list.
    @State private var showFullLast = false
    /// 40/41 mm: "Double tap to log." once, on the first first-time page the user
    /// sees, until they log a set or leave that page (CDO watch QA 5, Should 1).
    @AppStorage("watch.doubleTapHintSeen") private var hintSeen = false
    @State private var smallHint = false

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
            claimSmallHint()
        }
        .onChange(of: isCurrent) { _, now in if now { claimSmallHint() } else { endSmallHint() } }
        .onDisappear { endSmallHint() }
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
    //
    // CDO watch QA 3: the value being logged (and its Crown ring) is always on
    // screen without scrolling, and nothing scrolls under the pinned status line.
    // The page works out, from the fonts and the space it has, the first step
    // of this ladder that fits (no layout feedback loop; WatchFit):
    //   0  roomy: titles wrap; Last in full on 45/49 mm with no status line,
    //      one line on 40/41 mm (always) or with a status line
    //   1  no "Double tap to log." hint (45/49 mm keep full weights longer)
    //   2  Last one line everywhere
    //   3  title on one line (scales to 80 %)
    //   4  no Last line (the full list is on tap and in VoiceOver)
    //   5  first-time captions on one line
    // Past 5 it scrolls, clipped above the pinned slot.
    private var logView: some View {
        GeometryReader { geo in
            let width = geo.size.width - WatchTheme.inset - WatchTheme.trailingInset
            let level = fitLevel(height: geo.size.height, width: width)
            let fit = level.0
            ScrollView {
                logContent(fit: fit, hint: level.1)
                    .padding(.leading, WatchTheme.inset)
                    .padding(.trailing, WatchTheme.trailingInset)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDisabled(fit < Self.maxFit)
        }
        .pinnedBottom(pager: true) {
            VStack(alignment: .leading, spacing: 6) {
                // Above Log set, never in its inset (QA 2, item 3 and P); the page
                // above ends at this slot and is clipped there (QA 3, decision 2).
                statusLine
                if store.toast != nil { ToastBar() }
                // The toast takes Log set's place while it's up, on every size: on 45/49 mm
                // a toast stacked above Log set left no room for the value (QA 3).
                if store.toast == nil { logButton }
            }
        }
    }

    static let maxFit = 5

    /// The small-size hint is taken by the first current first-time page and
    /// marked seen at once, so it shows for this one view only. Fixtures read
    /// the flag but never write it, so every reshoot starts as first use.
    private func claimSmallHint() {
        guard !WatchTheme.isLarge, isCurrent, !hintSeen, exercise.target == nil,
              store.liveCount(for: exercise) == nil else { return }
        smallHint = true
        if !store.isFixture { hintSeen = true }
    }
    private func endSmallHint() { smallHint = false }

    /// "Double tap to log." on this page: always on first use on 45/49 mm (QA 4),
    /// once on 40/41 mm (QA 5); on large it's the ladder's first thing dropped.
    private func showsHint(fit: Int, small: Bool) -> Bool {
        let counting = store.liveCount(for: exercise) != nil
        if counting { return false }
        if WatchTheme.isLarge { return fit < 1 || exercise.target == nil }
        return small
    }
    private var hasStatus: Bool { !store.phoneReachable || store.healthOff }
    /// The first ladder step whose estimated height fits (see logView).
    private func fitLevel(height: CGFloat, width: CGFloat) -> (Int, Bool) {
        // The one-time small hint gets the first try; if nothing fits with it,
        // the ladder runs again without it (dropped first when tight).
        if smallHint {
            // No 2 pt margin here: the hint is the last row, so a miss clips only its own
            // descenders, never the value; each row's ceil already errs tall (w05 40 mm).
            for l in 0...Self.maxFit where estimatedHeight(fit: l, width: width, hint: true) <= height { return (l, true) }
        }
        for l in 0..<Self.maxFit where estimatedHeight(fit: l, width: width, hint: false) <= height - 2 { return (l, false) }
        return (Self.maxFit, false)
    }

    /// logContent's height at a ladder step, from the same fonts and texts.
    private func estimatedHeight(fit: Int, width: CGFloat, hint: Bool) -> CGFloat {
        let large = WatchTheme.isLarge
        let counting = store.liveCount(for: exercise) != nil
        var rows: [CGFloat] = []
        rows.append(WatchFit.height(exercise.name, WatchFit.title, width: width,
                                    lines: (fit >= 3 || (counting && !large)) ? 1 : 2))
        if counting {
            rows.append(WatchFit.line(WatchFit.caption2) + (large ? 54 : 40) + 7 + WatchFit.line(WatchFit.caption2))
        } else {
            if let full = BeatItText.last(exercise.last, date: exercise.lastDate), showFullLast || fit < 4 {
                let wrapFull = showFullLast || (fit <= 1 && large && !hasStatus)
                rows.append(wrapFull ? WatchFit.height(full.replacingOccurrences(of: "×", with: "\u{2060}×\u{2060}"), WatchFit.caption2, width: width) : WatchFit.line(WatchFit.caption2))
            }
            if !exercise.countable || !store.motionAvailable { rows.append(WatchFit.height("Counting off.", WatchFit.caption2, width: width)) }
            if exercise.target != nil {
                rows.append(WatchFit.line(WatchFit.footnoteSemibold) + 7)
                rows.append(WatchFit.line(WatchFit.hero(large ? 26 : 24)) + (large ? 2 : 0))
            } else {
                let cap = { (t: String) in fit >= 5 ? WatchFit.line(WatchFit.caption2) : WatchFit.height(t, WatchFit.caption2, width: width) }
                rows.append(cap("First time. Log what you do."))
                rows.append(WatchFit.line(WatchFit.hero(weight <= 0 && !exercise.bodyweight && active != .weight ? 22 : (large ? 26 : 24))))
                rows.append(cap("\(Int(reps)) reps · Crown to set"))
            }
        }
        if showsHint(fit: fit, small: hint) { rows.append(WatchFit.line(WatchFit.caption2)) }
        return rows.reduce(0, +) + CGFloat(max(rows.count - 1, 0)) * (large ? 3 : 1)
    }

    @ViewBuilder private func logContent(fit: Int, hint: Bool) -> some View {
        let counting = store.liveCount(for: exercise) != nil
        VStack(alignment: .leading, spacing: WatchTheme.isLarge ? 3 : 1) {
            // 40/41 mm counting: one line so the 56 pt count, its bar and
            // "of 9 · Crown to correct" fit (QA 3, decision 3).
            let title = Text(exercise.name).watchTitle(lines: (fit >= 3 || (counting && !WatchTheme.isLarge)) ? 1 : 2)
            if !counting, !showFullLast, fit >= 4, let full = BeatItText.last(exercise.last, date: exercise.lastDate) {
                // No room for Last: the name opens it, and VoiceOver reads it with the name.
                Button { showFullLast = true } label: {
                    // A 44 pt hit target around the same-size name (QA 4, Must 3): the
                    // shape reaches past the text; the layout doesn't move.
                    title.contentShape(Rectangle().inset(by: -14))
                }
                    .buttonStyle(.plain)
                    .accessibilityLabel(exercise.name)
                    .accessibilityValue(full)
                    .accessibilityHint("Shows every set")
            } else {
                title
            }
            if let count = store.liveCount(for: exercise) {
                countingBody(count)
            } else {
                lastLine(fit: fit)
                if !exercise.countable || !store.motionAvailable {
                    Text("Counting off.").watchCaption()
                }
                targetBlock(fit: fit)
            }
            if showsHint(fit: fit, small: hint) {  // first use: always on 45/49 mm (QA 4), once on 40/41 mm (QA 5)
                Text("Double tap to log.").watchCaption(WatchTheme.textTertiary)
            }
        }
    }

    /// One line on 40/41 mm, "Last · Tue · 185×8, 7, 6" or "185×8, 175×7…" cut at
    /// a whole entry. Tap for every set in full; VoiceOver always reads them all.
    @ViewBuilder private func lastLine(fit: Int) -> some View {
        if let full = BeatItText.last(exercise.last, date: exercise.lastDate), showFullLast || fit < 4 {
            let wrapFull = showFullLast || (fit <= 1 && WatchTheme.isLarge && !hasStatus)
            Button { showFullLast.toggle() } label: {
                if wrapFull {
                    lastText(full)
                } else {
                    let options = BeatItText.lastOneLine(exercise.last, date: exercise.lastDate)
                    ViewThatFits(in: .horizontal) {
                        ForEach(options, id: \.self) { lastText($0).lineLimit(1) }
                        lastText(options.last ?? full).lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(full)
            .accessibilityHint(wrapFull ? "" : "Shows every set")
        }
    }

    /// Word joiners keep "185×8" together when Last wraps.
    private func lastText(_ s: String) -> some View {
        Text(s.replacingOccurrences(of: "×", with: "\u{2060}×\u{2060}")).watchCaption()
    }

    @ViewBuilder private func targetBlock(fit: Int) -> some View {
        if let target = exercise.target {
            // The target keeps the bar until a set beats it, after a miss too
            // (Ben 2:16pm; QA 2, item 7). Target hit is a quiet Ember "✓ Target hit"
            // on the same line, the bar still under the number (§3.11, QA 2 O).
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                if exercise.targetHit {
                    Label("Target hit", systemImage: "checkmark")
                        .font(.caption2.weight(.semibold)).foregroundStyle(WatchTheme.ember)
                        .labelStyle(TightLabel())
                } else {
                    Text("Beat it").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                }
                Text(BeatItText.number(target, bodyweight: exercise.bodyweight))
                    .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                    .theBar(dimmed: dimmed)
            }
            .accessibilityElement(children: .combine)
            valueRow
                .padding(.top, WatchTheme.isLarge ? 2 : 0)
        } else {
            // 3.5 First time: no Last, no bar; Crown sets the weight.
            firstTimeCaption("First time. Log what you do.", short: "First time.", fit: fit)
            if weight <= 0 && !exercise.bodyweight && active != .weight {
                Button { take(.weight) } label: {
                    Text("Add weight").font(WatchTheme.hero(22)).foregroundStyle(WatchTheme.textPrimary)
                }
                .buttonStyle(.plain)
            } else {
                valueRow
            }
            firstTimeCaption("\(Int(reps)) reps · Crown to set", short: "\(Int(reps)) reps", fit: fit)
        }
    }

    /// Step 5 keeps each caption to one line by falling back to a whole clause
    /// ("First time.", "10 reps"), never a mid-word ellipsis (CDO watch QA 4, Must 2).
    @ViewBuilder private func firstTimeCaption(_ s: String, short: String, fit: Int) -> some View {
        if fit >= 5 {
            ViewThatFits(in: .horizontal) {
                Text(s).watchCaption().lineLimit(1)
                Text(short).watchCaption().lineLimit(1)
            }
            .accessibilityLabel(s)
        } else {
            Text(s).watchCaption()
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
        .id("prefill")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("This set, \(UnitMath.format(weight)) \(exercise.unit.symbol) times \(Int(reps))")
        .accessibilityHint("Tap the weight or the reps, then turn the Digital Crown")
    }

    // 3.3 Live count: the bar moves under the estimate; Crown corrects it.
    private func countingBody(_ count: Int) -> some View {
        let target = exercise.target?.reps ?? Int(reps)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(UnitMath.format(weight)) \(exercise.unit.symbol) · Beat \(target)").watchCaption()
            // numeralHero 56 / 64 pt; the frame trims the line box to the digits so
            // "of 9 · Crown to correct" stays above Log set on 40 mm (QA 2, item 3).
            // 40/41 mm: 40 pt still holds the 35.5 pt cap with the descender room the bar needs (QA 3, decision 3).
            Text("\(count)")
                .font(.system(size: WatchTheme.isLarge ? 64 : 56, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(height: WatchTheme.isLarge ? 54 : 40)
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
                .lineLimit(WatchTheme.isLarge ? nil : 1).minimumScaleFactor(WatchTheme.isLarge ? 1 : 0.85)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if !store.phoneReachable {
            Text("On this Watch only.").watchCaption()
        } else if store.healthOff {
            // 40/41 mm: the short form, so a three-line wrap can't push the value
            // off the page (CDO watch QA 4, Must 1). VoiceOver reads it in full.
            Text(WatchTheme.isLarge ? "Apple Health is off. Your sets are safe in Lift." : "Health is off.")
                .watchCaption()
                .accessibilityLabel("Apple Health is off. Your sets are safe in Lift.")
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
        if !store.isFixture { hintSeen = true }
        smallHint = false
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
                    // 40 mm: "Next 185 × 9" on one line so the bar clears the chips.
                    let layout = WatchTheme.isLarge ? AnyLayout(VStackLayout(spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 5))
                    layout {
                        Text("Next").font(.caption2).foregroundStyle(WatchTheme.textSecondary)
                        Text(next).font(.body.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                            .theBar(dimmed: dimmed)
                    }
                    .padding(.top, WatchTheme.isLarge ? 0 : 2)
                }
            }
            // Clear of the ••• / Finish row (QA 1, item 1).
            .padding(.top, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .pinnedBottom(pager: true) {
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
        .pinnedBottom(pager: true) { Button("Log set", action: onLog).buttonStyle(WatchPrimaryStyle()).modifier(DoubleTapLogs()) }
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
        .pinnedBottom(pager: true) { Button("Add exercise", action: onAdd).buttonStyle(WatchPrimaryStyle()) }
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
    /// The first entry at the top of the scroll; nil or 0 = at rest at the top.
    @State private var topID: Int?
    /// Moved off the top by code (the w18 fixture's scrollTo), which scrollPosition doesn't report.
    @State private var scrolledByCode = false

    var body: some View {
        let w = store.live
        let t = w.targetsBeaten
        let beaten = w.beaten
        GeometryReader { geo in
        // Whole entries only at Done's edge (QA 3, item 2): at rest, an entry that
        // would be cut there is held back until a scroll brings all of it up.
        let cut: Set<Int> = (scrolledByCode || (topID ?? 0) != 0) ? Set<Int>() : cutAtRest(height: geo.size.height, width: geo.size.width - 2 * WatchTheme.inset)
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                Group {
                    if t.of == 0 {
                        Text("First time on these. Next time, they’re your numbers to beat.").watchTitle()
                    } else {
                        Text("\(t.beaten) of \(t.of) targets beaten.").watchTitle().monospacedDigit()
                    }
                }
                .opacity(cut.contains(0) ? 0 : 1).id(0)
                ForEach(Array(beaten.enumerated()), id: \.element.exercise.id) { i, b in
                    VStack(alignment: .leading, spacing: 0) {
                        Text(b.exercise.name).font(.footnote).foregroundStyle(WatchTheme.textPrimary)
                            .lineLimit(2).minimumScaleFactor(0.9)
                        Text(BeatItText.number(b.best, bodyweight: b.exercise.bodyweight))
                            .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(WatchTheme.textPrimary)
                            .theBar(i == 0)
                    }
                    .opacity(cut.contains(i + 1) ? 0 : 1).id(i + 1)
                }
                if let v = w.volumeComparison {
                    Text(volumeLine(v, unit: w.unit, lastDate: w.exercises.compactMap(\.lastDate).max())).watchCaption()
                        .opacity(cut.contains(1000) ? 0 : 1).id(1000)
                }
                if w.unloggedCount > 0 {
                    let n = w.unloggedCount
                    Text("\(n) set\(n == 1 ? "" : "s") not logged, so \(n == 1 ? "it won’t" : "they won’t") be saved.").watchCaption()
                        .opacity(cut.contains(1001) ? 0 : 1).id(1001)
                    Button("Back to workout", action: onBack)
                        .buttonStyle(.plain)
                        .font(.footnote.weight(.semibold)).foregroundStyle(WatchTheme.textPrimary)
                        .frame(minHeight: 44)
                        .opacity(cut.contains(1002) ? 0 : 1)
                        .id(1002)
                }
            }
            .scrollTargetLayout()
            .padding(.horizontal, WatchTheme.inset)
            // The last line scrolls fully clear of Done.
            .padding(.bottom, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollPosition(id: $topID)
        // The w18 still shows the end of the list: sets-left copy and Back to workout (QA 2, item 2).
        .onAppear { if store.isFixture && w.unloggedCount > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { scrolledByCode = true; proxy.scrollTo(1002, anchor: .bottom) } } }
        }
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

    /// Entries (by id) that straddle the bottom edge with the list at the top,
    /// from the same fonts and texts (WatchFit).
    private func cutAtRest(height: CGFloat, width: CGFloat) -> Set<Int> {
        let w = store.live
        let t = w.targetsBeaten
        var rows: [(Int, CGFloat)] = []
        let title = t.of == 0 ? "First time on these. Next time, they’re your numbers to beat." : "\(t.beaten) of \(t.of) targets beaten."
        rows.append((0, WatchFit.height(title, WatchFit.title, width: width, lines: 2)))
        let footnote = UIFont.preferredFont(forTextStyle: .footnote)
        for (i, b) in w.beaten.enumerated() {
            rows.append((i + 1, WatchFit.height(b.exercise.name, footnote, width: width, lines: 2) + WatchFit.line(WatchFit.footnoteSemibold) + (i == 0 ? 7 : 0)))
        }
        if let v = w.volumeComparison {
            rows.append((1000, WatchFit.height(volumeLine(v, unit: w.unit, lastDate: w.exercises.compactMap(\.lastDate).max()), WatchFit.caption2, width: width)))
        }
        if w.unloggedCount > 0 {
            let n = w.unloggedCount
            rows.append((1001, WatchFit.height("\(n) set\(n == 1 ? "" : "s") not logged, so \(n == 1 ? "it won’t" : "they won’t") be saved.", WatchFit.caption2, width: width)))
            rows.append((1002, 44))
        }
        var y: CGFloat = 0
        var out = Set<Int>()
        for (id, h) in rows {
            // A small allowance: an estimate a point or two tall shouldn't hide a line that fits.
            if y < height && y + h > height + 1 { out.insert(id) }
            if y >= height { out.insert(id) }
            y += h + 6
        }
        return out
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
