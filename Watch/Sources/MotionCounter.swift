import Foundation
import CoreMotion
import LiftCore

/// CoreMotion device motion (50 Hz) into LiftCore's RepCounter while a set
/// is active. The count is live and the user corrects it with the Crown.
@MainActor
@Observable
final class MotionCounter {
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInteractive
        return q
    }()
    /// Only touched on `queue`.
    private final class Box: @unchecked Sendable { var counter = RepCounter() }
    @ObservationIgnored private let box = Box()

    private(set) var count = 0
    private(set) var isCounting = false
    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start() {
        count = 0
        isCounting = true
        guard manager.isDeviceMotionAvailable else { return }
        let box = box
        queue.addOperation { box.counter = RepCounter() }
        manager.deviceMotionUpdateInterval = 1.0 / 50
        manager.startDeviceMotionUpdates(to: queue) { [weak self] m, _ in
            guard let m else { return }
            let s = MotionSample(t: m.timestamp, ax: m.userAcceleration.x, ay: m.userAcceleration.y, az: m.userAcceleration.z,
                                 gx: m.gravity.x, gy: m.gravity.y, gz: m.gravity.z)
            let n = box.counter.add(s)
            Task { @MainActor in
                guard let self, self.isCounting, n != self.count else { return }
                self.count = n
            }
        }
    }

    /// Stops and returns the count.
    @discardableResult
    func stop() -> Int {
        manager.stopDeviceMotionUpdates()
        isCounting = false
        return count
    }
}
