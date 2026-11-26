import Foundation
import HealthKit

/// The HKWorkoutSession (Traditional Strength Training) that runs while a
/// workout is active on the watch: heart rate, background runtime (so rest
/// alerts and rep counting keep working wrist-down) and the Health save.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private(set) var workoutID: UUID?
    private(set) var heartRate: Int?

    var isRunning: Bool { session != nil }

    /// Starts the session; false when Health isn't available or allowed.
    func start(workoutID: UUID) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable(), session == nil else { return session != nil }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
        do { try await store.requestAuthorization(toShare: share, read: read) } catch { return false }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: config)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: config)
            b.delegate = self
            let start = Date()
            s.startActivity(with: start)
            try await b.beginCollection(at: start)
            try await b.addMetadata([HKMetadataKeyExternalUUID: workoutID.uuidString, HKMetadataKeyWorkoutBrandName: "Lift"])
            session = s
            builder = b
            self.workoutID = workoutID
            return true
        } catch {
            return false
        }
    }

    /// Ends the session. `save`: write the workout to Health (the phone then
    /// skips its own save); otherwise discard. Returns the Health workout id.
    func end(at end: Date, save: Bool) async -> UUID? {
        guard let session, let builder else { return nil }
        self.session = nil
        self.builder = nil
        workoutID = nil
        heartRate = nil
        session.end()
        do {
            try await builder.endCollection(at: max(end, builder.startDate?.addingTimeInterval(60) ?? end))
            guard save else { builder.discardWorkout(); return nil }
            return try await builder.finishWorkout()?.uuid
        } catch {
            return nil
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let hr = HKQuantityType(.heartRate)
        guard collectedTypes.contains(hr),
              let q = workoutBuilder.statistics(for: hr)?.mostRecentQuantity() else { return }
        let bpm = Int(q.doubleValue(for: HKUnit.count().unitDivided(by: .minute())).rounded())
        Task { @MainActor in self.heartRate = bpm }
    }
}
