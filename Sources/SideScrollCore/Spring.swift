import Foundation

/// A damped spring that eases a value toward a target. Retargeting keeps the
/// current velocity, so interrupted animations stay smooth.
public struct Spring: Equatable {
    public var value: Double
    public var velocity: Double
    public var target: Double
    /// Stiffness (k). Higher is faster.
    public var stiffness: Double
    /// 1.0 is critically damped (no overshoot).
    public var dampingRatio: Double

    public init(value: Double, target: Double? = nil, velocity: Double = 0,
                stiffness: Double = 800, dampingRatio: Double = 1.0) {
        self.value = value
        self.target = target ?? value
        self.velocity = velocity
        self.stiffness = stiffness
        self.dampingRatio = dampingRatio
    }

    public var isSettled: Bool {
        abs(target - value) < 0.5 && abs(velocity) < 5
    }

    /// Advances by `dt` seconds using fixed sub-steps for stability.
    public mutating func step(_ dt: Double) {
        let damping = 2 * dampingRatio * stiffness.squareRoot()
        var remaining = min(dt, 0.1)
        while remaining > 0 {
            let h = min(remaining, 1.0 / 240.0)
            let force = -stiffness * (value - target) - damping * velocity
            velocity += force * h
            value += velocity * h
            remaining -= h
        }
        if isSettled {
            value = target
            velocity = 0
        }
    }
}

/// Spring parameters derived from the user's animation speed setting.
public func springStiffness(speed: Double) -> Double {
    // speed 1.0 -> ~0.25 s settle time; 2.0 -> about twice as fast.
    let s = min(max(speed, 0.25), 4)
    return 700 * s * s
}
