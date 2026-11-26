import SwiftUI
import SwiftData
import LiftCore

/// Today / History / Routines, the first-run gate, and the workout flow:
/// full-screen workout → (Close minimises to a bar) → Finish summary → Today.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Query(filter: #Predicate<Workout> { $0.endedAt == nil }, sort: \Workout.startedAt, order: .reverse)
    private var activeWorkouts: [Workout]

    @State private var tab: Tab
    @State private var presented: Workout?
    @State private var finishing: Workout?
    @State private var didRestore = false
    /// A discarded workout stays in memory (and the store) until its Undo
    /// window ends, hidden from Today, then it is deleted.
    @State private var pendingDiscard: Workout?

    private var activeWorkout: Workout? { activeWorkouts.first { $0 !== pendingDiscard } }

    enum Tab: Hashable { case today, history, routines }

    init(initialTab: Tab = .today) { _tab = State(initialValue: initialTab) }

    var body: some View {
        Group {
            if settings.hasOnboarded {
                tabs
            } else {
                SetupFlow { tab = .today }
            }
        }
        .overlay { ToastOverlay() }
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            TodayView(onOpenWorkout: open)
                .safeAreaInset(edge: .bottom) { minimisedBar }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)
            HistoryView(onGoToToday: { tab = .today }, onOpenWorkout: open)
                .safeAreaInset(edge: .bottom) { minimisedBar }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            RoutinesView()
                .safeAreaInset(edge: .bottom) { minimisedBar }
                .tabItem { Label("Routines", systemImage: "list.bullet") }
                .tag(Tab.routines)
        }
        .fullScreenCover(item: $presented) { workout in
            ActiveWorkoutView(workout: workout,
                              onClose: { presented = nil },
                              onFinished: { done in
                                  presented = nil
                                  finishing = done
                              },
                              onDiscard: discard)
                .overlay { ToastOverlay() }
        }
        .fullScreenCover(item: $finishing) { workout in
            FinishView(workout: workout,
                       onDone: {
                           finishing = nil
                           tab = .today
                       },
                       onBack: {
                           finishing = nil
                           presented = workout
                       },
                       onDiscard: discard)
            .overlay { ToastOverlay() }
        }
        .onAppear {
            // Reopen a workout that was in progress when the app was closed.
            guard !didRestore else { return }
            didRestore = true
            if presented == nil, let active = activeWorkout { presented = active }
        }
    }

    private func open(_ workout: Workout) { presented = workout }

    /// Discard: no alert. Back to Today with a 5 s Undo; deleted when it ends.
    private func discard(_ workout: Workout) {
        presented = nil
        finishing = nil
        tab = .today
        pendingDiscard = workout
        let name = workout.routineName.isEmpty ? "Workout" : workout.routineName
        toasts.show("\(name) discarded", undo: {
            pendingDiscard = nil
            presented = workout
        }, onCommit: {
            if pendingDiscard === workout { pendingDiscard = nil }
            context.delete(workout)
            _ = LiftStore.save(context)
        })
    }

    /// "Push · 18:42 · Resume" while a workout is minimised.
    @ViewBuilder private var minimisedBar: some View {
        if presented == nil, finishing == nil, let w = activeWorkout {
            Button { presented = w } label: {
                HStack(spacing: Theme.Spacing.s2) {
                    Text(w.routineName.isEmpty ? "Workout" : w.routineName).font(Theme.Fonts.label)
                    Text("·").foregroundStyle(Theme.Colors.textTertiary)
                    Text(timerInterval: w.startedAt...Date.distantFuture, countsDown: false)
                        .font(Theme.Fonts.bodyNumber)
                    Spacer()
                    Text("Resume").font(Theme.Fonts.label).foregroundStyle(Theme.Colors.accent)
                }
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.s4)
                .frame(minHeight: Theme.Size.setRow)
                .background(Theme.Colors.bgRaised, in: .continuous(Theme.Radius.button))
                .overlay(Shape.continuous(Theme.Radius.button).stroke(Theme.Colors.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .screenMargins()
            .padding(.bottom, Theme.Spacing.s2)
            .accessibilityLabel("\(w.routineName) in progress. Resume")
        }
    }
}
