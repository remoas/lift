import XCTest
@testable import LiftCore

/// Synthetic wrist signals: a known number of reps with a real movement
/// profile (half-cosine up and down), sensor noise and tremor, sampled at
/// 50 Hz like CMDeviceMotion on the watch. Seeded, so every run is identical.
enum Fixture {
    struct Rep { var up: Double; var down: Double; var pause: Double = 0.3 }

    struct RNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state }
        mutating func gaussian() -> Double {
            let u1 = max(Double(next() >> 11) / Double(1 << 53), 1e-12), u2 = Double(next() >> 11) / Double(1 << 53)
            return (-2 * log(u1)).squareRoot() * cos(2 * .pi * u2)
        }
    }

    /// `axis`: the movement direction in device axes; `gravity`: where down is.
    static func signal(reps: [Rep], travel: Double = 0.4, axis: (Double, Double, Double) = (0, 1, 0),
                       gravity: (Double, Double, Double) = (0, -1, 0), lead: Double = 2, tail: Double = 2,
                       noise: Double = 0.015, tremor: Double = 0.01, seed: UInt64 = 1, rate: Double = 50) -> [MotionSample] {
        // Acceleration (m/s²) as a function of time, piecewise per phase.
        var phases: [(start: Double, dur: Double, sign: Double)] = []
        var t = lead
        for r in reps {
            phases.append((t, r.up, 1)); t += r.up
            phases.append((t, r.down, -1)); t += r.down + r.pause
        }
        let end = t + tail
        var rng = RNG(state: seed)
        var out: [MotionSample] = []
        var i = 0.0
        while i / rate < end {
            let time = i / rate
            var a = 0.0
            if let p = phases.first(where: { time >= $0.start && time < $0.start + $0.dur }) {
                let u = (time - p.start) / p.dur
                a = p.sign * travel / 2 * pow(.pi / p.dur, 2) * cos(.pi * u)
            }
            let g = a / 9.80665 + tremor * sin(2 * .pi * 9 * time)
            func n() -> Double { noise * rng.gaussian() }
            out.append(MotionSample(t: time, ax: g * axis.0 + n(), ay: g * axis.1 + n(), az: g * axis.2 + n(),
                                    gx: gravity.0, gy: gravity.1, gz: gravity.2))
            i += 1
        }
        return out
    }

    static func steady(_ n: Int, up: Double = 1, down: Double = 1.2) -> [Rep] { Array(repeating: Rep(up: up, down: down), count: n) }
}

final class RepCounterTests: XCTestCase {
    func testTenSteadyReps() {
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Fixture.steady(10))), 10)
    }

    func testOneRep() {
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Fixture.steady(1))), 1)
    }

    func testFastReps() {
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Array(repeating: .init(up: 0.5, down: 0.6, pause: 0.1), count: 15))), 15)
    }

    func testSlowEccentric() {
        // 1 s up, 3 s down (tempo work).
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Fixture.steady(8, up: 1, down: 3))), 8)
    }

    func testVariableTempoAndShortTravel() {
        let reps: [Fixture.Rep] = [.init(up: 0.8, down: 1), .init(up: 1.2, down: 1.5), .init(up: 1.6, down: 2), .init(up: 2.4, down: 2.2, pause: 1), .init(up: 1, down: 1)]
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: reps, travel: 0.25)), 5)
    }

    func testWristTiltedMovementOnXAxis() {
        // Curl-like: the wrist moves along its own x axis, gravity is on z.
        let s = Fixture.signal(reps: Fixture.steady(12), axis: (1, 0, 0), gravity: (0, 0, -1), seed: 7)
        XCTAssertEqual(RepCounter.count(s), 12)
    }

    func testInvertedAxis() {
        let s = Fixture.signal(reps: Fixture.steady(6), axis: (0, -1, 0), seed: 3)
        XCTAssertEqual(RepCounter.count(s), 6)
    }

    func testDiagonalMovement() {
        let d = 1 / 3.0.squareRoot()
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Fixture.steady(9), axis: (d, d, d), gravity: (0, -0.7, -0.7), seed: 11)), 9)
    }

    func testStillWristCountsNothing() {
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: [], lead: 30, tail: 0, noise: 0.02, tremor: 0.015)), 0)
    }

    func testNoisierSensorStillCountsWithinOne() {
        let s = Fixture.signal(reps: Fixture.steady(10), noise: 0.05, tremor: 0.03, seed: 99)
        XCTAssertLessThanOrEqual(abs(RepCounter.count(s) - 10), 1)
    }

    func testManySeedsExactAtNormalNoise() {
        var exact = 0
        for seed in 1...50 {
            if RepCounter.count(Fixture.signal(reps: Fixture.steady(8), seed: UInt64(seed))) == 8 { exact += 1 }
        }
        XCTAssertEqual(exact, 50)
    }

    func testCountIsLiveAndNeverGoesDown() {
        var c = RepCounter()
        var last = 0
        for s in Fixture.signal(reps: Fixture.steady(5)) {
            let n = c.add(s)
            XCTAssertGreaterThanOrEqual(n, last)
            last = n
        }
        XCTAssertEqual(last, 5)
    }

    /// Known limit, kept visible: tiny wrist travel (a leg press seen from the
    /// wrist) is under the floor, so it isn't counted. The user enters reps.
    func testTinyTravelIsNotCounted() {
        XCTAssertEqual(RepCounter.count(Fixture.signal(reps: Fixture.steady(10), travel: 0.03)), 0)
    }
}

final class RepCounterBenchTests: XCTestCase {
    /// Bench-style: unrack (one-way up), reps that start going down, rack.
    /// Built by flipping the axis of a rep train that starts at the top.
    func testBenchStartsAtTheTop() {
        // Lowering first = the same movement with the axis inverted.
        let s = Fixture.signal(reps: Fixture.steady(5, up: 1.4, down: 0.9), axis: (0, -1, 0), seed: 5)
        XCTAssertEqual(RepCounter.count(s), 5)
    }
}
