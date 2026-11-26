import SwiftUI
import SwiftData
import LiftCore

/// Two tabs: Log (today's workout, open from launch, no setup ever) and History.
/// Finish → summary → Done → a fresh blank Log.
struct RootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var context
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: Tab
    /// Today's open workout, shown in the Log tab.
    @State private var log: Workout?
    @State private var finishing: Workout?
    /// A past workout being logged from History (its own cover, with Close).
    @State private var backLog: Workout?
    @Namespace private var liftNS

    enum Tab: Hashable { case log, history }

    /// `workout`: DEBUG fixtures pass their own; otherwise the open log is found or made.
    init(initialTab: Tab = .log, workout: Workout? = nil) {
        _tab = State(initialValue: initialTab)
        _log = State(initialValue: workout)
    }

    var body: some View {
        TabView(selection: $tab) {
            Group {
                if let w = log {
                    ActiveWorkoutView(workout: w, onFinished: { finishing = $0 }, onDiscard: discard)
                        .id(w.id)
                } else {
                    Theme.Colors.bgCanvas.ignoresSafeArea()
                }
            }
            .tabItem { Label("Log", systemImage: "figure.strengthtraining.traditional") }
            .tag(Tab.log)
            HistoryView(onGoToLog: { tab = .log }, onOpenWorkout: { backLog = $0 })
                .tabItem { Label("History", systemImage: "clock") }
                .tag(Tab.history)
        }
        .overlay { ToastOverlay() }
        .environment(\.liftNamespace, liftNS)
        .fullScreenCover(item: $backLog) { workout in
            ActiveWorkoutView(workout: workout,
                              onClose: { backLog = nil },
                              onFinished: { done in
                                  backLog = nil
                                  finishing = done
                              },
                              onDiscard: discard)
                .overlay { ToastOverlay() }
                .environment(\.liftNamespace, liftNS)
        }
        .fullScreenCover(item: $finishing) { workout in
            FinishView(workout: workout,
                       onDone: {
                           finishing = nil
                           if workout.isBackLog { tab = .history } else { refreshLog() }
                       },
                       onBack: {
                           finishing = nil
                           if workout.isBackLog { backLog = workout }
                       },
                       onDiscard: discard)
            .overlay { ToastOverlay() }
            .environment(\.liftNamespace, liftNS)
        }
        .onAppear { if log == nil { refreshLog() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshLog() }
        }
    }

    /// Finds or makes the open log; a workout idle for 3 h is saved (with
    /// Health) and a new blank one opens, with a 5 s "Saved …" toast (AC 67).
    private func refreshLog() {
        guard finishing == nil, backLog == nil else { return }
        #if DEBUG
        if Fixtures.requested != nil, log != nil { return }
        #endif
        let result = LiftStore.openLog(context)
        if log?.id != result.open.id { log = result.open }
        if let saved = result.autoFinished {
            if settings.healthEnabled == true { HealthSync.save(saved, context: context, toasts: toasts) }
            let day = saved.startedAt.formatted(.dateTime.weekday(.wide))
            toasts.show("Saved \(day)'s workout", action: "View", undo: { tab = .history })
        }
    }

    /// Nothing logged: nothing is saved, no toast (AC 63). Otherwise Discard with
    /// a 5 s Undo; deleted when the window ends.
    private func discard(_ workout: Workout) {
        finishing = nil
        backLog = nil
        if workout.doneSets.isEmpty {
            context.delete(workout)
            _ = LiftStore.save(context)
            if !workout.isBackLog { log = LiftStore.startBlank(context: context) }
            return
        }
        let replacement: Workout? = workout.isBackLog ? nil : LiftStore.startBlank(context: context)
        if let replacement { log = replacement; tab = .log }
        toasts.show("Workout discarded", undo: {
            if let replacement, replacement.allSets.isEmpty {
                context.delete(replacement)
                _ = LiftStore.save(context)
            }
            if workout.isBackLog { backLog = workout } else { log = workout }
        }, onCommit: {
            context.delete(workout)
            _ = LiftStore.save(context)
        })
    }
}
