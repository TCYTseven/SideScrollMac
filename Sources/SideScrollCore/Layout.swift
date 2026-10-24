import Foundation
import CoreGraphics

/// How the viewport follows focus.
public enum CenterMode: String, Codable, CaseIterable {
    /// Scroll just enough to show the focused column (niri "never").
    case never
    /// Always put the focused column in the middle.
    case always
    /// Center only when the focused column would not fit next to the previous one.
    case onOverflow
}

public struct LayoutParams: Equatable {
    /// Usable area of the display (menu bar and Dock removed, outer padding applied),
    /// in top-left-origin global coordinates.
    public var area: CGRect
    /// Full bounds of the display, used for hiding windows off its edges.
    public var screen: CGRect
    public var gap: Double
    public var tabBarHeight: Double
    public var keepOriginalHeight: Bool
    public var originalHeights: [WinID: Double]
    /// Another display touches this one on the left / right edge.
    public var neighborLeft: Bool
    public var neighborRight: Bool

    public init(area: CGRect, screen: CGRect, gap: Double, tabBarHeight: Double = 24,
                keepOriginalHeight: Bool = false, originalHeights: [WinID: Double] = [:],
                neighborLeft: Bool = false, neighborRight: Bool = false) {
        self.area = area
        self.screen = screen
        self.gap = gap
        self.tabBarHeight = tabBarHeight
        self.keepOriginalHeight = keepOriginalHeight
        self.originalHeights = originalHeights
        self.neighborLeft = neighborLeft
        self.neighborRight = neighborRight
    }
}

public struct Placement: Equatable {
    public var window: WinID
    public var frame: CGRect
    /// False when the window is parked off-screen (scrolled away or a background tab).
    public var visible: Bool
}

/// Frame of a tab bar drawn above a tabbed column.
public struct TabBarPlacement: Equatable {
    public var columnID: UUID
    public var frame: CGRect
    public var windows: [WinID]
    public var activeIndex: Int
}

public struct LayoutResult: Equatable {
    public var placements: [Placement]
    public var tabBars: [TabBarPlacement]
    /// Visible frame of each column, for hit testing and drag-to-reorder.
    public var columnFrames: [UUID: CGRect]
}

public enum Layout {

    // MARK: Geometry of the strip

    /// The part of `area` the scrolling columns use once pinned columns are taken out.
    public static func viewport(_ strip: Strip, _ p: LayoutParams) -> CGRect {
        var r = p.area
        if let l = strip.pinnedLeft {
            let w = columnWidth(l, r.width, p.gap)
            r.origin.x += w + p.gap
            r.size.width -= w + p.gap
        }
        if let rt = strip.pinnedRight {
            let w = columnWidth(rt, p.area.width, p.gap)
            r.size.width -= w + p.gap
        }
        r.size.width = max(r.size.width, 100)
        return r
    }

    /// Pixel width of a column for a given viewport width. Two 0.5 columns plus
    /// the gap between them fill the viewport exactly.
    public static func columnWidth(_ c: Column, _ viewportWidth: Double, _ gap: Double) -> Double {
        max((c.width * (viewportWidth + gap) - gap).rounded(), c.minWidth)
    }

    /// Left edge of every column in strip coordinates.
    public static func columnXs(_ strip: Strip, _ viewportWidth: Double, _ gap: Double) -> [Double] {
        var xs: [Double] = []
        var x = 0.0
        for c in strip.columns {
            xs.append(x)
            x += columnWidth(c, viewportWidth, gap) + gap
        }
        return xs
    }

    public static func totalWidth(_ strip: Strip, _ viewportWidth: Double, _ gap: Double) -> Double {
        let xs = columnXs(strip, viewportWidth, gap)
        guard let last = strip.columns.last, let lx = xs.last else { return 0 }
        return lx + columnWidth(last, viewportWidth, gap)
    }

    // MARK: Scrolling

