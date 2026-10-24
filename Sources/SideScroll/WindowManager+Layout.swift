import AppKit
import QuartzCore
import SideScrollCore

extension WindowManager {

    func params(for d: Display) -> LayoutParams {
        var heights: [WinID: Double] = [:]
        if config.keepOriginalHeight {
            for (id, mw) in windows { heights[id] = mw.originalSize.height }
        }
        return d.layoutParams(config, originalHeights: heights)
    }

    func viewportWidth(_ key: StripKey) -> Double {
        guard let d = display(for: key), let s = strips[key] else { return 1000 }
        return Layout.viewport(s, params(for: d)).width
    }

    /// Scrolls the strip so its focused column is visible.
    func scrollToFocus(_ key: StripKey, mode: CenterMode? = nil) {
        guard var s = strips[key], let d = display(for: key), s.focusedPin == nil else { return }
        let vp = Layout.viewport(s, params(for: d))
        s.viewOffset = Layout.offsetShowing(s.focusedColumn, s, viewportWidth: vp.width, gap: config.gap,
                                            mode: mode ?? config.centerMode, current: s.viewOffset)
        strips[key] = s
    }

    func layoutAll(animate: Bool) {
        for d in displays { layout(activeKey(for: d), animate: animate) }
    }

    /// Moves every window of a strip to where it belongs.
    /// - Parameters:
    ///   - offset: overrides the strip's view offset (live trackpad scrolling).
    ///   - velocity: horizontal speed in points/s handed to the springs.
    func layout(_ key: StripKey, animate: Bool, offset: Double? = nil, velocity: Double = 0) {
        guard store.enabled, let d = display(for: key), activeKey(for: d) == key, let strip = strips[key] else { return }
        let result = Layout.compute(strip, params(for: d), viewOffset: offset)
        let now = CACurrentMediaTime()
        let stiffness = springStiffness(speed: config.animationSpeed)
        let shouldAnimate = animate && config.animationsEnabled

        for pl in result.placements {
            guard let mw = windows[pl.window] else { continue }
            let current = animator.currentOrigin(pl.window).map { CGRect(origin: $0, size: mw.lastFrame?.size ?? pl.frame.size) }
                ?? mw.lastFrame ?? mw.ax.frame ?? pl.frame
            let sizeChanged = abs(current.width - pl.frame.width) > 1 || abs(current.height - pl.frame.height) > 1
            let moved = abs(current.minX - pl.frame.minX) > 0.5 || abs(current.minY - pl.frame.minY) > 0.5
            mw.lastSetAt = now
            if !sizeChanged && !moved && mw.lastFrame != nil {
                continue
            }
            let wasVisible = d.frame.insetBy(dx: 2, dy: 0).intersects(current)
            if sizeChanged {
                AXApp.withoutEnhancedUI(mw.ax.pid) { mw.ax.setSize(pl.frame.size) }
            }
            if shouldAnimate && (pl.visible || wasVisible) && moved {
                animator.animate(mw.ax, from: current, to: pl.frame, stiffness: stiffness, velocityX: velocity)
            } else {
                animator.cancel(pl.window)
                mw.ax.setFrame(pl.frame, sizeChanged: false)
            }
            mw.lastFrame = pl.frame
        }
        lastLayout[key] = result
        updateTabBars()
        updateDecorations()
        updateStatus()
        if offset == nil { scheduleSave() }
    }

    // MARK: Decorations

    func updateTabBars() {
        guard store.enabled else { tabBars.hideAll(); return }
        let bars = displays.flatMap { lastLayout[activeKey(for: $0)]?.tabBars ?? [] }
        tabBars.update(bars, titles: { [weak self] id in
            guard let mw = self?.windows[id] else { return "" }
            let t = mw.ax.title
            return t.isEmpty ? mw.ax.appName : t
        }, above: { p in
            p.windows.indices.contains(p.activeIndex) ? p.windows[p.activeIndex] : nil
        })
    }

    func updateDecorations() {
        guard store.enabled, let id = focusedID, let mw = windows[id], !mw.floating || config.focusBorder else {
            border.hide()
            dim.hide()
            return
        }
        let frame: CGRect
        if let o = animator.currentOrigin(id), let s = mw.lastFrame?.size {
            frame = CGRect(origin: o, size: s)
        } else if let f = mw.lastFrame ?? mw.ax.frame {
            frame = f
        } else {
            border.hide(); dim.hide(); return
        }
        if config.focusBorder {
            border.show(around: frame, windowNumber: id,
                        color: NSColor(hex: config.focusBorderColor) ?? .systemBlue,
                        width: CGFloat(config.focusBorderWidth))
        } else {
            border.hide()
        }
        if config.dimUnfocused {
            dim.show(below: id, displays: displays, amount: config.dimAmount)
        } else {
            dim.hide()
        }
    }

    func updateStatus() {
        guard store.enabled, config.showPositionInMenuBar, let key = currentKey(), let s = strips[key], !s.columns.isEmpty else {
            onStatusChange?("")
            return
        }
        if s.focusedPin != nil {
            onStatusChange?("📌")
        } else {
            onStatusChange?("\(s.focusedColumn + 1)/\(s.columns.count)")
        }
    }
}
