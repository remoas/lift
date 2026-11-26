import Foundation
import HealthKit

/// Writes finished workouts to Apple Health as Traditional Strength Training.
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    enum Status { case notSetUp, on, denied, unavailable }
    enum SaveResult: Equatable { case saved(UUID), denied, failed, unavailable }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func status(userEnabled: Bool?) -> Status {
        guard isAvailable else { return .unavailable }
        switch store.authorizationStatus(for: HKObjectType.workoutType()) {
        case .sharingAuthorized: return userEnabled == false ? .notSetUp : .on
        case .sharingDenied: return .denied
        default: return .notSetUp
        }
    }

    /// Shows the system prompt (first time only; later calls return at once).
    func requestAccess() async -> Bool {
        guard isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: [])
        } catch {
            return false
        }
        return store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
    }

    func save(start: Date, end: Date, routineName: String, workoutID: UUID) async -> SaveResult {
        guard isAvailable else { return .unavailable }
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return .denied }
        let config = HKWorkoutConfiguration()
        config.activityType = .traditionalStrengthTraining
        config.locationType = .indoor
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([
                HKMetadataKeyExternalUUID: workoutID.uuidString,
                HKMetadataKeyWorkoutBrandName: "Lift",
            ])
            try await builder.endCollection(at: max(end, start.addingTimeInterval(60)))
            guard let workout = try await builder.finishWorkout() else { return .failed }
            return .saved(workout.uuid)
        } catch {
            return .failed
        }
    }
}