    /// View offset that shows column `i` according to `mode`, starting from `current`.
    public static func offsetShowing(_ i: Int, _ strip: Strip, viewportWidth W: Double, gap: Double,
                                     mode: CenterMode, current: Double) -> Double {
        guard strip.columns.indices.contains(i) else { return current }
        let xs = columnXs(strip, W, gap)
        let x = xs[i]
        let w = columnWidth(strip.columns[i], W, gap)
        let centered = x + w / 2 - W / 2
        if w >= W { return x }
        switch mode {
        case .always:
            return centered
        case .onOverflow:
            // If the column fits alongside the previous one, show both; otherwise center.
            if i > 0 {
                let px = xs[i - 1]
                if x + w - px <= W {
                    return clampToShow(x: x, w: w, W: W, current: current, gap: gap, prevX: px)
                }
                return centered
            }
            return clampToShow(x: x, w: w, W: W, current: current, gap: gap, prevX: nil)
        case .never:
            return clampToShow(x: x, w: w, W: W, current: current, gap: gap, prevX: nil)
        }
    }

    private static func clampToShow(x: Double, w: Double, W: Double, current: Double, gap: Double, prevX: Double?) -> Double {
        var o = current
        if x < o { o = x }
        if x + w > o + W { o = x + w - W }
        if let px = prevX, px < o, x + w - px <= W { o = max(px, x + w - W) }
        return o
    }

    /// After a free scroll (trackpad), picks the column to focus and the offset
    /// to settle on. `projected` already includes momentum.
    public static func snap(_ strip: Strip, viewportWidth W: Double, gap: Double,
                            projected: Double) -> (column: Int, offset: Double) {
        guard !strip.columns.isEmpty else { return (0, 0) }
        let xs = columnXs(strip, W, gap)
        let center = projected + W / 2
        var best = 0
        var bestDist = Double.infinity
        for (i, c) in strip.columns.enumerated() {
            let w = columnWidth(c, W, gap)
            let lo = xs[i], hi = xs[i] + w
            let d = center < lo ? lo - center : (center > hi ? center - hi : 0)
            // Prefer the column under the center; ties go to the nearer center.
            let score = d * 10 + abs((lo + hi) / 2 - center) * 0.01
            if score < bestDist { bestDist = score; best = i }
        }
        let w = columnWidth(strip.columns[best], W, gap)
        let x = xs[best]
        let total = totalWidth(strip, W, gap)
        var offset = projected
        if w >= W {
            offset = x
        } else {
            // Keep the projected position if the column stays fully visible,
            // otherwise slide just enough to show it, aligning to a column edge.
            offset = min(max(offset, x + w - W), x)
            offset = alignToEdges(offset, xs: xs, strip: strip, W: W, gap: gap, keepVisible: (x, w))
        }
        // Do not leave empty space past the ends of the strip.
        if total <= W {
            offset = 0
        } else {
            offset = min(max(offset, 0), total - W)
            if x < offset { offset = x }
            if x + w > offset + W { offset = x + w - W }
        }
        return (best, offset)
    }

    /// Snaps the offset so the viewport starts or ends on a column edge, if one is close.
    private static func alignToEdges(_ offset: Double, xs: [Double], strip: Strip, W: Double, gap: Double,
                                     keepVisible: (Double, Double)) -> Double {
        var candidates: [Double] = []
        for (i, c) in strip.columns.enumerated() {
            let w = columnWidth(c, W, gap)
            candidates.append(xs[i])            // column starts at left edge
            candidates.append(xs[i] + w - W)    // column ends at right edge
        }
        let (kx, kw) = keepVisible
        let valid = candidates.filter { $0 <= kx + 0.5 && $0 + W >= kx + kw - 0.5 }
        guard let nearest = valid.min(by: { abs($0 - offset) < abs($1 - offset) }) else { return offset }
        return nearest
    }

    // MARK: Placement

