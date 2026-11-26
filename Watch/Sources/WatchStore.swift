import Foundation
import WatchConnectivity
import WatchKit
import LiftCore

/// The watch's copy of today's workout and its link to the phone.
///
/// The phone's store is the database. The watch edits its copy at once
/// (optimistic), keeps every command in `pending` (saved to disk) until a
/// phone snapshot lists it as applied, and rebases each snapshot on top of
/// what's still pending, so nothing logged on the wrist is lost offline.
@MainActor
@Observable
final class WatchStore: NSObject {
    private(set) var live: LiveWorkout
    private(set) var pending: [LiveEnvelope]
    /// A snapshot has arrived from the phone at least once.
    private(set) var heardFromPhone: Bool
    /// The one toast: "Rest skipped · Undo", "Workout discarded · Undo" (5 s).
    private(set) var toast: WatchToast?
    /// Rest reached zero for this exercise's page; stays until a log or a tap.
    private(set) var restUpFor: UUID?
    /// "New best 205 × 5" for about 2 s, then rest.
    private(set) var newBest: (exerciseID: UUID, text: String)?
    /// The phone isn't reachable right now ("On this Watch only.").
    private(set) var phoneReachable = true
    /// The workout session couldn't start because Health is off.
    private(set) var healthOff = false
    /// The exercise page on screen (drives auto-count).
    private(set) var pageExerciseID: UUID?
    /// Auto-count is running for this exercise.
    private(set) var countingFor: UUID?
    /// Crown correction on top of the live count.
    var countOffset = 0
    /// Always-On preview for the w11 capture.
    let forceDimmed: Bool
    /// Motion can count here (screenshot frames act as a real watch).
    var motionAvailable: Bool { fixture || motion.isAvailable }
    /// Screenshot frames only: a live count to show.
    @ObservationIgnored var fixtureCount: Int?

    #if DEBUG
    /// Screenshot frames: put the store in a state that needs time or motion.
    func applyFixture(_ f: WatchFixtures.Frame) {
        fixtureCount = f.countedReps
        if f.restUp { restUpFor = live.exercises.first?.id }
        if let b = f.newBest, let id = live.exercises.first?.id { newBest = (id, b) }
        if f.skipToast { toast = WatchToast(text: "Rest skipped", undo: {}) }
    }
    #endif

