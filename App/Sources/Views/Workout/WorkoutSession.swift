import Foundation
import SwiftData
import Observation
import LiftCore

/// View model for the active workout. Owns logging, rest and the PR banner so
/// the set row, rest bar and banner views stay layout-free (reusable by the
/// phase 2 Watch app and Live Activity).
@Observable
@MainActor
final class WorkoutSession {
    let workout: Workout
    private let context: ModelContext
    private let settings: AppSettings

    private(set) var rest: RestCountdown?
    private(set) var restNextText: String?
    private(set) var restDoneText: String?
    private(set) var banner: PRBannerContent?
    private(set) var bannerExercise: Exercise?
    /// SetEntry.id behind the banner (prValue / prBanner shared IDs).
    private(set) var bannerSetID: UUID?
    private(set) var bestIDs: Set<UUID> = []
    var saveError: String?

    /// The exercise of the set just logged: it keeps the bar while its rest runs (N1).
    private(set) var lastLoggedExercise: Exercise?
    /// True while the set editor is up: the banner's 4 s clock waits (flow 3).
    private var bannerHeld = false
    private var editBefore: (weight: Double, reps: Int, unit: WeightUnit)?
    private var restTask: Task<Void, Never>?
    private var bannerTask: Task<Void, Never>?

    init(workout: Workout, context: ModelContext, settings: AppSettings) {
        self.workout = workout
        self.context = context
        self.settings = settings
        bestIDs = LiftStore.bestSetIDs(in: workout)
    }

    // MARK: Derived

    var groups: [(exercise: Exercise, sets: [SetEntry])] { workout.groups }

    /// The first unticked set: its ring is the screen's primary action.
    var currentSet: SetEntry? { groups.lazy.flatMap(\.sets).first { !$0.isDone } }

    var setsLeft: Int { workout.allSets.filter { !$0.isDone }.count }
    var allDone: Bool { !workout.allSets.isEmpty && setsLeft == 0 }

    func unit(for exercise: Exercise) -> WeightUnit { exercise.unit(global: settings.unit) }

    func previous(for set: SetEntry) -> SetEntry? {
        guard let ex = set.exercise else { return nil }
        let last = LiftStore.lastSessionSets(for: ex, excluding: workout)
        let index = groups.first(where: { $0.exercise === ex })?.sets.firstIndex(where: { $0 === set }) ?? 0
        return index < last.count ? last[index] : nil
    }

    func rowModel(for set: SetEntry, number: Int) -> SetRowModel {
        let unit = set.unit
        let state: SetRowState = set.isDone ? (bestIDs.contains(set.id) ? .best : .done) : (set === currentSet ? .current : .upcoming)
        let secondary: String? = settings.showOtherUnit && set.weight > 0
            ? "\(UnitMath.format(UnitMath.convertLoadable(set.weight, from: unit, to: unit.other, step: unit.other.defaultStep / 2))) \(unit.other.symbol)"
            : nil
        // Last time lives on the exercise's Last line now, not per row.
        return SetRowModel(id: set.id, number: number, kind: set.kind,
                           lastTime: nil,
                           weightText: set.needsWeight ? nil : UnitMath.format(set.weight),
                           unit: unit, reps: set.reps, secondary: secondary, state: state)
    }

    // MARK: Logging

    enum TickOutcome { case logged, unticked, needsEditor }

    /// One tap: logs exactly what's shown, saves with its UUID, checks for a
    /// best and starts rest. Tapping a logged ring unticks it, asking nothing.
    @discardableResult
    func tick(_ set: SetEntry) -> TickOutcome {
        if set.isDone {
            set.isDone = false
            set.doneAt = nil
            if !LiftStore.save(context) { saveError = "Couldn't save that set. Try again." }
            if rest?.setID == set.id { stopRest() }
            bestIDs = LiftStore.bestSetIDs(in: workout)
            return .unticked
        }
        if set.needsWeight { return .needsEditor }
        log(set)
        return .logged
    }

    /// Last line + Beat it target for an exercise (same function as the prefill).
    func beatIt(for exercise: Exercise) -> LiftStore.BeatIt {
        LiftStore.beatIt(for: exercise, excluding: workout, unit: unit(for: exercise))
    }

    /// A logged set in this workout met or beat the exercise's target.
    func targetHit(for exercise: Exercise) -> Bool {
        LiftStore.targetHit(exercise, in: workout, globalUnit: settings.unit)
    }

    /// The clock starts at the first logged set; nil until then.
    var startedClock: Date? { workout.doneSets.isEmpty ? nil : workout.startedAt }

    /// The exercise holding the current set: the only one with the bar.
    var currentExercise: Exercise? { currentSet?.exercise }

    /// Where the one 4 pt bar sits when no banner shows: the exercise just logged
    /// while its rest runs, otherwise the current exercise (qa-quicklog-run2 N1).
    var barExercise: Exercise? {
        if rest != nil || restDoneText != nil, let ex = lastLoggedExercise, groups.contains(where: { $0.exercise === ex }) { return ex }
        return currentExercise
    }

