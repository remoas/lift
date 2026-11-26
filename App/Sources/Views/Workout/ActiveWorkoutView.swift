import SwiftUI
import SwiftData
import LiftCore

/// The Log tab: today's workout, open from launch. Nothing logged = nothing saved.
struct ActiveWorkoutView: View {
    let workout: Workout
    /// Only for a past workout logged from History (it opens in a cover).
    var onClose: (() -> Void)? = nil
    /// Opens the summary. Nothing is final until Done there.
    var onFinished: (Workout) -> Void
    /// Back to Today with a 5 s Undo; deleted only when the window ends.
    var onDiscard: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(CloudSyncMonitor.self) private var cloud
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var session: WorkoutSession?
    @State private var editing: SetEntry?
    @State private var picker: ExercisePicker.Mode?
    @State private var showEditToday = false
    @State private var detail: Exercise?
    // PR banner morph state (§8.5): shown copy, its set, and whether it has landed.
    @State private var shownBanner: PRBannerContent?
    @State private var shownSetID: UUID?
    @State private var bannerLanded = false
    /// Exercise whose inline rep-goal stepper is showing.
    @State private var repGoalFor: UUID?
    /// Exercise whose rest picker sheet is open (frame 28).
    @State private var restFor: Exercise?

    var body: some View {
        NavigationStack {
            Group {
                if let session { content(session) } else { Theme.Colors.bgCanvas }
            }
            .background(Theme.Colors.bgCanvas)
            .navigationTitle(workout.isBackLog
                             ? workout.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
                             : Date().formatted(.dateTime.weekday(.wide)))
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbar }
            .navigationDestination(item: $detail) { ExerciseDetailView(exercise: $0).liftZoomDestination(.exercise($0.id)) }
        }
        .sheet(item: $restFor) { ex in
            RestPickerSheet(exercise: ex, current: ex.restSec ?? settings.workingRestSeconds) { session?.setRest(for: ex, seconds: $0) }
                .presentationDetents([.medium])
        }
        .onAppear {
            if session == nil { session = WorkoutSession(workout: workout, context: context, settings: settings) }
            #if DEBUG
            applyFixture()
            #endif
        }
        .sheet(item: $editing) { set in
            if let session {
                SetEditorSheet(entry: set, title: editorTitle(set, session), lastTime: session.previous(for: set).map { WeightText.pair($0.snapshot, in: set.unit, step: set.exercise?.step(for: set.unit) ?? set.unit.defaultStep) }) {
                    if set.isDone { session.save(); session.refreshBests() } else { session.log(set) }
                }
            }
        }
        .sheet(item: Binding(get: { picker.map(PickerItem.init) }, set: { picker = $0?.mode })) { item in
            ExercisePicker(mode: item.mode) { picked in
                guard let session else { return }
                switch item.mode {
                case .swap(let old): if let new = picked.first { session.swap(old, for: new) }
                default: for ex in picked { session.addExercise(ex) }
                }
            }
        }
        .sheet(isPresented: $showEditToday) {
            if let session { EditTodayView(session: session, onAdd: { showEditToday = false; picker = .add }) }
        }
    }

    #if DEBUG
    private func applyFixture() {
        guard let frame = Fixtures.requested, let session else { return }
        let lastDone = workout.groups.flatMap(\.sets).last { $0.isDone }
        switch frame {
        case "04-rest": if let lastDone { session.startRest(after: lastDone) }
        case "05-set-editor": editing = session.currentSet
        case "06-pr-banner": if let lastDone { session.refreshBests(); session.debugShowBanner(for: lastDone) }
        case "19-reorder": showEditToday = true
        default: break
        }
    }
    #endif

    // MARK: Content

    private func content(_ session: WorkoutSession) -> some View {
        ZStack(alignment: .top) {
            List {
                if session.groups.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: Theme.Spacing.s5) {
                            if cloud.isRestoring {
                                VStack(alignment: .leading, spacing: Theme.Spacing.s2) {
                                    Text("Bringing your workouts over from iCloud. You can log now; anything you log is kept.")
                                    IndeterminateLine()
                                }
                                .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                            } else if cloud.restoreFailed {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text("Couldn't reach iCloud. Your workouts will come over when you're back online.")
                                        .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                                    Button("Try again") { cloud.retry() }.buttonStyle(TextActionStyle())
                                }
                            }
                            Text("Log what you lift. Lift remembers it for next time.")
                                .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Add exercise") { picker = .add }.buttonStyle(PrimaryButtonStyle())
                        }
                        .padding(.top, Theme.Spacing.s3)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.Colors.bgCanvas)
                } else if !workout.isBackLog, let started = session.startedClock {
                    Section {
                        TimelineView(.periodic(from: .now, by: 1)) { ctx in
                            Text(RestCountdown.format(ctx.date.timeIntervalSince(started)))
                                .font(Theme.Fonts.caption.monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                                .accessibilityLabel("Elapsed")
                        }
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.Colors.bgCanvas)
                }
                ForEach(session.groups, id: \.exercise.id) { group in
                    exerciseSection(group.exercise, sets: group.sets, session: session)
                }
                if !session.groups.isEmpty {
                    Section {
                        Button("Add exercise") { picker = .add }.buttonStyle(TextActionStyle())
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.Colors.bgCanvas)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                RestBarView(countdown: session.rest, nextText: session.restNextText, doneText: session.restDoneText,
                            caption: session.restCaption,
                            onAdjust: { session.adjustRest(by: $0) }, onSkip: { session.skipRest(toasts: toasts) })
                    .opacity(session.rest == nil && session.restDoneText == nil ? 0 : 1)
                    .frame(height: session.rest == nil && session.restDoneText == nil ? 0 : nil)
                    .animation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.springBanner, value: session.rest == nil)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                // Under the nav, pushing the list down so it never covers a header (QA 8).
                if let banner = shownBanner {
                    PRBannerView(content: banner, setID: shownSetID, landed: bannerLanded, onTap: {
                        detail = session.bannerExercise
                        session.dismissBanner()
                    }, onDismiss: { session.dismissBanner() })
                    .padding(.vertical, Theme.Spacing.s2)
                    .background(Theme.Colors.bgCanvas)
                    .transition(.opacity)
                }
            }

        }
        .onChange(of: session.banner) { _, new in bannerChanged(new, setID: session.bannerSetID) }
        .onAppear {
            // A banner set before this view existed (fixtures): show it in place.
            if let b = session.banner, shownBanner == nil {
                shownBanner = b
                shownSetID = session.bannerSetID
                bannerLanded = true
            }
        }
        .onChange(of: session.saveError) { _, err in
            if let err { toasts.show(err); session.saveError = nil }
        }
    }

    @ViewBuilder
    private func exerciseSection(_ ex: Exercise, sets: [SetEntry], session: WorkoutSession) -> some View {
        Section {
            header(ex, sets: sets, session: session)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button("Remove", role: .destructive) { session.remove(ex, toasts: toasts) }
                }
            ForEach(Array(sets.enumerated()), id: \.element.id) { index, set in
                let model = session.rowModel(for: set, number: index + 1)
                SetRowView(model: model, onValue: { editing = set }, onTick: {
                    if session.tick(set) == .needsEditor { editing = set }
                })
                .listRowInsets(EdgeInsets(top: 0, leading: Theme.Spacing.s3, bottom: 0, trailing: Theme.Spacing.s3))
                .listRowSeparatorTint(Theme.Colors.separator)
                .listRowBackground(Theme.Colors.bgCanvas)
                .swipeActions(edge: .trailing) {
                    Button("Delete", role: .destructive) { session.deleteSet(set, toasts: toasts) }
                }
                .contextMenu {
                    Picker("Set type", selection: Binding(get: { set.kind }, set: { session.setKind(set, $0) })) {
                        ForEach(SetKind.allCases) { Text($0.label).tag($0) }
                    }
                    Button("Delete set", role: .destructive) { session.deleteSet(set, toasts: toasts) }
                }
            }
            Button("Add set") { session.addSet(to: ex) }
                .buttonStyle(TextActionStyle())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.Colors.bgCanvas)
        }
    }

    /// Typographic block (quick-log §2): name + •••, the Last line, the Beat it line.
    private func header(_ ex: Exercise, sets: [SetEntry], session: WorkoutSession) -> some View {
        let rest = sets.first?.restSeconds ?? 120
        let beat = session.beatIt(for: ex)
        let isCurrent = session.currentExercise === ex
        let hit = session.targetHit(for: ex)
        return VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            HStack {
                Button { detail = ex } label: {
                    Text(ex.name).font(.headline).foregroundStyle(Theme.Colors.textPrimary)
                        .liftZoomSource(.exercise(ex.id))
                }
                .buttonStyle(.plain)
                .onLongPressGesture { showEditToday = true }
                Spacer()
                Menu {
                    Button("Swap") { picker = .swap(ex) }
                    Button("Add set") { session.addSet(to: ex) }
                    Button("Rest · \(RestChoices.label(ex.restSec ?? rest))") { restFor = ex }
                    Button("Rep goal · \(ex.repGoal)") { repGoalFor = ex.id }
                    Button("Remove", role: .destructive) { session.remove(ex, toasts: toasts) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Size.hit, height: Theme.Size.hit)
                }
                .accessibilityLabel("\(ex.name) options")
            }
            if !beat.last.isEmpty {
                Text(lastLine(beat, unit: session.unit(for: ex)))
                    .font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            targetLine(beat, ex: ex, unit: session.unit(for: ex), isCurrent: isCurrent, hit: hit)
            if repGoalFor == ex.id {
                HStack {
                    Stepper("Rep goal \(ex.repGoal)", value: Binding(get: { ex.repGoal }, set: { session.setRepGoal(for: ex, $0) }), in: 3...30)
                        .font(.subheadline).foregroundStyle(Theme.Colors.textSecondary)
                    Button("Done") { repGoalFor = nil }.buttonStyle(TextActionStyle()).padding(.leading, Theme.Spacing.s3)
                }
            }
        }
        .padding(.top, Theme.Spacing.s4)
        .padding(.bottom, Theme.Spacing.s2)
        .listRowBackground(Theme.Colors.bgCanvas)
    }

    /// "Last · Mon · 185×8, 185×7, 185×6"
    private func lastLine(_ beat: LiftStore.BeatIt, unit: WeightUnit) -> String {
        BeatItText.last(beat.last, date: beat.lastDate) ?? "Last"
    }

    @ViewBuilder
    private func targetLine(_ beat: LiftStore.BeatIt, ex: Exercise, unit: WeightUnit, isCurrent: Bool, hit: Bool) -> some View {
        if let t = beat.target {
            let number = BeatItText.number(t, bodyweight: ex.equipment == .bodyweight)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.s1))
                : AnyLayout(HStackLayout(spacing: 0))
            layout {
                Text(typeSize.isAccessibilitySize ? "Beat it" : "Beat it · ")
                if isCurrent && !hit { Text(number).theBar() } else { Text(number) }
                if hit {
                    Text("✓ Target hit").foregroundStyle(Theme.Colors.accent)
                        .padding(.leading, typeSize.isAccessibilitySize ? 0 : Theme.Spacing.s3)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Theme.Colors.textPrimary)
            .font(.body.monospacedDigit())
            .padding(.bottom, isCurrent ? Theme.Size.bar + 3 : 0)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Beat it, \(number)\(hit ? ", target hit" : "")")
        } else {
            Text("First time. Log what you do.")
                .font(.body).foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let onClose {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", action: onClose)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Reorder", systemImage: "arrow.up.arrow.down") { showEditToday = true }
                Divider()
                Button("Discard workout", systemImage: "trash", role: .destructive) { discard() }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(width: Theme.Size.hit, height: Theme.Size.hit)
            }
            .tint(Theme.Colors.textSecondary)
            .accessibilityLabel("Workout options")
        }
        ToolbarItem(placement: .confirmationAction) {
            if session?.groups.isEmpty == false {
                // The one Ember primary once an exercise is in (AC 65).
                Button("Finish") { finish() }
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .padding(.horizontal, Theme.Spacing.s4)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.accent, in: Capsule())
            }
        }
    }

    private func editorTitle(_ set: SetEntry, _ session: WorkoutSession) -> String {
        guard let ex = set.exercise, let sets = session.groups.first(where: { $0.exercise === ex })?.sets,
              let i = sets.firstIndex(where: { $0 === set }) else { return set.exercise?.name ?? "" }
        return "\(ex.name), set \(i + 1)"
    }

    /// Appear: start on the set's value, then grow into place with springBanner.
    /// Replace: in place, no stack. Dismiss: reverse toward the set, then fade.
    private func bannerChanged(_ new: PRBannerContent?, setID: UUID?) {
        if let new {
            if shownBanner != nil {
                withAnimation(reduceMotion ? Theme.Motion.fadeReduced : Theme.Motion.springBanner) {
                    shownBanner = new
                    shownSetID = setID
                    bannerLanded = true
                }
                return
            }
            if reduceMotion {
                bannerLanded = true
                shownSetID = setID
                withAnimation(Theme.Motion.fadeReduced) { shownBanner = new }
                return
            }
            var t = Transaction()
            t.disablesAnimations = true
            withTransaction(t) {
                bannerLanded = false
                shownSetID = setID
                shownBanner = new
            }
            DispatchQueue.main.async {
                withAnimation(Theme.Motion.springBanner) { bannerLanded = true }
            }
        } else {
            guard shownBanner != nil else { return }
            if reduceMotion {
                withAnimation(Theme.Motion.fadeReduced) { shownBanner = nil }
                return
            }
            withAnimation(Theme.Motion.springBanner) { bannerLanded = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.32 / Theme.Motion.slowFactor) {
                guard session?.banner == nil else { return }
                withAnimation(Theme.Motion.fadeReduced) { shownBanner = nil }
            }
        }
    }

    /// Straight to the summary, no alert. Sets aren't touched until Done.
    private func finish() {
        session?.stopRest()
        session?.save()
        onFinished(workout)
    }

    private func discard() {
        session?.stopRest()
        session?.save()
        onDiscard(workout)
    }
}


