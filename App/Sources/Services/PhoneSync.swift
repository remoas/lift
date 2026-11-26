import Foundation
import SwiftData
import WatchConnectivity
import LiftCore

extension Notification.Name {
    /// The watch changed today's log in a way the screens must re-read (finish).
    static let liftWatchFinished = Notification.Name("lift.watchFinished")
    /// Discarded on the watch; `object` is the fresh open log.
    static let liftWatchDiscarded = Notification.Name("lift.watchDiscarded")
}

/// The phone's end of the live link to the watch (WatchConnectivity).
///
/// - Phone → watch: the whole live workout (small JSON) as the application
///   context (latest state, delivered whenever the watch app wakes) and as a
///   message when the watch is reachable (instant).
/// - Watch → phone: commands, by message when reachable, otherwise by
///   transferUserInfo (queued, delivered in order, survives relaunches).
/// - Rest alerts: RestAlertPolicy picks one device, so there is one buzz.
@MainActor
final class PhoneSync: NSObject {
    static let shared = PhoneSync()

    private var container: ModelContainer?
    private var settings: AppSettings?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }
    private var pushTask: Task<Void, Never>?
    private var lastSent: Data?
    private var applied: [UUID] = UserDefaults.standard.stringArray(forKey: "lift.live.applied")?.compactMap(UUID.init) ?? []

    /// The rest both devices show.
    private(set) var rest: RestState?
    /// The watch is running a workout session for today's log.
    private(set) var watchSessionActive = false
    /// The open WorkoutSession's hook for rests started on the watch.
    var onRemoteRest: ((RestState?) -> Void)?

    func start(container: ModelContainer, settings: AppSettings) {
        self.container = container
        self.settings = settings
        guard let session else { return }
        session.delegate = self
        session.activate()
        NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedulePush() }
        }
    }

    private var watchReachable: Bool { session?.isReachable ?? false }

    /// The watch, not the phone, buzzes at the end of rest.
    var watchAlerts: Bool {
        RestAlertPolicy.plan(rest: rest, now: Date(), watchSessionActive: watchSessionActive, watchReachable: watchReachable).watchAlertAt != nil
    }

    // MARK: Rest

    /// A rest started, extended or skipped on the phone.
    func setLocalRest(_ r: RestState?) {
        rest = r
        scheduleAlert()
        schedulePush(now: true)
    }

    /// +30s from the Lock Screen or Island: this break only, never restSec.
    func addRestFromActivity(_ seconds: Int) {
        guard let r = rest, !r.isOver(at: Date()) else { return }
        let longer = r.adding(seconds)
        setLocalRest(longer)
        onRemoteRest?(longer)
        RestActivityController.shared.show(start: longer.countdown.endsAt.addingTimeInterval(-longer.countdown.total), end: longer.countdown.endsAt)
    }

    /// Skip from the Lock Screen or Island: no confirm, no alert.
    func skipRestFromActivity() {
        setLocalRest(nil)
        onRemoteRest?(nil)
        RestActivityController.shared.skipped()
    }

    private func scheduleAlert() {
        let plan = RestAlertPolicy.plan(rest: rest, now: Date(), watchSessionActive: watchSessionActive, watchReachable: watchReachable)
        if let at = plan.phoneNotificationAt, let rest {
            RestNotifications.schedule(at: at, body: rest.alertBody)
        } else {
            RestNotifications.cancel()
        }
    }

    // MARK: Push

    private func schedulePush(now: Bool = false) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            if !now { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            self?.push()
        }
    }

    private func push() {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let container, let settings else { return }
        let live = LiveBridge.snapshot(container.mainContext, unit: settings.unit, restDefault: settings.workingRestSeconds,
                                       healthEnabled: settings.healthEnabled, rest: rest, applied: applied)
        watchSessionActive = live.watchSessionActive
        guard let data = LiveCoding.encode(live), data != lastSent else { return }
        lastSent = data
        try? session.updateApplicationContext(["w": data])
        if session.isReachable { session.sendMessage(["w": data], replyHandler: nil, errorHandler: nil) }
    }

    // MARK: Receive

    private func receive(_ data: Data) {
        guard let env = LiveCoding.decode(LiveEnvelope.self, from: data), let container, let settings else { return }
        guard !applied.contains(env.id) else { schedulePush(now: true); return }
        let context = container.mainContext
        let effect = LiveBridge.apply(env, context, unit: settings.unit, restDefault: settings.workingRestSeconds)
        applied = LiveReducer.remember(env.id, in: applied)
        UserDefaults.standard.set(applied.map(\.uuidString), forKey: "lift.live.applied")
        switch effect {
        case .none: break
        case .rest(let r):
            let wasRunning = rest.map { !$0.isOver(at: Date()) } ?? false
            rest = r
            scheduleAlert()
            onRemoteRest?(r)
            // The same Activity follows rests started, extended or skipped on the watch.
            if let r {
                RestActivityController.shared.show(start: r.countdown.endsAt.addingTimeInterval(-r.countdown.total), end: r.countdown.endsAt)
            } else if wasRunning {
                RestActivityController.shared.skipped()
            } else {
                RestActivityController.shared.end()
            }
        case .finished(let w):
            RestActivityController.shared.end()
            rest = nil
            scheduleAlert()
            onRemoteRest?(nil)
            if HealthOwnership.phoneShouldSave(healthEnabled: settings.healthEnabled, watchRanSession: w.device == "Watch", watchSaveFailed: false, alreadySaved: w.healthKitID != nil) {
                HealthSync.save(w, context: context, toasts: nil)
            }
            NotificationCenter.default.post(name: .liftWatchFinished, object: w)
        case .discarded(let w):
            // The watch already gave its 5 s Undo. A fresh log first, so the
            // screens never hold the deleted one.
            RestActivityController.shared.end()
            rest = nil
            scheduleAlert()
            onRemoteRest?(nil)
            let fresh = LiftStore.startBlank(context: context)
            NotificationCenter.default.post(name: .liftWatchDiscarded, object: fresh)
            context.delete(w)
            _ = LiftStore.save(context)
        case .watchSession(let active):
            watchSessionActive = active
            scheduleAlert()
        case .healthFailed(let w):
            if HealthOwnership.phoneShouldSave(healthEnabled: settings.healthEnabled, watchRanSession: true, watchSaveFailed: true, alreadySaved: w.healthKitID != nil) {
                HealthSync.save(w, context: context, toasts: nil)
            }
        }
        lastSent = nil
        schedulePush(now: true)
    }
}

extension PhoneSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.schedulePush(now: true) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching watches: reactivate for the new one.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.scheduleAlert()
            self.lastSent = nil
            self.schedulePush(now: true)
        }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSent = nil; self.schedulePush(now: true) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["c"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message["c"] as? Data else { replyHandler([:]); return }
        Task { @MainActor in
            self.receive(data)
            replyHandler(["ok": true])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["c"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}