    func log(_ set: SetEntry) {
        let wasHit = set.exercise.map { targetHit(for: $0) } ?? true
        // The clock starts at the first logged set (nothing logged = nothing timed).
        if !workout.isBackLog, workout.doneSets.isEmpty { workout.startedAt = Date() }
        set.isDone = true
        set.doneAt = workout.isBackLog ? backLogTime() : Date()
        guard LiftStore.save(context) else {
            set.isDone = false
            set.doneAt = nil
            saveError = "Couldn't save that set. Try again."
            return
        }
        if let ex = set.exercise, !wasHit, targetHit(for: ex) { Haptics.step() }
        lastLoggedExercise = set.exercise
        detectRecords(set)
        // Later sets prefill with what was just logged (AC 64, Ben 2:16 pm).
        if let ex = set.exercise { LiftStore.prefill(ex, in: workout, globalUnit: settings.unit); _ = LiftStore.save(context) }
        if !workout.isBackLog, settings.autoStartRest { startRest(after: set) }
    }

    private func detectRecords(_ set: SetEntry) {
        let kinds = LiftStore.newRecords(for: set, in: workout)
        bestIDs = LiftStore.bestSetIDs(in: workout)
        if let ex = set.exercise, !kinds.isEmpty {
            let history = LiftStore.history(for: ex, including: workout).filter { $0 !== set }.map(\.snapshot)
            if let content = PRBannerContent.make(kinds: kinds, exercise: ex.name, set: set.snapshot, history: history, unit: set.unit) {
                showBanner(content, exercise: ex, setID: set.id)
            }
        }
    }

    /// A logged set edited in the editor ("Save set"): a new best still gets its banner.
    func saveEdited(_ set: SetEntry) {
        guard LiftStore.save(context) else { saveError = "Couldn't save that set. Try again."; return }
        let changed = editBefore.map { $0.weight != set.weight || $0.reps != set.reps || $0.unit != set.unit } ?? true
        bestIDs = LiftStore.bestSetIDs(in: workout)
        if changed { detectRecords(set) }
    }

    /// The set editor pauses the banner's clock; closing it gives the banner a fresh 4 s.
    func holdBanner(editing set: SetEntry) {
        editBefore = (set.weight, set.reps, set.unit)
        bannerHeld = true
        bannerTask?.cancel()
    }

    func resumeBanner() {
        bannerHeld = false
        if banner != nil { scheduleBannerDismiss() }
    }

    /// Back-logged sets are stamped in order on the workout's own day.
    private func backLogTime() -> Date {
        let latest = workout.doneSets.compactMap(\.doneAt).max() ?? workout.startedAt
        return latest.addingTimeInterval(60)
    }


    // MARK: Rest

    func startRest(after set: SetEntry) {
        let seconds = set.kind == .warmup ? settings.warmupRestSeconds : set.restSeconds
        guard seconds > 0 else { return }
        rest = RestCountdown(seconds: seconds, setID: set.id)
        restDoneText = nil
        if let next = currentSet, let nextEx = next.exercise {
            // Next is the prefill (N3). Another exercise: prefill its first set at
            // the target and name it ("Shoulder Press · 110 × 9").
            let other = nextEx !== set.exercise
            if other { LiftStore.prefill(nextEx, in: workout, globalUnit: settings.unit) }
            let bodyweight = nextEx.equipment == .bodyweight
            let pair: String
            if next.needsWeight { pair = "Add weight × \(next.reps)" }
            else if bodyweight { pair = next.weight <= 0 ? "\(next.reps) reps" : "BW + \(UnitMath.format(next.weight)) × \(next.reps)" }
            else { pair = "\(UnitMath.format(next.weight)) × \(next.reps)" }
            restNextText = other ? "\(nextEx.name) · \(pair)" : pair
        } else {
            restNextText = nil
        }
        scheduleRestEnd()
    }

    func adjustRest(by seconds: Int) {
        guard var r = rest else { return }
        r.adjust(by: seconds)
        rest = r
        if r.remaining(at: Date()) <= 0 { finishRest() } else { scheduleRestEnd() }
    }

    func stopRest() {
        rest = nil
        restDoneText = nil
        restTask?.cancel()
        RestNotifications.cancel()
    }

    private func scheduleRestEnd() {
        guard let r = rest else { return }
        restTask?.cancel()
        let nextEx = currentSet?.exercise?.name
        RestNotifications.schedule(at: r.endsAt, exercise: nextEx, next: restNextText)
        restTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(r.endsAt.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled else { return }
            self?.finishRest()
        }
    }

