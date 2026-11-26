import SwiftUI
import SwiftData
import LiftCore

struct TodayView: View {
    var onOpenWorkout: (Workout) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(CloudSyncMonitor.self) private var cloud
    @Query(sort: \Routine.order) private var routines: [Routine]
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }, sort: \Workout.startedAt, order: .reverse)
    private var active: [Workout]
    @State private var showSettings = false
    @State private var showChooser = false
    @State private var buildingDay: Routine?
    /// Workout.id reserved before presenting so the zoom source and cover share one UUID.
    @State private var reservedID = UUID()
    @State private var reservedBlankID = UUID()

    private var next: Routine? { LiftStore.nextRoutine(routines: routines, finished: finished) }
    private var doneThisWeek: Int { Week.count(finished.map(\.startedAt), inWeekOf: Date()) }
    private var target: Int { settings.daysPerWeek }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                    Text(Date(), format: .dateTime.weekday(.wide))
                        .font(Theme.Fonts.secondary)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    hero
                    lede
                    if cloud.isRestoring { IndeterminateLine().padding(.vertical, Theme.Spacing.s1) }
                    WeekDots(done: doneThisWeek, target: target)
                        .padding(.top, Theme.Spacing.s2)
                    lifts.padding(.top, Theme.Spacing.section - Theme.Spacing.s3)
                }
                .liftZoomSource(.workout(active.first?.id ?? reservedID))
                .screenMargins()
                .padding(.bottom, 140)
            }
            .background(Theme.Colors.bgCanvas)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").frame(width: Theme.Size.hit, height: Theme.Size.hit)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .safeAreaInset(edge: .bottom) { actions }
            .navigationDestination(for: Exercise.self) { ExerciseDetailView(exercise: $0).liftZoomDestination(.exercise($0.id)) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showChooser) {
                ChooseWorkoutSheet(routines: routines, finished: finished, next: next) { routine in
                    showChooser = false
                    start(routine)
                }
            }
            .sheet(item: $buildingDay) { day in
                NavigationStack {
                    BuildDayView(routine: day, context: .sheet, onDone: { buildingDay = nil })
                }
                .presentationDragIndicator(.visible)
            }
        }
    }

    // MARK: Hero and lede

    @ViewBuilder private var hero: some View {
        if cloud.isRestoring {
            Text("Bringing your workouts over").font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
        } else if let current = active.first {
            HStack(spacing: 0) {
                Text("Next up, ")
                Text(current.routineName).theBar()
            }
            .font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
        } else if let next {
            HStack(spacing: 0) {
                Text("Next up, ")
                Text(next.name).theBar()
            }
            .font(Theme.Fonts.display).foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    @ViewBuilder private var lede: some View {
        Group {
            if cloud.isRestoring {
                Text("Restoring from iCloud. You can start a workout now; anything you log is kept.")
            } else if cloud.restoreFailed {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Couldn't reach iCloud. Your workouts will come over when you're back online.")
                    Button("Try again") { cloud.retry() }.buttonStyle(TextActionStyle())
                }
            } else if let current = active.first {
                let minutes = Int(Date().timeIntervalSince(current.startedAt) / 60)
                Text("\(current.doneSets.count) of \(current.allSets.count) sets done, \(minutes) min in.")
            } else if let next {
                ledeText(for: next)
            }
        }
        .font(.body)
        .foregroundStyle(Theme.Colors.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func ledeText(for routine: Routine) -> Text {
        if routine.sortedItems.isEmpty {
            return Text("\(routine.name) doesn't have any exercises yet. Add the ones you do and you're ready to go.")
        }
        if doneThisWeek >= target {
            return Text("That's \(doneThisWeek) of \(target) this week. Anything more is a bonus.")
        }
        let lastOfRoutine = finished.first { $0.routineID == routine.id }
        guard let lastOfRoutine else {
            return Text("Your first \(routine.name). Pick weights you could lift for the top of each range with good form.")
        }
        if let latest = finished.first, Date().timeIntervalSince(latest.startedAt) > 7 * 86_400 {
            return Text("Welcome back. Last \(routine.name) was \(lastOfRoutine.startedAt.formatted(.dateTime.day().month(.wide))); we've kept your numbers.")
        }
        var text = Text("Session \(doneThisWeek + 1) of \(target) this week. Last \(routine.name) was \(lastOfRoutine.startedAt.formatted(.dateTime.weekday(.wide)))")
        if let first = lastOfRoutine.groups.first, let top = topSet(first.sets) {
            let unit = first.exercise.unit(global: settings.unit)
            text = text + Text(", when you got ") + Text(WeightText.pair(top.snapshot, in: unit, step: first.exercise.step(for: unit))).fontWeight(.semibold).foregroundColor(Theme.Colors.textPrimary)
                + Text(" on \(shortName(first.exercise.name)).")
        } else {
            text = text + Text(".")
        }
        return text
    }

    private func topSet(_ sets: [SetEntry]) -> SetEntry? {
        sets.filter { $0.isDone && $0.kind.countsForRecords }.max { $0.snapshot.weightKg < $1.snapshot.weightKg }
    }

    private func shortName(_ name: String) -> String {
        let lower = name.lowercased()
        return lower.split(separator: " ").first.map(String.init) ?? lower
    }

    // MARK: Lifts

    @ViewBuilder private var lifts: some View {
        if cloud.isRestoring {
            VStack(alignment: .leading, spacing: Theme.Spacing.s4) {
                ForEach([0.6, 0.45, 0.7, 0.5], id: \.self) { SkeletonLine(widthFraction: $0) }
            }
        } else if let routine = active.first == nil ? next : nil, !routine.sortedItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text("Today's lifts").sectionLabel().padding(.bottom, Theme.Spacing.s2)
                ForEach(routine.sortedItems) { item in
                    if let ex = item.exercise {
                        NavigationLink(value: ex) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name).font(.body).foregroundStyle(Theme.Colors.textPrimary)
                                Text(liftDetail(ex, sets: item.targetSets)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: Theme.Size.setRow, alignment: .leading)
                            .contentShape(Rectangle())
                            .liftZoomSource(.exercise(ex.id))
                        }
                        .buttonStyle(.plain)
                        Divider().overlay(Theme.Colors.separator)
                    }
                }
            }
        }
    }

    private func liftDetail(_ ex: Exercise, sets: Int) -> String {
        guard let top = topSet(LiftStore.lastSessionSets(for: ex)) else { return "\(sets) sets" }
        let unit = ex.unit(global: settings.unit)
        return "\(sets) sets · last \(WeightText.pair(top.snapshot, in: unit, step: ex.step(for: unit)))"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 0) {
            if let current = active.first {
                Button("Resume \(current.routineName)") { onOpenWorkout(current) }.buttonStyle(PrimaryButtonStyle())
            } else if let next, next.sortedItems.isEmpty {
                Button("Add exercises to \(next.name)") { buildingDay = next }.buttonStyle(PrimaryButtonStyle())
            } else if let next {
                Button("Start \(next.name)") { start(next) }.buttonStyle(PrimaryButtonStyle())
            }
            if active.isEmpty {
                HStack(spacing: Theme.Spacing.s6) {
                    Button("Other routine") { showChooser = true }.buttonStyle(TextActionStyle())
                    Button("Blank workout") { start(nil) }.buttonStyle(TextActionStyle())
                        .liftZoomSource(.workout(reservedBlankID))
                }
            }
        }
        .screenMargins()
        .padding(.vertical, Theme.Spacing.s2)
        .background(Theme.Colors.bgCanvas)
    }

    private func start(_ routine: Routine?) {
        let id = routine == nil ? reservedBlankID : reservedID
        let workout = LiftStore.start(routine, globalUnit: settings.unit, id: id, context: context)
        onOpenWorkout(workout)
        // Fresh reservations for the next workout; the block now tags the active id.
        reservedID = UUID()
        reservedBlankID = UUID()
    }
}

