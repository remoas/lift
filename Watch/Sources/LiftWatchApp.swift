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
            let s = WatchStore(fixture: f.live, dimmed: f.dimmed, unreachable: f.unreachable)
            s.applyFixture(f)
            _store = State(initialValue: s)
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