    private func finishRest() {
        restTask?.cancel()
        Haptics.restDone()
        rest = nil
        restDoneText = restNextText.map { "Rest's up · \($0)" } ?? "Rest's up"
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            self?.restDoneText = nil
        }
    }

    // MARK: Banner

    private func showBanner(_ content: PRBannerContent, exercise: Exercise, setID: UUID) {
        // Success haptic as the banner starts to appear, never on dismiss.
        if settings.celebrateHaptic { Haptics.newBest() }
        guard settings.celebrateBanner else { return }
        banner = content
        bannerExercise = exercise
        bannerSetID = setID
        bannerTask?.cancel()
        if !bannerHeld { scheduleBannerDismiss() }
    }

    private func scheduleBannerDismiss() {
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            // 4.0 s on screen once the number has landed (~0.4 s morph).
            try? await Task.sleep(for: .seconds(4.4))
            guard !Task.isCancelled else { return }
            self?.dismissBanner()
        }
    }

    #if DEBUG
    /// Screenshot fixtures only (frame 06): show the banner for a logged set.
    func debugShowBanner(for set: SetEntry) {
        guard let ex = set.exercise else { return }
        let history = LiftStore.history(for: ex).filter { $0.workout !== workout }.map(\.snapshot)
        let kinds = PRDetector.newRecords(for: set.snapshot, history: history)
        guard let content = PRBannerContent.make(kinds: kinds, exercise: ex.name, set: set.snapshot, history: history, unit: set.unit) else { return }
        banner = content
        bannerExercise = ex
        bannerSetID = set.id
    }
    #endif

    func dismissBanner() {
        bannerTask?.cancel()
        banner = nil
        bannerExercise = nil
        bannerSetID = nil
    }

    // MARK: Edits (this workout only)

    func addSet(to exercise: Exercise) { _ = LiftStore.addSet(to: exercise, in: workout, context: context) }

    func deleteSet(_ set: SetEntry, toasts: ToastCenter) {
        guard let ex = set.exercise else { return }
        let removed = LiftStore.RemovedSet(set)
        let number = (groups.first(where: { $0.exercise === ex })?.sets.firstIndex(where: { $0 === set }) ?? 0) + 1
        LiftStore.delete(set, context: context)
        _ = LiftStore.save(context)
        bestIDs = LiftStore.bestSetIDs(in: workout)
        if rest?.setID == removed.id { stopRest() }
        toasts.show("Set \(number) removed") { [weak self] in
            guard let self else { return }
            let s = removed.makeEntry(exercise: ex)
            self.context.insert(s)
            s.workout = self.workout
            _ = LiftStore.save(self.context)
            self.bestIDs = LiftStore.bestSetIDs(in: self.workout)
        }
    }

    func setKind(_ set: SetEntry, _ kind: SetKind) {
        set.kind = kind
        _ = LiftStore.save(context)
        bestIDs = LiftStore.bestSetIDs(in: workout)
    }

    func addExercise(_ exercise: Exercise) {
        LiftStore.addExercise(exercise, to: workout, globalUnit: settings.unit, restDefault: settings.workingRestSeconds, context: context)
    }

    func swap(_ old: Exercise, for new: Exercise) {
        LiftStore.swap(old, for: new, in: workout, globalUnit: settings.unit, context: context)
        bestIDs = LiftStore.bestSetIDs(in: workout)
    }

    func move(_ exercise: Exercise, by offset: Int) {
        LiftStore.move(exercise, by: offset, in: workout, context: context)
    }

    func remove(_ exercise: Exercise, toasts: ToastCenter) {
        let removed = LiftStore.remove(exercise, from: workout, context: context)
        bestIDs = LiftStore.bestSetIDs(in: workout)
        if let r = rest?.setID, removed.contains(where: { $0.id == r }) { stopRest() }
        toasts.show("\(exercise.name) removed") { [weak self] in
            guard let self else { return }
            LiftStore.restore(removed, exercise: exercise, into: self.workout, context: self.context)
            self.bestIDs = LiftStore.bestSetIDs(in: self.workout)
        }
    }

    func reorder(_ exercises: [Exercise]) {
        LiftStore.reorder(exercises, in: workout, context: context)
    }

    /// Rest lives on the exercise: sets its own rest and applies it to this
    /// workout's unlogged sets of that exercise (warm-ups keep their default).
    func setRest(for exercise: Exercise, seconds: Int) {
        exercise.restSec = seconds
        for set in workout.allSets where set.exercise === exercise && !set.isDone && set.kind != .warmup {
            set.restSeconds = seconds
        }
        save()
    }

    /// Rep goal for the Target rule; re-derives this workout's unlogged prefill.
    func setRepGoal(for exercise: Exercise, _ goal: Int) {
        exercise.repGoal = min(max(goal, 3), 30)
        LiftStore.prefill(exercise, in: workout, globalUnit: settings.unit)
        save()
    }

    func refreshBests() { bestIDs = LiftStore.bestSetIDs(in: workout) }

    func save() { _ = LiftStore.save(context) }
}