    let workout = WorkoutManager()
    let motion = MotionCounter()
    private let fixture: Bool
    private var toastTask: Task<Void, Never>?
    private var bestTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("live.json")
    }

    private struct Saved: Codable { var live: LiveWorkout; var pending: [LiveEnvelope]; var heard: Bool }

    init(fixture: LiveWorkout? = nil, dimmed: Bool = false, unreachable: Bool = false) {
        // Index the catalog off the main thread so Add exercise opens instantly.
        Task.detached(priority: .utility) { _ = WatchLibrary.index; _ = WatchLibrary.byID }
        self.fixture = fixture != nil
        forceDimmed = dimmed
        if let fixture {
            live = fixture; pending = []; heardFromPhone = true
        } else if let data = try? Data(contentsOf: Self.fileURL), let saved = LiveCoding.decode(Saved.self, from: data) {
            live = saved.live; pending = saved.pending; heardFromPhone = saved.heard
        } else {
            live = LiveWorkout(unit: Locale.current.measurementSystem == .metric ? .kg : .lb)
            pending = []; heardFromPhone = false
        }
        super.init()
        phoneReachable = !unreachable
        if live.endedAt != nil { startFresh() }
    }

    func activate() {
        guard !fixture, WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        phoneReachable = WCSession.default.isReachable
        if let data = WCSession.default.receivedApplicationContext["w"] as? Data { receive(data) }
        scheduleRestAlert()
    }

    private func persist() {
        guard !fixture, let data = LiveCoding.encode(Saved(live: live, pending: pending, heard: heardFromPhone)) else { return }
        try? FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    // MARK: Sending

    private func send(_ command: LiveCommand) {
        let env = LiveEnvelope(workoutID: live.workoutID, command: command)
        LiveReducer.apply(command, to: &live)
        pending.append(env)
        persist()
        deliver(env)
    }

    private func deliver(_ env: LiveEnvelope) {
        guard !fixture, WCSession.isSupported(), WCSession.default.activationState == .activated,
              let data = LiveCoding.encode(env) else { return }
        let s = WCSession.default
        if s.isReachable {
            s.sendMessage(["c": data], replyHandler: { _ in }, errorHandler: { _ in s.transferUserInfo(["c": data]) })
        } else {
            s.transferUserInfo(["c": data])
        }
    }

    // MARK: Receiving

    fileprivate func receive(_ data: Data) {
        guard let server = LiveCoding.decode(LiveWorkout.self, from: data) else { return }
        // The phone finished the workout this watch is timing: end it at the same moment.
        if let id = workout.workoutID, let end = server.finishedElsewhere(id) { endSession(at: end, save: server.healthEnabled != false) }
        let wasRest = live.rest
        let r = LiveReducer.rebase(server, pending: pending)
        live = r.workout
        pending = r.pending
        heardFromPhone = true
        persist()
        if live.rest != wasRest { scheduleRestAlert() }
        if countingFor == nil, live.rest == nil { arm() }
    }

    // MARK: Actions

    var current: Int { live.currentIndex ?? 0 }

    func add(_ ex: LiveExercise) {
        startSessionIfNeeded()
        // Recents come from the phone with their history; library rows are new here.
        send(.addExercise(live.recents.contains { $0.id == ex.id } ? ex : fromLibrary(ex)))
    }

    /// What the Log set button saves: the live count when counting, else the reps.
    func liveCount(for ex: LiveExercise) -> Int? {
        if let n = fixtureCount, ex.id == pageExerciseID { return n + countOffset }
        guard countingFor == ex.id, motion.count >= 2 || countOffset != 0 else { return nil }
        return max(0, motion.count + countOffset)
    }

    /// Logs a set. Haptics here only (the logging device owns them): log
    /// click, target hit, new best. Starts the shared rest unless rest is Off.
    func log(exercise: LiveExercise, weight: Double, reps: Int) {
        startSessionIfNeeded()
        let wasHit = exercise.targetHit
        var set = exercise.nextSet
        set.weight = weight
        set.reps = reps
        set.doneAt = Date()
        set.source = "watch"
        let records = exercise.newRecords(weight: weight, reps: reps, workoutID: live.workoutID, setID: set.id)
        send(.logSet(exerciseID: exercise.id, set: set))
        restUpFor = nil
        countOffset = 0
        motion.stop()
        countingFor = nil
        let updated = live.exercises.first { $0.id == exercise.id }
        if !records.isEmpty {
            WKInterfaceDevice.current().play(.success)
            showNewBest(exercise.id, text: BeatItText.number(SetTarget(weight: weight, reps: reps), bodyweight: exercise.bodyweight))
        } else if !wasHit, updated?.targetHit == true {
            WKInterfaceDevice.current().play(.directionUp)
        } else {
            WKInterfaceDevice.current().play(.click)
        }
        let nextText = updated.map { BeatItText.number($0.prefill, bodyweight: $0.bodyweight) }
        if exercise.restSeconds > 0 {
            send(.rest(RestState(seconds: exercise.restSeconds, setID: set.id, exercise: exercise.name, next: nextText, origin: .watch)))
        } else if live.rest != nil {
            send(.rest(nil))
        }
        scheduleRestAlert()
        if live.rest == nil { arm() }
    }

    private func showNewBest(_ id: UUID, text: String) {
        newBest = (id, text)
        bestTask?.cancel()
        bestTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.newBest = nil
        }
    }

    private func showToast(_ t: WatchToast) {
        toast = t
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self else { return }
            let done = self.toast
            self.toast = nil
            done?.onCommit?()
        }
    }

    func undoToast() {
        toastTask?.cancel()
        let t = toast
        toast = nil
        t?.undo()
    }

    /// Back to the exercise after "Rest's up".
    func dismissRestUp() { restUpFor = nil; arm() }

    // MARK: Auto-count

    func showPage(_ ex: LiveExercise?) {
        pageExerciseID = ex?.id
        arm()
    }

    /// Runs the counter on the page on screen when nothing else is going on.
    func arm() {
        motion.stop()
        countingFor = nil
        countOffset = 0
        guard !fixture, let id = pageExerciseID, let ex = live.exercises.first(where: { $0.id == id }),
              ex.countable, motion.isAvailable, live.rest.map({ $0.isOver(at: Date()) }) ?? true else { return }
        countingFor = id
        motion.start()
    }

    func setRest(_ exercise: LiveExercise, seconds: Int) { send(.setRest(exerciseID: exercise.id, seconds: seconds)) }

    func addRest(_ seconds: Int) {
        guard let r = live.rest else { return }
        send(.rest(r.adding(seconds)))
        scheduleRestAlert()
    }

    /// Skip with "Rest skipped · Undo" (5 s); Undo puts the remaining time back.
    func skipRest() {
        guard let r = live.rest else { return }
        let left = r.remaining(at: Date())
        send(.rest(nil))
        scheduleRestAlert()
        arm()
        showToast(WatchToast(text: "Rest skipped", undo: { [weak self] in
            guard let self, left > 1 else { return }
            var back = r
            back.countdown.endsAt = Date().addingTimeInterval(left)
            self.send(.rest(back))
            self.scheduleRestAlert()
            self.arm()
        }))
    }

    /// Discard from •••: nothing is asked; it happens when the 5 s Undo ends.
    func discard() {
        let before = live
        var shown = live
        shown.exercises = []
        shown.rest = nil
        live = shown
        showToast(WatchToast(text: "Workout discarded", undo: { [weak self] in self?.live = before }, onCommit: { [weak self] in
            guard let self else { return }
            self.live = before
            self.send(.discard)
            self.endSession(at: Date(), save: false)
            self.startFresh()
        }))
    }

    /// Ends the workout: the phone stores it; the watch saves it to Health.
    func finish() {
        let end = Date()
        send(.finish(at: end))
        endSession(at: end, save: live.healthEnabled != false)
    }

    /// After the summary: a blank log until the phone sends its new one.
    func startFresh() {
        var next = LiveWorkout(unit: live.unit, restDefault: live.restDefault)
        next.recents = live.recents
        next.healthEnabled = live.healthEnabled
        next.lastFinishedID = live.workoutID
        next.lastFinishedAt = live.endedAt
        live = next
        persist()
    }

    // MARK: Workout session (heart rate, background time, Health)

    func startSessionIfNeeded() {
        guard !fixture, !workout.isRunning else { return }
        let id = live.workoutID
        Task {
            if await workout.start(workoutID: id) {
                healthOff = false
                send(.watchSession(active: true))
                watchForStale()
            } else {
                healthOff = true
            }
        }
    }

    private func endSession(at end: Date, save: Bool) {
        guard workout.isRunning else { return }
        let id = workout.workoutID
        staleTask?.cancel()
        Task {
            let hk = await workout.end(at: end, save: save)
            guard save, let id else { return }
            let env = LiveEnvelope(workoutID: id, command: .healthSaved(healthKitID: hk))
            pending.append(env)
            persist()
            deliver(env)
        }
    }

    /// Same 3 h auto-finish as the phone, so a forgotten session doesn't run all day.
    private func watchForStale() {
        staleTask?.cancel()
        staleTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                if let last = self.live.doneSets.compactMap(\.doneAt).max(), Date().timeIntervalSince(last) > 3 * 3600 {
                    self.send(.finish(at: last))
                    self.endSession(at: last, save: self.live.healthEnabled != false)
                    self.startFresh()
                    return
                }
            }
        }
    }

    // MARK: Rest alert

    /// The watch buzzes when rest ends while its workout session runs (wrist
    /// down too); otherwise the phone's notification does (RestAlertPolicy).
    private func scheduleRestAlert() {
        restTask?.cancel()
        guard let r = live.rest, !r.isOver(at: Date()) else { return }
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(r.remaining(at: Date())))
            guard !Task.isCancelled, let self, self.live.rest == r else { return }
            // .notification is the watch's warning-family haptic, distinct from
            // log (.click), target hit (.directionUp) and new best (.success).
            if self.workout.isRunning || WKApplication.shared().applicationState == .active {
                WKInterfaceDevice.current().play(.notification)
            }
            self.restUpFor = self.pageExerciseID ?? self.live.exercises[safe: self.current]?.id
        }
    }

    // MARK: Library

    /// Catalog search sits behind ExerciseFinder so the shared LiftCore search
    /// (spec.md §10, quicklog-qa) drops in without touching the views.
    @ObservationIgnored var finder: any ExerciseFinder = CatalogFinder()

    /// A library pick in today's unit and rest default.
    func fromLibrary(_ e: LiveExercise) -> LiveExercise {
        guard let entry = WatchLibrary.entry[e.id] else { return e }
        var x = LiveExercise(library: entry, unit: live.unit, restDefault: live.restDefault)
        x.name = e.name
        return x
    }

    /// Recents first (with their Last line), then the library, searchable.
    func pickerRows(query: String) -> (recents: [LiveExercise], all: [LiveExercise]) {
        let inToday = Set(live.exercises.map(\.id))
        let q = query.trimmingCharacters(in: .whitespaces)
        let recents = live.recents.filter { !inToday.contains($0.id) && (q.isEmpty || finder.matches($0.name, q)) }
        let recentIDs = Set(recents.map(\.id))
        let all = finder.find(q, limit: q.isEmpty ? 40 : 60).compactMap { WatchLibrary.byID[$0] }
            .filter { !inToday.contains($0.id) && !recentIDs.contains($0.id) }
        return (recents, Array(all))
    }
}

