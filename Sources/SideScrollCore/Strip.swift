import Foundation

/// A window is identified by its CGWindowID.
public typealias WinID = UInt32

/// One column on the strip. Holds one window, or several stacked / tabbed.
public struct Column: Equatable, Codable {
    public var id: UUID
    public var windows: [WinID]
    /// Index of the focused (or, when tabbed, visible) window inside the column.
    public var activeIndex: Int
    /// Width as a fraction of the strip viewport.
    public var width: Double
    /// Width to go back to when full-width is toggled off.
    public var widthBeforeFull: Double?
    public var isTabbed: Bool
    /// Relative heights of stacked windows. Missing entries count as 1.
    public var heightWeights: [WinID: Double]

    public init(windows: [WinID], width: Double, isTabbed: Bool = false) {
        self.id = UUID()
        self.windows = windows
        self.activeIndex = 0
        self.width = width
        self.widthBeforeFull = nil
        self.isTabbed = isTabbed
        self.heightWeights = [:]
    }

    public var activeWindow: WinID? {
        windows.isEmpty ? nil : windows[min(max(activeIndex, 0), windows.count - 1)]
    }

    public var isFullWidth: Bool { widthBeforeFull != nil }

    public func weight(_ w: WinID) -> Double { heightWeights[w] ?? 1 }

    mutating func clampActive() {
        if windows.isEmpty { activeIndex = 0 } else { activeIndex = min(max(activeIndex, 0), windows.count - 1) }
    }
}

public enum PinSide: String, Codable, CaseIterable { case left, right }

/// Where focus sits on a strip.
public enum FocusTarget: Equatable {
    case column(Int)
    case pinned(PinSide)
}

/// The endless horizontal strip for one display (and one Space).
public struct Strip: Equatable {
    public var columns: [Column] = []
    public var focusedColumn: Int = 0
    /// True when a pinned column holds focus instead of `focusedColumn`.
    public var focusedPin: PinSide?
    /// Left edge of the viewport in strip coordinates (points).
    public var viewOffset: Double = 0
    public var pinnedLeft: Column?
    public var pinnedRight: Column?

    public init() {}

    public var isEmpty: Bool { columns.isEmpty && pinnedLeft == nil && pinnedRight == nil }

    public var focus: FocusTarget {
        if let p = focusedPin, pinned(p) != nil { return .pinned(p) }
        return .column(focusedColumn)
    }

    public func pinned(_ side: PinSide) -> Column? { side == .left ? pinnedLeft : pinnedRight }

    public var focusedWindow: WinID? {
        switch focus {
        case .pinned(let side): return pinned(side)?.activeWindow
        case .column(let i): return columns.indices.contains(i) ? columns[i].activeWindow : nil
        }
    }

    public var allWindows: [WinID] {
        var out: [WinID] = []
        if let p = pinnedLeft { out += p.windows }
        for c in columns { out += c.windows }
        if let p = pinnedRight { out += p.windows }
        return out
    }

    public func contains(_ w: WinID) -> Bool { locate(w) != nil }

    public enum Location: Equatable {
        case column(Int, Int)
        case pinned(PinSide, Int)
    }

    public func locate(_ w: WinID) -> Location? {
        for (ci, c) in columns.enumerated() {
            if let wi = c.windows.firstIndex(of: w) { return .column(ci, wi) }
        }
        if let wi = pinnedLeft?.windows.firstIndex(of: w) { return .pinned(.left, wi) }
        if let wi = pinnedRight?.windows.firstIndex(of: w) { return .pinned(.right, wi) }
        return nil
    }

    mutating func clampFocus() {
        if columns.isEmpty { focusedColumn = 0 } else { focusedColumn = min(max(focusedColumn, 0), columns.count - 1) }
        if let p = focusedPin, pinned(p) == nil { focusedPin = nil }
    }
}