/// One dot per target session: done filled, next accent with a halo, the rest rings.
struct WeekDots: View {
    let done: Int
    let target: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.s3) {
            HStack(spacing: Theme.Spacing.s3) {
                ForEach(0..<max(target, done), id: \.self) { i in
                    Group {
                        if i < done {
                            Circle().fill(Theme.Colors.textPrimary)
                        } else if i == done {
                            Circle().fill(Theme.Colors.accent)
                                .background(Circle().fill(Theme.Colors.accentSoft).padding(-4))
                        } else {
                            Circle().strokeBorder(Theme.Colors.controlStroke, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 10, height: 10)
                }
            }
            Text("\(done) of \(target) this week").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(done) of \(target) sessions this week")
    }
}

/// "Choose a workout" (§3.2): every routine plus Blank; tapping starts at once.
struct ChooseWorkoutSheet: View {
    let routines: [Routine]
    let finished: [Workout]
    let next: Routine?
    var onPick: (Routine?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Your rotation picks up from whatever you do.")
                        .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                        .listRowSeparator(.hidden)
                }
                ForEach(routines) { r in
                    Button { onPick(r) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Theme.Spacing.s2) {
                                    Text(r.name).font(Theme.Fonts.exercise).foregroundStyle(Theme.Colors.textPrimary)
                                    if r.id == next?.id { Text("Next").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Colors.accent) }
                                }
                                Text(lastText(r)).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                        }
                        .frame(minHeight: Theme.Size.setRow)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Button { onPick(nil) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Blank workout").font(Theme.Fonts.exercise).foregroundStyle(Theme.Colors.accent)
                        Text("Add exercises as you go").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: Theme.Size.setRow, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.bgRaised)
            .navigationTitle("Choose a workout")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func lastText(_ r: Routine) -> String {
        if r.sortedItems.isEmpty { return "No exercises yet" }
        guard let last = finished.first(where: { $0.routineID == r.id }) else { return "Not done yet" }
        return "Last \(last.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
    }
}
