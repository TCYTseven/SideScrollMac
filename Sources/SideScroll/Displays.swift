import AppKit
import SideScrollCore

/// One connected display, in the top-left-origin coordinates the
/// Accessibility API uses.
struct Display: Equatable {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    /// Whole screen.
    let frame: CGRect
    /// Screen minus menu bar and Dock.
    let visibleFrame: CGRect
    let neighborLeft: Bool
    let neighborRight: Bool

    /// Current Space on this display. Used to keep one strip per Space.
    var currentSpace: UInt64 {
        let cid = CGSMainConnectionID()
        let s = CGSManagedDisplayGetCurrentSpace(cid, uuid as CFString)
        return s != 0 ? s : CGSGetActiveSpace(cid)
    }

    func layoutParams(_ config: Config, originalHeights: [WinID: Double]) -> LayoutParams {
        // Without Dock awareness, still keep clear of the menu bar.
        let base = config.respectDock ? visibleFrame
            : CGRect(x: frame.minX, y: visibleFrame.minY, width: frame.width, height: frame.maxY - visibleFrame.minY)
        let pad = config.outerPadding
        let area = base.insetBy(dx: pad, dy: pad)
        return LayoutParams(area: area, screen: frame, gap: config.gap, tabBarHeight: config.tabBarHeight,
                            keepOriginalHeight: config.keepOriginalHeight, originalHeights: originalHeights,
                            neighborLeft: neighborLeft, neighborRight: neighborRight)
    }
}

enum Displays {
    /// Height of the primary screen; flips between AppKit and AX coordinates.
    static var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    static func flip(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: primaryHeight - r.maxY, width: r.width, height: r.height)
    }

    static func all() -> [Display] {
        let screens = NSScreen.screens
        let frames = screens.map { flip($0.frame) }
        return screens.enumerated().compactMap { (i, s) in
            guard let num = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(num.uint32Value)
            let f = frames[i]
            // A neighbour shares a vertical edge and overlaps vertically.
            let others = frames.enumerated().filter { $0.offset != i }.map { $0.element }
            let left = others.contains { abs($0.maxX - f.minX) < 2 && $0.maxY > f.minY && $0.minY < f.maxY }
            let right = others.contains { abs($0.minX - f.maxX) < 2 && $0.maxY > f.minY && $0.minY < f.maxY }
            return Display(id: id, uuid: uuidString(id), name: s.localizedName, frame: f,
                           visibleFrame: flip(s.visibleFrame), neighborLeft: left, neighborRight: right)
        }
    }

    static func uuidString(_ id: CGDirectDisplayID) -> String {
        guard let u = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return "display-\(id)" }
        return (CFUUIDCreateString(nil, u) as String?) ?? "display-\(id)"
    }

    /// Display containing most of `rect`, else the one nearest its center.
    static func containing(_ rect: CGRect, in displays: [Display]) -> Display? {
        var best: Display?
        var bestArea: CGFloat = 0
        for d in displays {
            let i = d.frame.intersection(rect)
            let a = i.isNull ? 0 : i.width * i.height
            if a > bestArea { bestArea = a; best = d }
        }
        if let best { return best }
        let c = CGPoint(x: rect.midX, y: rect.midY)
        return displays.min { dist($0.frame, c) < dist($1.frame, c) }
    }

    static func containing(point p: CGPoint, in displays: [Display]) -> Display? {
        displays.first { $0.frame.contains(p) } ?? displays.first
    }

    private static func dist(_ r: CGRect, _ p: CGPoint) -> CGFloat {
        let dx = max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = max(r.minY - p.y, 0, p.y - r.maxY)
        return dx * dx + dy * dy
    }

    /// Mouse location in AX coordinates.
    static var mouseLocation: CGPoint {
        let p = NSEvent.mouseLocation
        return CGPoint(x: p.x, y: primaryHeight - p.y)
    }
}
