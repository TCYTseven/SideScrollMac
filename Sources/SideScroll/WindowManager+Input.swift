import AppKit
import QuartzCore
import SideScrollCore

extension WindowManager {

    func startInputMonitors() {
        trackpad.onSwipe = { [weak self] phase in self?.handleSwipe(phase) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self?.finishDrag() }
        }) { eventMonitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            self?.mouseMoved()
        }) { eventMonitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .scrollWheel, handler: { [weak self] e in
            self?.scrollWheel(e)
        }) { eventMonitors.append(m) }
    }

    // MARK: Trackpad swipe

    /// Points the strip moves per full trackpad width.
    private func swipeScale(_ key: StripKey) -> Double {
        viewportWidth(key) * 1.6 * config.swipeSensitivity * (config.swipeNatural ? -1 : 1)
    }

    func handleSwipe(_ phase: TrackpadMonitor.Phase) {
        guard store.enabled else { return }
        switch phase {
        case .began:
            guard let d = Displays.containing(point: Displays.mouseLocation, in: displays) else { return }
            let key = activeKey(for: d)
            guard let s = strips[key], !s.columns.isEmpty else { return }
            animator.cancelAll()
            for id in s.allWindows {
                // Animations were cut short; read where windows really are.
                if let f = windows[id]?.ax.frame { windows[id]?.lastFrame = f }
            }
            swipeKey = key
            swipeStartOffset = s.viewOffset
            swipeOffset = s.viewOffset

        case .changed(let dx):
            guard let key = swipeKey, let s = strips[key] else { return }
            var off = swipeStartOffset + dx * swipeScale(key)
            // Rubber-band past the ends.
            let W = viewportWidth(key)
            let maxOff = max(Layout.totalWidth(s, W, config.gap) - W, 0)
            if off < 0 { off = off * 0.3 }
            if off > maxOff { off = maxOff + (off - maxOff) * 0.3 }
            swipeOffset = off
            layout(key, animate: false, offset: off)

        case .ended(let velocity):
            guard let key = swipeKey, var s = strips[key] else { swipeKey = nil; return }
            swipeKey = nil
            let offsetVelocity = velocity * swipeScale(key)
            let projected = swipeOffset + offsetVelocity * 0.22
            let W = viewportWidth(key)
            let (col, off) = Layout.snap(s, viewportWidth: W, gap: config.gap, projected: projected)
            s.viewOffset = off
            let changed = s.focusedColumn != col || s.focusedPin != nil
            s.focusColumn(col)
            strips[key] = s
            layout(key, animate: true, velocity: -offsetVelocity)
            if changed {
                // Focus follows the swipe, without scrolling again.
                suppressScrollUntil = CACurrentMediaTime() + 0.6
                focusStrip(key)
            }

        case .cancelled:
            guard let key = swipeKey else { return }
            swipeKey = nil
            layout(key, animate: true)
        }
    }

    // MARK: ⌃⌥ + scroll wheel

    func scrollWheel(_ e: NSEvent) {
        guard store.enabled, config.modifierScroll else { return }
        let mods = e.modifierFlags.intersection([.control, .option, .command, .shift])
        guard mods == [.control, .option] else { return }
        guard let d = Displays.containing(point: Displays.mouseLocation, in: displays) else { return }
        let key = activeKey(for: d)
        guard var s = strips[key], !s.columns.isEmpty else { return }
        let raw = abs(e.scrollingDeltaX) > abs(e.scrollingDeltaY) ? e.scrollingDeltaX : e.scrollingDeltaY
        let delta = Double(raw) * (e.hasPreciseScrollingDeltas ? 1 : 12)
        if scrollKey != key {
            animator.cancelAll()
            scrollKey = key
        }
        let W = viewportWidth(key)
        let maxOff = max(Layout.totalWidth(s, W, config.gap) - W, 0)
        s.viewOffset = min(max(s.viewOffset - delta, 0), maxOff)
        strips[key] = s
        layout(key, animate: false, offset: s.viewOffset)

        scrollSettleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, var s = self.strips[key] else { return }
            self.scrollKey = nil
            let (col, off) = Layout.snap(s, viewportWidth: W, gap: self.config.gap, projected: s.viewOffset)
            s.viewOffset = off
            let changed = s.focusedColumn != col
            s.focusColumn(col)
            self.strips[key] = s
            self.layout(key, animate: true)
            if changed {
                self.suppressScrollUntil = CACurrentMediaTime() + 0.6
                self.focusStrip(key)
            }
        }
        scrollSettleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    // MARK: Focus follows mouse

    func mouseMoved() {
        guard store.enabled, config.focusFollowsMouse, swipeKey == nil, dragging == nil,
              NSEvent.pressedMouseButtons == 0 else { return }
        let now = CACurrentMediaTime()
        guard now - lastMouseMove > 0.05 else { return }
        lastMouseMove = now
        let p = Displays.mouseLocation
        guard let d = Displays.containing(point: p, in: displays) else { return }
        let key = activeKey(for: d)
        guard let result = lastLayout[key] else { return }
        guard let hit = result.placements.first(where: { $0.visible && $0.frame.contains(p) }),
              hit.window != focusedID, let mw = windows[hit.window] else { return }
        // Only when the window under the mouse is the topmost thing there.
        if let top = topWindow(at: p), top != hit.window { return }
        suppressScrollUntil = now + 0.5
        focusedID = mw.id
        mw.ax.focus()
    }

    /// Topmost normal window at a point, from the window server's z-order.
    func topWindow(at p: CGPoint) -> WinID? {
        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        for info in infos where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let b = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: b), rect.contains(p),
                  let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            if (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == getpid() { continue }
            return id
        }
        return nil
    }
}
