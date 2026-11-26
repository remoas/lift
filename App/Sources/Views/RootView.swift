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
    /// Which source the workout cover zooms from (iOS 18): Today's block or the mini bar.
    @State private var zoomSource: LiftTransitionID?
    @Namespace private var liftNS
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .environment(\.liftNamespace, liftNS)
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            TodayView(onOpenWorkout: { open($0, from: .workout($0.id)) })
                .safeAreaInset(edge: .bottom) { minimisedBar(tagged: true) }
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(Tab.today)
            HistoryView(onGoToToday: { tab = .today }, onOpenWorkout: { open($0, from: nil) })
                .safeAreaInset(edge: .bottom) { minimisedBar(tagged: false) }
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
            RoutinesView()
                .safeAreaInset(edge: .bottom) { minimisedBar(tagged: false) }
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
                .environment(\.liftNamespace, liftNS)
                .modifier(CoverZoom(source: zoomSource))
        }
        .fullScreenCover(item: $finishing) { workout in
            FinishView(workout: workout,
                       onDone: {
                           finishing = nil
                           tab = .today
                       },
                       onBack: {
                           finishing = nil
                           open(workout, from: nil)
                       },
                       onDiscard: discard)
            .overlay { ToastOverlay() }
            .environment(\.liftNamespace, liftNS)
        }
        .animation(reduceMotion ? Theme.Motion.fadeReduced : Theme.Motion.springZoom, value: presented == nil)
        .onAppear {
            // Reopen a workout that was in progress when the app was closed.
            guard !didRestore else { return }
            didRestore = true
            if presented == nil, let active = activeWorkout { presented = active }
        }
    }

    private func open(_ workout: Workout, from source: LiftTransitionID?) {
        zoomSource = source
        presented = workout
    }

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
    /// `tagged`: only Today's copy is the zoom / matched source, so IDs stay unique.
    @ViewBuilder private func minimisedBar(tagged: Bool) -> some View {
        if presented == nil, finishing == nil, let w = activeWorkout {
            Button { open(w, from: .workoutMini(w.id)) } label: {
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
                .overlay(RoundedRectangle.smooth(Theme.Radius.button).stroke(Theme.Colors.separator, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .modifier(MiniBarSource(id: w.id, tagged: tagged))
            .screenMargins()
            .padding(.bottom, Theme.Spacing.s2)
            .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            .accessibilityLabel("\(w.routineName) in progress. Resume")
        }
    }
}

/// The workout cover zooms from its source on iOS 18; standard cover on 17.
private struct CoverZoom: ViewModifier {
    let source: LiftTransitionID?
    func body(content: Content) -> some View {
        if let source { content.liftZoomDestination(source) } else { content }
    }
}

private struct MiniBarSource: ViewModifier {
    let id: UUID
    let tagged: Bool
    func body(content: Content) -> some View {
        if tagged {
            content.liftZoomSource(.workoutMini(id)).liftMatched(.workoutMini(id))
        } else {
            content
        }
    }
}