private struct PickerItem: Identifiable {
    let mode: ExercisePicker.Mode
    var id: String {
        switch mode {
        case .add: return "add"
        case .swap(let ex): return "swap-\(ex.id)"
        }
    }
}

/// Reorder (frame 19): native List edit mode, today only.
struct EditTodayView: View {
    let session: WorkoutSession
    var onAdd: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ToastCenter.self) private var toasts
    @State private var order: [Exercise] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Drag to reorder.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                }
                Section {
                    ForEach(order, id: \.id) { ex in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                            Text(status(ex)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .frame(minHeight: 60, alignment: .leading)
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        Haptics.step()
                        session.reorder(order)
                    }
                    .onDelete { offsets in
                        for i in offsets { session.remove(order[i], toasts: toasts) }
                        order.remove(atOffsets: offsets)
                    }
                }
                if order.isEmpty {
                    Button("Add exercise", action: onAdd).buttonStyle(TextActionStyle())
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Reorder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Add", action: onAdd) }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
            .overlay { ToastOverlay() }
        }
        .presentationDragIndicator(.visible)
        .onAppear { order = session.groups.map(\.exercise) }
        .onChange(of: session.groups.count) { _, _ in order = session.groups.map(\.exercise) }
    }

    private func status(_ ex: Exercise) -> String {
        let sets = session.groups.first { $0.exercise === ex }?.sets ?? []
        let done = sets.filter(\.isDone).count
        let state = done == 0 ? "" : (done == sets.count ? " · done" : " · \(done) done")
        return "\(sets.count) sets\(state)"
    }
}
