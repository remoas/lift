import SwiftUI
import SwiftData

@main
struct LiftApp: App {
    @State private var settings: AppSettings
    @State private var toasts = ToastCenter()
    @State private var cloud = CloudSyncMonitor()
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if let fixture = Fixtures.requested {
            let (container, settings) = Fixtures.make(fixture)
            self.container = container
            _settings = State(initialValue: settings)
            return
        }
        #endif
        container = LiftStore.makeContainer()
        let settings = AppSettings()
        _settings = State(initialValue: settings)
        let context = container.mainContext
        LiftStore.mergeLibrary(context: context)
        LiftStore.dedupe(context)
        PhoneSync.shared.start(container: container, settings: settings)
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(settings)
                .environment(toasts)
                .environment(cloud)
                .tint(Theme.Colors.accent)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Pending discards/deletes become final rather than lingering.
            if phase == .background { toasts.flush() }
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if let fixture = Fixtures.requested { FixtureRoot(frame: fixture) } else { RootView() }
        #else
        RootView()
        #endif
    }
}
