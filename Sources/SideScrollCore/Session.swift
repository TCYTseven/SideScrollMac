import Foundation

/// Enough about a window to find it again after SideScroll or the Mac restarts.
public struct WindowIdentity: Codable, Equatable {
    public var windowID: WinID
    public var bundleID: String
    public var title: String

    public init(windowID: WinID, bundleID: String, title: String) {
        self.windowID = windowID
        self.bundleID = bundleID
        self.title = title
    }
}

public struct ColumnSnapshot: Codable, Equatable {
    public var windows: [WindowIdentity]
    public var width: Double
    public var isTabbed: Bool
    public var pinned: PinSide?

    public init(windows: [WindowIdentity], width: Double, isTabbed: Bool, pinned: PinSide? = nil) {
        self.windows = windows
        self.width = width
        self.isTabbed = isTabbed
        self.pinned = pinned
    }
}

public struct StripSnapshot: Codable, Equatable {
    public var display: String
    public var columns: [ColumnSnapshot]

    public init(display: String, columns: [ColumnSnapshot]) {
        self.display = display
        self.columns = columns
    }
}

public struct SessionSnapshot: Codable, Equatable {
    public var strips: [StripSnapshot]
    public init(strips: [StripSnapshot] = []) { self.strips = strips }
}

public enum SessionRestore {

    /// Rebuilds a strip from a snapshot. `available` lists the live windows on
    /// this display in their current on-screen order. Windows are matched by ID
    /// first, then by app and title, then by app alone. Unmatched live windows
    /// are appended at the end.
    public static func rebuild(_ snap: StripSnapshot, available: [WindowIdentity], defaultWidth: Double) -> Strip {
        var pool = available
        func take(_ want: WindowIdentity) -> WinID? {
            if let i = pool.firstIndex(where: { $0.windowID == want.windowID && $0.bundleID == want.bundleID }) {
                return pool.remove(at: i).windowID
            }
            if !want.title.isEmpty,
               let i = pool.firstIndex(where: { $0.bundleID == want.bundleID && $0.title == want.title }) {
                return pool.remove(at: i).windowID
            }
            return nil
        }
        func takeLoose(_ want: WindowIdentity) -> WinID? {
            if let i = pool.firstIndex(where: { $0.bundleID == want.bundleID }) {
                return pool.remove(at: i).windowID
            }
            return nil
        }

        // Two passes: exact matches first so loose matches cannot steal them.
        var resolved: [[WinID?]] = snap.columns.map { col in col.windows.map { take($0) } }
        for (ci, col) in snap.columns.enumerated() {
            for (wi, want) in col.windows.enumerated() where resolved[ci][wi] == nil {
                resolved[ci][wi] = takeLoose(want)
            }
        }

        var strip = Strip()
        for (ci, col) in snap.columns.enumerated() {
            let ids = resolved[ci].compactMap { $0 }
            guard !ids.isEmpty else { continue }
            var c = Column(windows: ids, width: col.width, isTabbed: col.isTabbed)
            c.activeIndex = 0
            if let side = col.pinned {
                if strip.pinned(side) == nil { strip.setPinned(side, c); continue }
                c.width = defaultWidth
            }
            strip.columns.append(c)
        }
        for w in pool {
            strip.columns.append(Column(windows: [w.windowID], width: defaultWidth))
        }
        strip.focusedColumn = 0
        return strip
    }

    public static func snapshot(_ strip: Strip, display: String, identify: (WinID) -> WindowIdentity?) -> StripSnapshot {
        func snap(_ c: Column, _ pin: PinSide?) -> ColumnSnapshot? {
            let ids = c.windows.compactMap(identify)
            guard !ids.isEmpty else { return nil }
            return ColumnSnapshot(windows: ids, width: c.widthBeforeFull ?? c.width, isTabbed: c.isTabbed, pinned: pin)
        }
        var cols: [ColumnSnapshot] = []
        if let p = strip.pinnedLeft, let s = snap(p, .left) { cols.append(s) }
        cols += strip.columns.compactMap { snap($0, nil) }
        if let p = strip.pinnedRight, let s = snap(p, .right) { cols.append(s) }
        return StripSnapshot(display: display, columns: cols)
    }
}
