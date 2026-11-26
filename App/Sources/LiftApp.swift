import SwiftUI
import SwiftData

@main
struct LiftApp: App {
    @State private var settings: AppSettings
    @State private var toasts = ToastCenter()
    @State private var cloud = CloudSyncMonitor()
    private let container: ModelContainer

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
        _settings = State(initialValue: AppSettings())
        let context = container.mainContext
        LiftStore.ensureRoutines(context)
        LiftStore.mergeLibrary(context: context)
        LiftStore.dedupe(context)
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
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if let fixture = Fixtures.requested { FixtureRoot(frame: fixture) } else { RootView() }
        #else
        RootView()
        #endif
    }
}
