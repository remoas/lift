import SwiftUI
import SwiftData
import LiftCore

/// Full-screen active workout. Close minimises; nothing is ever lost.
struct ActiveWorkoutView: View {
    let workout: Workout
    var onClose: () -> Void
    /// Opens the summary. Nothing is final until Done there.
    var onFinished: (Workout) -> Void
    /// Back to Today with a 5 s Undo; deleted only when the window ends.
    var onDiscard: (Workout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: WorkoutSession?
    @State private var editing: SetEntry?
    @State private var picker: ExercisePicker.Mode?
    @State private var showEditToday = false
    @State private var detail: Exercise?

    var body: some View {
        NavigationStack {
            Group {
                if let session { content(session) } else { Theme.Colors.bgCanvas }
            }
            .background(Theme.Colors.bgCanvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(item: $detail) { ExerciseDetailView(exercise: $0) }
        }
        .onAppear {
            if session == nil { session = WorkoutSession(workout: workout, context: context, settings: settings) }
            if workout.allSets.isEmpty { picker = .add }
            RestNotifications.requestPermissionIfNeeded()
            #if DEBUG
            applyFixture()
            #endif
        }
        .sheet(item: $editing) { set in
            if let session {
                SetEditorSheet(entry: set, title: editorTitle(set, session), lastTime: session.rowModel(for: set, number: 1).lastTime) {
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
                        Button("Add your first exercise") { picker = .add }
                            .font(Theme.Fonts.exercise)
                            .buttonStyle(TextActionStyle())
                    }
                    .listRowSeparator(.hidden)
                }
                ForEach(session.groups, id: \.exercise.id) { group in
                    exerciseSection(group.exercise, sets: group.sets, session: session)
                }
                if !session.groups.isEmpty {
                    Section {
                        if session.allDone {
                            Text("All sets done").font(Theme.Fonts.bodyEmphasis).foregroundStyle(Theme.Colors.textSecondary)
                        }
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
                            onAdjust: { session.adjustRest(by: $0) }, onSkip: { session.stopRest() })
                    .opacity(session.rest == nil && session.restDoneText == nil ? 0 : 1)
                    .frame(height: session.rest == nil && session.restDoneText == nil ? 0 : nil)
                    .animation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.springBanner, value: session.rest == nil)
            }

            if let banner = session.banner {
                PRBannerView(content: banner, onTap: {
                    detail = session.bannerExercise
                    session.dismissBanner()
                }, onDismiss: { withAnimation(Theme.Motion.springBanner) { session.dismissBanner() } })
                .padding(.top, Theme.Spacing.s2)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .animation(reduceMotion ? Theme.Motion.crossfade : Theme.Motion.springBanner, value: session.banner)
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

    private func header(_ ex: Exercise, sets: [SetEntry], session: WorkoutSession) -> some View {
        let first = sets.first
        let rest = first?.restSeconds ?? 120
        let firstTime = LiftStore.lastSessionSets(for: ex, excluding: workout).isEmpty
        return VStack(alignment: .leading, spacing: Theme.Spacing.s1) {
            HStack {
                Button { detail = ex } label: {
                    Text(ex.name).font(Theme.Fonts.exercise).foregroundStyle(Theme.Colors.textPrimary)
                }
                .buttonStyle(.plain)
                .onLongPressGesture { showEditToday = true }
                Spacer()
                Menu {
                    Button("Swap exercise") { picker = .swap(ex) }
                    Button("Add set") { session.addSet(to: ex) }
                    Button("Edit today") { showEditToday = true }
                    Picker("Rest", selection: Binding(get: { rest }, set: { session.setRest(for: ex, seconds: $0) })) {
                        ForEach(RestChoices.all(including: rest), id: \.self) { Text(RestCountdown.format(TimeInterval($0))).tag($0) }
                    }
                    .pickerStyle(.menu)
                    Button("Remove exercise", role: .destructive) { session.remove(ex, toasts: toasts) }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(width: Theme.Size.hit, height: Theme.Size.hit)
                }
                .accessibilityLabel("\(ex.name) options")
            }
            Text("\(first?.repMin ?? ex.repMin)–\(first?.repMax ?? ex.repMax) reps · \(RestCountdown.format(TimeInterval(rest))) rest")
                .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            if firstTime {
                Text("First time here. Pick a weight you could lift \(first?.repMax ?? ex.repMax) times with good form.")
                    .font(Theme.Fonts.secondary.italic()).foregroundStyle(Theme.Colors.textSecondary)
            } else if !ex.note.isEmpty {
                Text(ex.note).font(Theme.Fonts.secondary.italic()).foregroundStyle(Theme.Colors.textSecondary)
            }
            HStack {
                Text("Last time").padding(.leading, 36)
                Spacer().frame(width: 60)
                Text("Today")
                Spacer()
            }
            .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
            .padding(.top, Theme.Spacing.s2)
            .accessibilityHidden(true)
        }
        .padding(.top, Theme.Spacing.s4)
        .listRowBackground(Theme.Colors.bgCanvas)
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") { onClose() }
                .accessibilityHint("Keeps the workout running")
        }
        ToolbarItem(placement: .principal) {
            VStack(spacing: 0) {
                Text(workout.routineName).font(.headline).foregroundStyle(Theme.Colors.textPrimary)
                if workout.isBackLog {
                    Text(workout.startedAt, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                        .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(RestCountdown.format(ctx.date.timeIntervalSince(workout.startedAt)))
                            .font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Add exercise", systemImage: "plus") { picker = .add }
                Button("Edit today", systemImage: "arrow.up.arrow.down") { showEditToday = true }
                Divider()
                Button("Discard workout", systemImage: "trash", role: .destructive) { discard() }
            } label: {
                Image(systemName: "ellipsis.circle").frame(width: Theme.Size.hit, height: Theme.Size.hit)
            }
            .accessibilityLabel("Workout options")
        }
        ToolbarItem(placement: .confirmationAction) {
            if session?.allDone == true {
                Button("Finish") { finish() }
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.onAccent)
                    .padding(.horizontal, Theme.Spacing.s4)
                    .frame(minHeight: 36)
                    .background(Theme.Colors.accent, in: Capsule())
            } else {
                Button("Finish") { finish() }
                    .fontWeight(.semibold)
            }
        }
    }

    private func editorTitle(_ set: SetEntry, _ session: WorkoutSession) -> String {
        guard let ex = set.exercise, let sets = session.groups.first(where: { $0.exercise === ex })?.sets,
              let i = sets.firstIndex(where: { $0 === set }) else { return set.exercise?.name ?? "" }
        return "\(ex.name), set \(i + 1)"
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

/// Rest choices for the ••• menu and set editor (15 s steps up to 5 min).
enum RestChoices {
    static func all(including current: Int) -> [Int] {
        let base = [30, 45, 60, 75, 90, 105, 120, 150, 180, 210, 240, 300]
        return base.contains(current) ? base : (base + [current]).sorted()
    }
}

private struct PickerItem: Identifiable {
    let mode: ExercisePicker.Mode
    var id: String {
        switch mode {
        case .add: return "add"
        case .swap(let ex): return "swap-\(ex.id)"
        case .setup(let d): return "setup-\(d)"
        }
    }
}

/// §3.13 Edit today: native List edit mode, today only.
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
                    Text("Drag to reorder. Changes are for today only.")
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
                    Button("Add your first exercise", action: onAdd).buttonStyle(TextActionStyle())
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Add", action: onAdd) }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text("Edit today").font(.headline)
                        Text(session.workout.routineName).font(Theme.Fonts.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
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
