import AppKit
import CoreVideo
import QuartzCore
import SideScrollCore

/// Moves windows to their target positions with springs, one step per
/// display refresh. Sizes are applied once at the start; only positions animate.
final class Animator {
    private struct Anim {
        var x: Spring
        var y: Spring
        var size: CGSize
        weak var window: AXWin?
    }

    private var anims: [WinID: Anim] = [:]
    private var displayLink: CVDisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var tickPending = false
    /// Called after each step with the windows that moved, so overlays can follow.
    var onStep: (() -> Void)?
    /// Called once every animation has settled.
    var onSettle: (() -> Void)?

    var isAnimating: Bool { !anims.isEmpty }

    /// Current animated position of a window, if it is moving.
    func currentOrigin(_ id: WinID) -> CGPoint? {
        guard let a = anims[id] else { return nil }
        return CGPoint(x: a.x.value, y: a.y.value)
    }

    func animate(_ win: AXWin, from: CGRect, to: CGRect, stiffness: Double, velocityX: Double = 0) {
        if var a = anims[win.id] {
            a.x.target = to.minX
            a.y.target = to.minY
            a.x.stiffness = stiffness
            a.y.stiffness = stiffness
            if velocityX != 0 { a.x.velocity = velocityX }
            a.size = to.size
            anims[win.id] = a
        } else {
            anims[win.id] = Anim(
                x: Spring(value: from.minX, target: to.minX, velocity: velocityX, stiffness: stiffness),
                y: Spring(value: from.minY, target: to.minY, stiffness: stiffness),
                size: to.size, window: win)
        }
        start()
    }

    /// Drops any running animation of `id` (for instant placement).
    func cancel(_ id: WinID) { anims[id] = nil }

    func cancelAll() { anims.removeAll() }

    private func start() {
        guard displayLink == nil else { return }
        lastTime = CACurrentMediaTime()
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }
        let opaque = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, ctx in
            guard let ctx else { return kCVReturnSuccess }
            let me = Unmanaged<Animator>.fromOpaque(ctx).takeUnretainedValue()
            me.scheduleTick()
            return kCVReturnSuccess
        }, opaque)
        displayLink = link
        CVDisplayLinkStart(link)
    }

    private func stop() {
        if let link = displayLink { CVDisplayLinkStop(link) }
        displayLink = nil
    }

    private func scheduleTick() {
        // Called on the display link thread; hop to main and never queue more than one.
        guard !tickPending else { return }
        tickPending = true
        DispatchQueue.main.async { [weak self] in
            self?.tickPending = false
            self?.tick()
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = max(min(now - lastTime, 1.0 / 30.0), 1.0 / 240.0)
        lastTime = now
        for (id, var a) in anims {
            guard let w = a.window else { anims[id] = nil; continue }
            a.x.step(dt)
            a.y.step(dt)
            AXApp.withoutEnhancedUI(w.pid) {
                w.setPosition(CGPoint(x: a.x.value.rounded(), y: a.y.value.rounded()))
            }
            if a.x.isSettled && a.y.isSettled {
                anims[id] = nil
            } else {
                anims[id] = a
            }
        }
        onStep?()
        if anims.isEmpty {
            stop()
            onSettle?()
        }
    }
}
