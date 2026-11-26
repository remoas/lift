import Foundation

/// One device-motion reading: user acceleration (gravity removed) and the
/// gravity direction, both in g, in the watch's own axes (CMDeviceMotion).
public struct MotionSample: Sendable, Equatable {
    public var t: TimeInterval
    public var ax: Double, ay: Double, az: Double
    public var gx: Double, gy: Double, gz: Double

    public init(t: TimeInterval, ax: Double, ay: Double, az: Double, gx: Double = 0, gy: Double = -1, gz: Double = 0) {
        self.t = t; self.ax = ax; self.ay = ay; self.az = az; self.gx = gx; self.gy = gy; self.gz = gz
    }

    /// Acceleration along gravity (up/down), whatever the wrist's angle.
    public var vertical: Double {
        let n = max((gx * gx + gy * gy + gz * gz).squareRoot(), 1e-6)
        return -(ax * gx + ay * gy + az * gz) / n
    }
}

/// Live rep counting from the wrist.
///
/// Each channel (x, y, z and the gravity-vertical axis) is band-passed (bias
/// removed, 3 Hz low-pass) and leak-integrated to a velocity. A rep is one
/// out-and-back movement, so it shows as one velocity lobe each way; a
/// Schmitt trigger with an adaptive threshold (35 % of the recent peak, never
/// under 0.08 m/s) counts each return lobe, at most once per 0.7 s. The
/// dominant channel is the one with the most motion energy so far this set.
///
/// It's a starting estimate, not a referee: lifts with little wrist travel
/// (leg press, calf raise), very slow tempo (over ~5 s a rep) and racking or
/// re-gripping can miscount, so the count is always editable before saving.
public struct RepCounter: Sendable {
    public struct Config: Sendable {
        public var lowPassHz = 3.0
        public var biasSeconds = 3.0
        public var leakSeconds = 1.6
        public var envelopeSeconds = 4.0
        public var thresholdFraction = 0.35
        public var minVelocity = 0.08
        public var minRepSeconds = 0.7
        public init() {}
    }

    struct Channel: Sendable {
        var mean = 0.0, lp1 = 0.0, lp2 = 0.0, v = 0.0, env = 0.0, energy = 0.0
        var state = 0, firstSign = 0, count = 0
        var lastCount = -Double.infinity

        mutating func step(_ a: Double, t: Double, dt: Double, _ c: Config) {
            mean += (a - mean) * min(dt / c.biasSeconds, 1)
            let beta = 1 - exp(-2 * Double.pi * c.lowPassHz * dt)
            lp1 += (a - mean - lp1) * beta
            lp2 += (lp1 - lp2) * beta
            v = v * exp(-dt / c.leakSeconds) + lp2 * 9.80665 * dt
            env = max(abs(v), env * exp(-dt / c.envelopeSeconds))
            energy += v * v * dt
            let h = max(c.minVelocity, c.thresholdFraction * env)
            let sign = v > h ? 1 : (v < -h ? -1 : 0)
            guard sign != 0, sign != state else { return }
            state = sign
            if firstSign == 0 { firstSign = sign; return }
            if sign == -firstSign, t - lastCount >= c.minRepSeconds {
                count += 1
                lastCount = t
            }
        }
    }

    public let config: Config
    var channels = [Channel](repeating: Channel(), count: 4)
    var lastT: TimeInterval?

    public init(config: Config = Config()) { self.config = config }

    /// 0 = x, 1 = y, 2 = z, 3 = vertical.
    public var dominantChannel: Int {
        channels.indices.max { channels[$0].energy < channels[$1].energy } ?? 3
    }

    public var count: Int { channels[dominantChannel].count }

    /// Feeds one sample; returns the live count.
    @discardableResult
    public mutating func add(_ s: MotionSample) -> Int {
        let dt: Double
        if let lastT { dt = min(max(s.t - lastT, 0.001), 0.1) } else { dt = 0.02 }
        lastT = s.t
        let values = [s.ax, s.ay, s.az, s.vertical]
        for i in channels.indices { channels[i].step(values[i], t: s.t, dt: dt, config) }
        return count
    }

    public static func count(_ samples: [MotionSample], config: Config = Config()) -> Int {
        var c = RepCounter(config: config)
        for s in samples { c.add(s) }
        return c.count
    }
}
