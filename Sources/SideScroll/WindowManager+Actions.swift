import AppKit
import SideScrollCore

extension WindowManager {

    func perform(_ action: Action) {
        if action == .toggleEnabled {
            store.enabled.toggle()
            return
        }
        guard store.enabled else { return }
        if action == .retile {
            for mw in windows.values { mw.lastFrame = nil }
            reconcile(animate: false)
            layoutAll(animate: true)
            return
        }
        if action == .closeWindow {
            if let id = focusedID { windows[id]?.ax.close() }
            return
        }
        if action == .toggleFloat { toggleFloat(); return }
        if action == .focusNextDisplay { focusNextDisplay(); return }
        if action == .moveToNextDisplay { moveToNextDisplay(); return }

        guard let key = currentKey() else { return }
        var s = strips[key] ?? Strip()
        let before = s.focusedWindow
        var scroll = true
        var centerOverride: CenterMode?

        switch action {
        case .focusLeft: s.focusLeft()
        case .focusRight: s.focusRight()
        case .focusUp: s.focusVertical(-1)
        case .focusDown: s.focusVertical(1)
        case .moveLeft: s.moveColumn(-1)
        case .moveRight: s.moveColumn(1)
        case .moveUp: s.moveVertical(-1)
        case .moveDown: s.moveVertical(1)
        case .focusFirst: s.focusColumn(0)
        case .focusLast: s.focusColumn(s.columns.count - 1)
        case .cycleWidth: s.cycleWidth(presets: config.widthPresets)
        case .cycleWidthBack: s.cycleWidth(presets: config.widthPresets, backwards: true)
        case .wider: s.adjustWidth(config.resizeStep)
        case .narrower: s.adjustWidth(-config.resizeStep)
        case .fullWidth: s.toggleFullWidth()
        case .center: centerOverride = .always
        case .taller: s.adjustHeight(0.25)
        case .shorter: s.adjustHeight(-0.25)
        case .resetHeights: s.resetHeights()
        case .stackLeft: s.stackInto(-1)
        case .stackRight: s.stackInto(1)
        case .popLeft: s.popOut(-1, width: config.defaultWidth)
        case .popRight: s.popOut(1, width: config.defaultWidth)
        case .toggleTabbed: s.toggleTabbed()
        case .pinLeft: s.togglePin(.left, defaultWidth: config.defaultWidth); scroll = false
        case .pinRight: s.togglePin(.right, defaultWidth: config.defaultWidth); scroll = false
        default:
            if let n = action.columnNumber {
                if action.rawValue.hasPrefix("move") { s.moveColumn(to: n - 1) } else { s.focusColumn(n - 1) }
            }
        }

        strips[key] = s
        if scroll || centerOverride != nil { scrollToFocus(key, mode: centerOverride) }
        layout(key, animate: true)
        if s.focusedWindow != before || [.focusUp, .focusDown, .toggleTabbed].contains(action) {
            suppressScrollUntil = 0
            focusStrip(key)
        }
    }

    // MARK: Float

    func toggleFloat() {
        guard let id = focusedID, let mw = windows[id] else { return }
        if mw.floating {
            mw.floating = false
            addToStrip(mw, focus: true)
            return
        }
        guard let key = removeFromStrips(id), let d = display(for: key) else {
            mw.floating = true
            return
        }
        mw.floating = true
        animator.cancel(id)
        // Float at its original size, centered on the display.
        let area = d.visibleFrame
        let w = min(mw.originalSize.width, area.width * 0.8)
        let h = min(mw.originalSize.height, area.height * 0.8)
        let f = CGRect(x: area.midX - w / 2, y: area.midY - h / 2, width: w, height: h)
        mw.ax.setFrame(f)
        mw.lastFrame = f
        layout(key, animate: true)
        mw.ax.focus()
    }

    // MARK: Displays

    func orderedDisplays() -> [Display] {
        displays.filter { !config.excludedDisplays.contains($0.uuid) }.sorted {
            $0.frame.minX != $1.frame.minX ? $0.frame.minX < $1.frame.minX : $0.frame.minY < $1.frame.minY
        }
    }

    func nextDisplay(after key: StripKey?) -> Display? {
        let list = orderedDisplays()
        guard list.count > 1 else { return nil }
        let i = list.firstIndex { $0.uuid == key?.display } ?? -1
        return list[(i + 1) % list.count]
    }

    func focusNextDisplay() {
        guard let next = nextDisplay(after: currentKey()) else { return }
        let key = activeKey(for: next)
        if strips[key]?.focusedWindow != nil {
            focusStrip(key)
        } else {
            focusedID = nil
            updateDecorations()
        }
        // Put the mouse on that display so trackpad swipes go there too.
        let c = CGPoint(x: next.frame.midX, y: next.frame.midY)
        CGWarpMouseCursorPosition(c)
    }

    func moveToNextDisplay() {
        guard let id = focusedID, let mw = windows[id], !mw.floating,
              let from = key(of: id), let next = nextDisplay(after: from) else { return }
        strips[from]?.remove(id)
        let to = activeKey(for: next)
        var s = strips[to] ?? Strip()
        s.insert(id, width: config.rule(for: mw.ax.bundleID)?.width ?? config.defaultWidth,
                 position: config.newWindowPosition, focus: true)
        strips[to] = s
        mw.lastFrame = nil
        animator.cancel(id)
        layout(from, animate: true)
        scrollToFocus(to)
        layout(to, animate: false)
        focusStrip(to)
    }
}
