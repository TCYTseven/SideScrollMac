import AppKit
import QuartzCore
import SideScrollCore

extension WindowManager {

    func managed(_ el: AXUIElement, pid: pid_t) -> ManagedWindow? {
        if let id = AX.windowID(el), let mw = windows[id] { return mw }
        // Destroyed elements no longer report an ID; match by identity.
        return windows.values.first { $0.ax.pid == pid && CFEqual($0.ax.element, el) }
    }

    func handle(_ obs: AppObserver, _ event: WindowEvent) {
        guard store.enabled else { return }
        let pid = obs.pid
        switch event {
        case .created(let el):
            // New windows are often not sized or titled yet; give them a moment.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
                guard let self else { return }
                let front = NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
                let focus = front || !self.config.preventFocusStealing
                self.track(el, pid: pid, focus: focus)
            }

        case .destroyed(let el):
            if let mw = managed(el, pid: pid) { forget(mw.id) }

        case .focused(let el):
            // Only the frontmost app's focus counts: background apps raising
            // their own windows must not scroll the strip.
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            let mw = managed(el, pid: pid) ?? track(el, pid: pid, focus: true)
            if let mw { windowFocused(mw) }

        case .moved(let el), .resized(let el):
            guard let mw = managed(el, pid: pid) else { return }
            windowChangedByOthers(mw)

        case .minimized(let el):
            guard let mw = managed(el, pid: pid), let key = key(of: mw.id) else { return }
            if case .column(let c, _)? = strips[key]?.locate(mw.id) { mw.parkedAt = (key, c) }
            strips[key]?.remove(mw.id)
            layout(key, animate: true)

        case .deminimized(let el):
            guard let mw = managed(el, pid: pid), !mw.floating else { return }
            let parked = mw.parkedAt
            mw.parkedAt = nil
            addToStrip(mw, focus: true, at: parked?.column, key: parked?.key)

        case .titleChanged:
            updateTabBars()

        case .appHidden:
            var touched = Set<StripKey>()
            for mw in windows.values where mw.ax.pid == pid {
                guard let key = key(of: mw.id) else { continue }
                if case .column(let c, _)? = strips[key]?.locate(mw.id) { mw.parkedAt = (key, c) }
                strips[key]?.remove(mw.id)
                touched.insert(key)
            }
            for k in touched { layout(k, animate: true) }

        case .appShown:
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.reconcile(animate: true) }
        }
    }

    func appActivated(_ app: NSRunningApplication) {
        guard store.enabled else { return }
        if observers[app.processIdentifier] == nil { addApp(app) }
        guard let el = AXApp.focusedWindow(of: app.processIdentifier) else { return }
        let mw = managed(el, pid: app.processIdentifier) ?? track(el, pid: app.processIdentifier, focus: true)
        if let mw { windowFocused(mw) }
    }

    func syncFocusFromSystem(scroll: Bool) {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let el = AXApp.focusedWindow(of: app.processIdentifier),
              let mw = managed(el, pid: app.processIdentifier) else { return }
        focusedID = mw.id
        if let key = key(of: mw.id) {
            strips[key]?.focusWindow(mw.id)
            if scroll { scrollToFocus(key) }
            layout(key, animate: false)
        }
        updateDecorations()
    }

    /// The system says `mw` got focus (click, ⌘-Tab, Dock, our own shortcut).
    func windowFocused(_ mw: ManagedWindow) {
        focusedID = mw.id
        guard let key = key(of: mw.id) else { updateDecorations(); updateStatus(); return }
        let before = strips[key]
        strips[key]?.focusWindow(mw.id)
        if CACurrentMediaTime() > suppressScrollUntil && swipeKey == nil {
            scrollToFocus(key)
        }
        if strips[key] != before {
            layout(key, animate: true)
        } else {
            updateTabBars()
            updateDecorations()
            updateStatus()
        }
    }

    /// Gives focus to whatever the strip says is focused. `warp` moves the
    /// mouse along when "mouse follows focus" is on.
    func focusStrip(_ key: StripKey, warp: Bool = false) {
        guard let id = strips[key]?.focusedWindow, let mw = windows[id] else { return }
        focusedID = id
        mw.ax.focus()
        if warp && config.mouseFollowsFocus, let f = mw.lastFrame {
            CGWarpMouseCursorPosition(CGPoint(x: f.midX, y: f.midY))
        }
    }

    func selectTab(column: UUID, index: Int) {
        for (key, s) in strips {
            guard let ci = s.columns.firstIndex(where: { $0.id == column }) else { continue }
            guard s.columns[ci].windows.indices.contains(index) else { return }
            let id = s.columns[ci].windows[index]
            strips[key]?.focusWindow(id)
            layout(key, animate: false)
            focusStrip(key)
            return
        }
    }

    // MARK: Moves and resizes we did not make

    func windowChangedByOthers(_ mw: ManagedWindow) {
        guard !mw.floating, let key = key(of: mw.id), let actual = mw.ax.frame else { return }
        if animator.currentOrigin(mw.id) != nil { return }
        if let expected = mw.lastFrame,
           abs(expected.minX - actual.minX) < 2, abs(expected.minY - actual.minY) < 2,
           abs(expected.width - actual.width) < 2, abs(expected.height - actual.height) < 2 { return }
        // Our own writes echo back for a moment; ignore those.
        if CACurrentMediaTime() - mw.lastSetAt < 0.25 && NSEvent.pressedMouseButtons & 1 == 0 { return }
        if mw.ax.isFullscreen {
            strips[key]?.remove(mw.id)
            layout(key, animate: false)
            return
        }
        if NSEvent.pressedMouseButtons & 1 != 0 {
            dragging = mw.id
            return
        }
        // The app moved itself (or refused a size). Put it back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.dragging == nil else { return }
            mw.lastFrame = nil
            self.layout(key, animate: false)
        }
    }

    /// Mouse released after the user dragged or resized a tiled window.
    func finishDrag() {
        guard let id = dragging else { return }
        dragging = nil
        guard let mw = windows[id], let key = key(of: id), let actual = mw.ax.frame,
              let d = display(for: key), var s = strips[key] else { return }
        let expected = mw.lastFrame ?? actual
        let resized = abs(expected.width - actual.width) > 2 || abs(expected.height - actual.height) > 2

        if resized {
            // Resizing by hand sets the column width (and the height share in a stack).
            let vp = Layout.viewport(s, params(for: d))
            // A hand resize is the new truth, including any earlier "refused" width.
            mw.minWidth = 0
            if case .column(let ci, _)? = s.locate(id) { s.columns[ci].minWidth = 0 }
            s.focusWindow(id)
            s.setWidth((actual.width + config.gap) / (vp.width + config.gap))
            if case .column(let ci, _)? = s.locate(id), s.columns[ci].windows.count > 1, !s.columns[ci].isTabbed {
                let col = s.columns[ci]
                let total = col.windows.reduce(0.0) { $0 + col.weight($1) }
                let share = actual.height / max(params(for: d).area.height, 1)
                s.columns[ci].heightWeights[id] = max(0.2, share * total)
            }
        } else if config.dragToReorder, case .column(let from, _)? = s.locate(id), let result = lastLayout[key] {
            // Dropped over another column: move there.
            let mid = actual.midX
            var to = from
            for (i, c) in s.columns.enumerated() where i != from {
                if let f = result.columnFrames[c.id], mid >= f.minX && mid <= f.maxX { to = i; break }
            }
            if to != from {
                s.reorderColumn(from: from, to: to)
                s.focusWindow(id)
            }
        }
        strips[key] = s
        mw.lastFrame = actual
        scrollToFocus(key)
        layout(key, animate: true)
    }
}