struct WatchToast {
    var text: String
    var undo: () -> Void
    var onCommit: (() -> Void)? = nil
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension WatchStore: WCSessionDelegate {
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let r = session.isReachable
        Task { @MainActor in self.phoneReachable = r }
    }

    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            if let data = session.receivedApplicationContext["w"] as? Data { self.receive(data) }
            // Anything queued while inactive goes again; the phone ignores repeats.
            for env in self.pending { self.deliver(env) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let data = applicationContext["w"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let data = message["w"] as? Data else { return }
        Task { @MainActor in self.receive(data) }
    }
}

/// How the Add exercise list searches the catalog. Swap point for the shared
/// LiftCore search from spec.md §10; the watch keeps no ranking of its own.
protocol ExerciseFinder {
    /// Catalog ids, best first. Empty query = the whole list in catalog order.
    func find(_ query: String, limit: Int) -> [UUID]
    /// Whether a recent's name matches the query.
    func matches(_ name: String, _ query: String) -> Bool
}

/// Interim: today's LiftCore `Search` over the bundled catalog.
struct CatalogFinder: ExerciseFinder {
    func find(_ query: String, limit: Int) -> [UUID] {
        Search.run(WatchLibrary.index, query: query).prefix(limit).map(\.id)
    }
    func matches(_ name: String, _ query: String) -> Bool {
        Search.fold(name).contains(Search.fold(query))
    }
}

/// The bundled exercise catalog (LiftCore), indexed once.
enum WatchLibrary {
    static let entry: [UUID: LibraryExercise] = Dictionary(ExerciseLibrary.bundled.exercises.map { ($0.rowID, $0) }, uniquingKeysWith: { a, _ in a })
    static let byID: [UUID: LiveExercise] = entry.mapValues {
        var e = LiveExercise(library: $0, unit: .lb, restDefault: 120)
        e.name = WatchText.displayName($0.name, variant: $0.variant)
        return e
    }
    static let index: [SearchEntry] = ExerciseLibrary.bundled.exercises.map {
        SearchEntry(id: $0.rowID, name: $0.name, variant: $0.variant, aliases: $0.aliases, primary: $0.primaryMuscles, secondary: $0.secondaryMuscles, equipment: $0.equipment)
    }
}

enum WatchText {
    static func displayName(_ name: String, variant: String) -> String {
        variant.isEmpty || name.localizedCaseInsensitiveContains(variant) ? name : "\(name) (\(variant))"
    }

    static func rest(_ seconds: Int) -> String { RestCountdown.format(TimeInterval(seconds)) }
}
