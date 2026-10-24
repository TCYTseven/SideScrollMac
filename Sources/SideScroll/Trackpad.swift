import AppKit
import CMultitouch

/// Turns raw multi-finger trackpad frames into horizontal swipe callbacks.
/// Only swipes with exactly the configured number of fingers count, and only
/// once the motion is clearly horizontal.
final class TrackpadMonitor {
    enum Phase { case began, changed(dx: Double), ended(velocity: Double), cancelled }

    var fingers = 4
    var onSwipe: ((Phase) -> Void)?

    private var tracking = false
    private var locked = false
    private var startX: Float = 0
    private var startY: Float = 0
    private var lastX: Float = 0
    private var lastTime: Double = 0
    private var velocity: Double = 0

    fileprivate static var shared: TrackpadMonitor?

    func start() -> Bool {
        TrackpadMonitor.shared = self
        return cmt_start { count, x, y, t in
            DispatchQueue.main.async {
                TrackpadMonitor.shared?.frame(count: Int(count), x: x, y: y, time: t)
            }
        }
    }

    func stop() {
        cmt_stop()
        TrackpadMonitor.shared = nil
    }

    private func frame(count: Int, x: Float, y: Float, time: Double) {
        if count == fingers {
            if !tracking {
                tracking = true
                locked = false
                startX = x; startY = y; lastX = x; lastTime = time; velocity = 0
                return
            }
            let dx = Double(x - startX)
            let dy = Double(y - startY)
            if !locked {
                // Wait for a clear horizontal intent before taking over.
                if abs(dx) > 0.03 && abs(dx) > abs(dy) * 1.5 {
                    locked = true
                    onSwipe?(.began)
                } else if abs(dy) > 0.05 {
                    tracking = false
                    return
                } else {
                    return
                }
            }
            let dt = time - lastTime
            if dt > 0 {
                let v = Double(x - lastX) / dt
                velocity = velocity * 0.6 + v * 0.4
            }
            lastX = x
            lastTime = time
            onSwipe?(.changed(dx: dx))
        } else if tracking {
            tracking = false
            if locked {
                locked = false
                // More fingers landing means a different gesture: cancel.
                if count > fingers { onSwipe?(.cancelled) } else { onSwipe?(.ended(velocity: velocity)) }
            }
        }
    }
}
