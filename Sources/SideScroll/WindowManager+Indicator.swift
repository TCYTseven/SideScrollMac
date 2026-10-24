import AppKit
import SideScrollCore

extension WindowManager {

    /// Shows the strip indicator for `key`. It stays while ⌃⌥ is held,
    /// otherwise it fades after a moment.
    func showIndicator(_ key: StripKey, persistent: Bool? = nil) {
        guard config.showStripIndicator, store.enabled, let s = strips[key], !s.columns.isEmpty,
              let d = display(for: key) else { return }
        indicatorKey = key
        var icons: [pid_t: NSImage] = [:]
        let tiles = s.columns.enumerated().map { (i, c) -> IndicatorTile in
            let mw = c.activeWindow.flatMap { windows[$0] }
            var icon: NSImage?
            if let pid = mw?.ax.pid {
                icon = icons[pid] ?? NSRunningApplication(processIdentifier: pid)?.icon
                icons[pid] = icon
            }
            return IndicatorTile(icon: icon, title: mw?.ax.appName ?? "", count: c.windows.count,
                                 focused: s.focusedPin == nil && i == s.focusedColumn, pinned: false)
        }
        indicator.show(tiles: tiles, on: d.visibleFrame, persistent: persistent ?? modifiersHeld)
    }

    func indicatorSelect(_ i: Int) {
        guard let key = indicatorKey, strips[key]?.columns.indices.contains(i) == true else { return }
        strips[key]?.focusColumn(i)
        scrollToFocus(key)
        layout(key, animate: true)
        focusStrip(key)
        showIndicator(key)
    }

    func indicatorReorder(_ from: Int, _ to: Int) {
        guard let key = indicatorKey, let s = strips[key], s.columns.indices.contains(from) else { return }
        strips[key]?.reorderColumn(from: from, to: to)
        scrollToFocus(key)
        layout(key, animate: true)
        showIndicator(key)
    }

    /// ⌃⌥ held keeps the indicator up; letting go fades it.
    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let held = flags.contains(.control) && flags.contains(.option) && !flags.contains(.command)
        if held && !modifiersHeld {
            modifiersHeld = true
            if let key = currentKey() { showIndicator(key, persistent: true) }
        } else if !held && modifiersHeld {
            modifiersHeld = false
            if indicator.isVisible { indicator.scheduleFade(after: 0.5) }
        }
    }
}
