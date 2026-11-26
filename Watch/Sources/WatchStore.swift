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
    /// "Logged 185 × 9 · Undo" (5 s).
    private(set) var undo: (text: String, setID: UUID, exerciseID: UUID)?
    private(set) var restUp = false

    let workout = WorkoutManager()
    let motion = MotionCounter()
    private let fixture: Bool
    private var undoTask: Task<Void, Never>?
    private var restTask: Task<Void, Never>?
    private var staleTask: Task<Void, Never>?

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("live.json")
    }

    private struct Saved: Codable { var live: LiveWorkout; var pending: [LiveEnvelope]; var heard: Bool }

    init(fixture: LiveWorkout? = nil) {
        self.fixture = fixture != nil
        if let fixture {
            live = fixture; pending = []; heardFromPhone = true
        } else if let data = try? Data(contentsOf: Self.fileURL), let saved = LiveCoding.decode(Saved.self, from: data) {
            live = saved.live; pending = saved.pending; heardFromPhone = saved.heard
        } else {
            live = LiveWorkout(unit: Locale.current.measurementSystem == .metric ? .kg : .lb)
            pending = []; heardFromPhone = false
        }
        super.init()
        if live.endedAt != nil { startFresh() }
    }

    func activate() {
        guard !fixture, WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
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
    }

    // MARK: Actions

    var current: Int { live.currentIndex ?? 0 }

    func add(_ ex: LiveExercise) {
        startSessionIfNeeded()
        // Recents come from the phone with their history; library rows are new here.
        send(.addExercise(live.recents.contains { $0.id == ex.id } ? ex : fromLibrary(ex)))
    }

    /// Logs a set; starts the shared rest. Haptic when this set hits the target.
    func log(exercise: LiveExercise, weight: Double, reps: Int) {
        startSessionIfNeeded()
        let wasHit = exercise.targetHit
        var set = exercise.nextSet
        set.weight = weight
        set.reps = reps
        set.doneAt = Date()
        set.source = "watch"
        send(.logSet(exerciseID: exercise.id, set: set))
        let updated = live.exercises.first { $0.id == exercise.id }
        if !wasHit, updated?.targetHit == true { WKInterfaceDevice.current().play(.success) } else { WKInterfaceDevice.current().play(.click) }
        let nextText = updated.map { BeatItText.number($0.prefill, bodyweight: $0.bodyweight) }
        if exercise.restSeconds > 0 {
            send(.rest(RestState(seconds: exercise.restSeconds, setID: set.id, exercise: exercise.name, next: nextText, origin: .watch)))
            scheduleRestAlert()
        }
        showUndo("Logged \(UnitMath.format(weight)) × \(reps)", setID: set.id, exerciseID: exercise.id)
    }

    func undoLast() {
        guard let u = undo else { return }
        send(.unlogSet(setID: u.setID))
        if live.rest?.countdown.setID == u.setID { send(.rest(nil)); scheduleRestAlert() }
        undo = nil
        undoTask?.cancel()
    }

    private func showUndo(_ text: String, setID: UUID, exerciseID: UUID) {
        undo = (text, setID, exerciseID)
        undoTask?.cancel()
        undoTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.undo = nil
        }
    }

    func setRest(_ exercise: LiveExercise, seconds: Int) { send(.setRest(exerciseID: exercise.id, seconds: seconds)) }

    func addRest(_ seconds: Int) {
        guard let r = live.rest else { return }
        send(.rest(r.adding(seconds)))
        scheduleRestAlert()
    }

    func skipRest() {
        send(.rest(nil))
        restUp = false
        scheduleRestAlert()
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
                send(.watchSession(active: true))
                watchForStale()
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
        restUp = false
        guard let r = live.rest, !r.isOver(at: Date()) else { return }
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(r.remaining(at: Date())))
            guard !Task.isCancelled, let self, self.live.rest == r else { return }
            if self.workout.isRunning || WKApplication.shared().applicationState == .active {
                WKInterfaceDevice.current().play(.notification)
            }
            self.restUp = true
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self.restUp = false
        }
    }

    // MARK: Library

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
        let recents = live.recents.filter { !inToday.contains($0.id) && (q.isEmpty || Search.fold($0.name).contains(Search.fold(q))) }
        let recentIDs = Set(recents.map(\.id))
        let all = Search.run(WatchLibrary.index, query: q).prefix(q.isEmpty ? 400 : 100).compactMap { WatchLibrary.byID[$0.id] }
            .filter { !inToday.contains($0.id) && !recentIDs.contains($0.id) }
        return (recents, Array(all))
    }
}

extension WatchStore: WCSessionDelegate {
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
