import SwiftUI
import LiftCore

@main
struct LiftWatchApp: App {
    @State private var store: WatchStore
    private let frame: WatchFixtures.Frame?

    init() {
        #if DEBUG
        if let f = WatchFixtures.requested {
            frame = f
            _store = State(initialValue: WatchStore(fixture: f.live))
            return
        }
        #endif
        frame = nil
        _store = State(initialValue: WatchStore())
    }

    var body: some Scene {
        WindowGroup {
            WatchRoot(frame: frame)
                .environment(store)
                .onAppear { store.activate() }
        }
    }
}