    public static func compute(_ strip: Strip, _ p: LayoutParams, viewOffset: Double? = nil) -> LayoutResult {
        var placements: [Placement] = []
        var tabBars: [TabBarPlacement] = []
        var columnFrames: [UUID: CGRect] = [:]
        let vp = viewport(strip, p)
        let offset = viewOffset ?? strip.viewOffset
        let xs = columnXs(strip, vp.width, p.gap)

        func place(column c: Column, x: Double, width: Double, visible colVisible: Bool) {
            let colRect = CGRect(x: x, y: p.area.minY, width: width, height: p.area.height)
            columnFrames[c.id] = colRect
            var top: Double = p.area.minY
            var height: Double = p.area.height
            if c.isTabbed && c.windows.count > 1 {
                if colVisible {
                    tabBars.append(TabBarPlacement(
                        columnID: c.id,
                        frame: CGRect(x: x, y: top, width: width, height: p.tabBarHeight),
                        windows: c.windows, activeIndex: c.activeIndex))
                }
                top += p.tabBarHeight + 2
                height -= p.tabBarHeight + 2
                for (i, w) in c.windows.enumerated() {
                    let f = CGRect(x: x, y: top, width: width, height: height)
                    let shown = colVisible && i == c.activeIndex
                    placements.append(Placement(window: w, frame: shown ? f : hide(f, p, preferRight: true), visible: shown))
                }
                return
            }
            if c.windows.count == 1, let w = c.windows.first {
                var h = height
                if p.keepOriginalHeight, let oh = p.originalHeights[w] { h = min(oh, height) }
                let f = CGRect(x: x, y: top, width: width, height: h)
                placements.append(Placement(window: w, frame: f, visible: colVisible))
                return
            }
            let totalGap = p.gap * Double(max(c.windows.count - 1, 0))
            let weights = c.windows.map { c.weight($0) }
            let sum = weights.reduce(0, +)
            var y: Double = top
            for (i, w) in c.windows.enumerated() {
                let h: Double
                if i == c.windows.count - 1 {
                    h = top + height - y
                } else {
                    h = ((height - totalGap) * weights[i] / sum).rounded()
                }
                placements.append(Placement(window: w, frame: CGRect(x: x, y: y, width: width, height: h), visible: colVisible))
                y += h + p.gap
            }
        }

        if let l = strip.pinnedLeft {
            let w = columnWidth(l, p.area.width, p.gap)
            place(column: l, x: p.area.minX, width: w, visible: true)
        }
        if let r = strip.pinnedRight {
            let w = columnWidth(r, p.area.width, p.gap)
            place(column: r, x: p.area.maxX - w, width: w, visible: true)
        }

        for (i, c) in strip.columns.enumerated() {
            let w = columnWidth(c, vp.width, p.gap)
            let screenX = vp.minX + xs[i] - offset
            // Visible if any part of the column is inside the viewport.
            let visible = screenX + w > vp.minX + 1 && screenX < vp.maxX - 1
            let start = placements.count
            place(column: c, x: screenX, width: w, visible: visible)
            // Post-process: park or clamp windows of this column.
            for k in start..<placements.count {
                var pl = placements[k]
                if !visible {
                    pl.frame = hide(pl.frame, p, preferRight: screenX >= vp.maxX - 1)
                    pl.visible = false
                } else if pl.visible {
                    pl.frame = clampToNeighbors(pl.frame, p)
                }
                placements[k] = pl
            }
        }
        return LayoutResult(placements: placements, tabBars: tabBars, columnFrames: columnFrames)
    }

    /// Parks a window just past a display edge, leaving one point on screen
    /// (macOS will not let a window go fully off-screen). Picks an edge with no
    /// neighbouring display so the window does not show up on another screen.
    public static func hide(_ f: CGRect, _ p: LayoutParams, preferRight: Bool) -> CGRect {
        var r = f
        let rightFree = !p.neighborRight
        let leftFree = !p.neighborLeft
        if (preferRight && rightFree) || (!leftFree && rightFree) {
            r.origin.x = p.screen.maxX - 1
        } else if leftFree {
            r.origin.x = p.screen.minX - r.width + 1
        } else {
            // Both sides have displays: tuck into the bottom-right corner.
            r.origin.x = p.screen.maxX - 1
            r.origin.y = p.screen.maxY - 1
        }
        return r
    }

    /// A partly visible window next to another display snaps flush to the edge
    /// instead of spilling onto the neighbour.
    static func clampToNeighbors(_ f: CGRect, _ p: LayoutParams) -> CGRect {
        var r = f
        if p.neighborLeft && r.minX < p.screen.minX { r.origin.x = p.screen.minX }
        if p.neighborRight && r.maxX > p.screen.maxX { r.origin.x = p.screen.maxX - r.width }
        return r
    }
}
