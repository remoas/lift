import SwiftUI
import SwiftData
import LiftCore

/// §3.9 History, grouped by Monday-start week.
struct HistoryView: View {
    var onGoToLog: () -> Void
    var onOpenWorkout: (Workout) -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(ToastCenter.self) private var toasts
    @Query(filter: #Predicate<Workout> { $0.endedAt != nil }, sort: \Workout.startedAt, order: .reverse)
    private var finished: [Workout]
    @State private var backLogging = false
    @State private var showSettings = false

    private var weeks: [(start: Date, workouts: [Workout])] {
        let grouped = Dictionary(grouping: finished) { Week.start(of: $0.startedAt) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0]!.sorted { $0.startedAt > $1.startedAt }) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if finished.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s3) {
                        Text("Your workouts land here once you finish one. Every set, every best, kept on this iPhone and backed up to iCloud.")
                            .font(.body).foregroundStyle(Theme.Colors.textSecondary)
                        Button("Go to Log", action: onGoToLog).buttonStyle(TextActionStyle())
                        Spacer()
                    }
                    .screenMargins()
                    .padding(.top, Theme.Spacing.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    List {
                        ForEach(weeks, id: \.start) { week in
                            Section {
                                ForEach(week.workouts) { w in
                                    NavigationLink(value: w) { row(w) }
                                        .listRowBackground(Theme.Colors.bgCanvas)
                                        .swipeActions { Button("Delete", role: .destructive) { delete(w) } }
                                }
                            } header: {
                                Text(label(week.start))
                                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary).textCase(nil)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(Theme.Colors.bgCanvas)
            .navigationTitle("History")
            .navigationDestination(for: Workout.self) { WorkoutDetailView(workout: $0) }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").frame(width: Theme.Size.hit, height: Theme.Size.hit)
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { backLogging = true } label: { Image(systemName: "plus").frame(width: Theme.Size.hit, height: Theme.Size.hit) }
                        .accessibilityLabel("Log a past workout")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $backLogging) {
                BackLogSheet { date in
                    backLogging = false
                    onOpenWorkout(LiftStore.startBlank(at: date, backLog: true, context: context))
                }
            }
        }
    }

    private func row(_ w: Workout) -> some View {
        let bests = LiftStore.bestSetIDs(in: w).count
        let minutes = Int(((w.endedAt ?? w.startedAt).timeIntervalSince(w.startedAt) / 60).rounded())
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title(w)).font(.body).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                Text("\(w.startedAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) · \(minutes) min")
                    .font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
            if bests > 0 {
                Text("\(bests) best\(bests == 1 ? "" : "s")").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.accent)
            }
        }
        .frame(minHeight: Theme.Size.setRow)
    }

    /// Old routine names stay; quick-log workouts are named by what was done.
    static func title(_ w: Workout) -> String {
        if !w.routineName.isEmpty, w.routineName != "Workout" { return w.routineName }
        let names = w.groups.map(\.exercise.name)
        guard let first = names.first else { return "Workout" }
        return names.count == 1 ? first : "\(first) + \(names.count - 1) more"
    }

    private func label(_ start: Date) -> String {
        let this = Week.start(of: Date())
        if start == this { return "This week" }
        if start == this.addingTimeInterval(-7 * 86_400) { return "Last week" }
        return "Week of \(start.formatted(.dateTime.day().month(.abbreviated)))"
    }

    private func delete(_ w: Workout) {
        // Undo restores the same workout: deletion is deferred until the toast ends.
        let snapshot = WorkoutArchive(w)
        context.delete(w)
        _ = LiftStore.save(context)
        // Labelled: an unlabelled trailing closure binds to `onCommit` (Swift 5 backward
        // matching), which "restored" the item when the Undo window ended (Ben, 1.0 (2)).
        toasts.show("Workout deleted", undo: {
            snapshot.restore(into: context)
        })
    }
}

/// Values needed to put a deleted workout back exactly (same UUIDs).
struct WorkoutArchive {
    let id: UUID, routineID: UUID?, routineName: String, startedAt: Date, endedAt: Date?, healthKitID: String?, note: String, isBackLog: Bool
    let sets: [(LiftStore.RemovedSet, Exercise)]

    @MainActor init(_ w: Workout) {
        id = w.id; routineID = w.routineID; routineName = w.routineName; startedAt = w.startedAt; endedAt = w.endedAt
        healthKitID = w.healthKitID; note = w.note; isBackLog = w.isBackLog
        sets = w.allSets.compactMap { s in s.exercise.map { (LiftStore.RemovedSet(s), $0) } }
    }

    @MainActor func restore(into context: ModelContext) {
        let w = Workout(startedAt: startedAt)
        w.routineID = routineID; w.routineName = routineName
        w.id = id; w.endedAt = endedAt; w.healthKitID = healthKitID; w.note = note; w.isBackLog = isBackLog
        context.insert(w)
        for (r, ex) in sets {
            let s = r.makeEntry(exercise: ex)
            context.insert(s)
            s.workout = w
        }
        _ = LiftStore.save(context)
    }
}

/// Back-log: pick the date, then log as usual (no rest timer).
struct BackLogSheet: View {
    var onStart: (Date) -> Void
    @State private var date = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.compact)
            }
            .navigationTitle("Log a past workout")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button("Start logging") { onStart(date) }
                    .buttonStyle(PrimaryButtonStyle()).screenMargins()
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}

/// Workout detail: edit sets after the fact; bests recompute.
struct WorkoutDetailView: View {
    let workout: Workout
    @Environment(\.modelContext) private var context
    @State private var editing: SetEntry?

    var body: some View {
        let bests = LiftStore.bestSetIDs(in: workout)
        List {
            ForEach(workout.groups, id: \.exercise.id) { g in
                Section(g.exercise.name) {
                    ForEach(Array(g.sets.enumerated()), id: \.element.id) { i, s in
                        Button { editing = s } label: {
                            HStack {
                                Text("\(i + 1)").font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textTertiary).frame(width: 24, alignment: .leading)
                                Text("\(UnitMath.format(s.weight)) \(s.unit.symbol) × \(s.reps)").font(Theme.Fonts.setValue).foregroundStyle(Theme.Colors.textPrimary)
                                if s.kind != .working { Text(s.kind.label).font(Theme.Fonts.secondary).foregroundStyle(Theme.Colors.textSecondary) }
                                Spacer()
                                if bests.contains(s.id) { Text("Best").font(.footnote.weight(.semibold)).foregroundStyle(Theme.Colors.accent) }
                            }
                            .frame(minHeight: Theme.Size.groupedRow)
                        }
                    }
                }
            }
            if !workout.note.isEmpty { Section("Note") { Text(workout.note) } }
        }
        .navigationTitle(HistoryView.title(workout))
        .sheet(item: $editing) { s in
            SetEditorSheet(entry: s, title: s.exercise?.name ?? "", lastTime: nil, noLastText: nil) { _ = LiftStore.save(context) }
        }
    }
}
