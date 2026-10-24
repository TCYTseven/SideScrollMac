import AppKit
import SideScrollCore

/// Borderless, click-through window used for decorations.
private func makeOverlayWindow(clickThrough: Bool = true) -> NSPanel {
    let w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    w.isOpaque = false
    w.backgroundColor = .clear
    w.hasShadow = false
    w.ignoresMouseEvents = clickThrough
    w.level = .normal
    w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
    w.isReleasedWhenClosed = false
    w.hidesOnDeactivate = false
    w.animationBehavior = .none
    return w
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let a = s.count == 8 ? CGFloat(v & 0xFF) / 255 : 1
        let rgb = s.count == 8 ? v >> 8 : v
        self.init(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: a)
    }

    var hexString: String {
        guard let c = usingColorSpace(.sRGB) else { return "#4C8DFF" }
        return String(format: "#%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

/// AX rect (top-left origin) to AppKit rect (bottom-left origin).
func appKitRect(_ r: CGRect) -> CGRect { Displays.flip(r) }

// MARK: - Focus border

private final class BorderView: NSView {
    var color: NSColor = .systemBlue { didSet { needsDisplay = true } }
    var lineWidth: CGFloat = 3 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        let inset = lineWidth / 2
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: inset, dy: inset), xRadius: 10, yRadius: 10)
        path.lineWidth = lineWidth
        color.setStroke()
        path.stroke()
    }
}

final class FocusBorder {
    private let window = makeOverlayWindow()
    private let view = BorderView()

    init() { window.contentView = view }

    func show(around frame: CGRect, windowNumber: CGWindowID, color: NSColor, width: CGFloat) {
        view.color = color
        view.lineWidth = width
        let r = appKitRect(frame).insetBy(dx: -width, dy: -width)
        window.setFrame(r, display: true)
        // Sit directly above the focused window, so windows in front of it still cover the border.
        window.order(.above, relativeTo: Int(windowNumber))
    }

    func hide() { window.orderOut(nil) }
}

// MARK: - Dim everything except the focused window

final class DimOverlay {
    private var windows: [CGDirectDisplayID: NSPanel] = [:]

    func show(below windowNumber: CGWindowID, displays: [Display], amount: Double) {
        let ids = Set(displays.map { $0.id })
        for (id, w) in windows where !ids.contains(id) { w.orderOut(nil); windows[id] = nil }
        for d in displays {
            let w = windows[d.id] ?? {
                let p = makeOverlayWindow()
                windows[d.id] = p
                return p
            }()
            w.backgroundColor = NSColor.black.withAlphaComponent(CGFloat(amount))
            w.setFrame(appKitRect(d.frame), display: false)
            // Directly below the focused window: dims every window behind it.
            w.order(.below, relativeTo: Int(windowNumber))
        }
    }

    func hide() { windows.values.forEach { $0.orderOut(nil) } }
}

// MARK: - Tab bars for tabbed columns

final class TabBarView: NSView {
    var titles: [String] = [] { didSet { needsDisplay = true } }
    var active = 0 { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let bg = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        bg.fill()
        guard !titles.isEmpty else { return }
        let w = bounds.width / CGFloat(titles.count)
        for (i, t) in titles.enumerated() {
            let r = CGRect(x: CGFloat(i) * w, y: 0, width: w, height: bounds.height).insetBy(dx: 2, dy: 2)
            if i == active {
                NSColor.controlAccentColor.withAlphaComponent(0.85).setFill()
                NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: i == active ? .semibold : .regular),
                .foregroundColor: i == active ? NSColor.white : NSColor.labelColor,
                .paragraphStyle: style,
            ]
            let textRect = r.insetBy(dx: 6, dy: (r.height - 14) / 2)
            (t as NSString).draw(in: textRect, withAttributes: attrs)
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard !titles.isEmpty else { return }
        let p = convert(event.locationInWindow, from: nil)
        let i = Int(p.x / (bounds.width / CGFloat(titles.count)))
        onSelect?(min(max(i, 0), titles.count - 1))
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class TabBars {
    private var bars: [UUID: (NSPanel, TabBarView)] = [:]
    var onSelect: ((UUID, Int) -> Void)?

    func update(_ placements: [TabBarPlacement], titles: (WinID) -> String, above: (TabBarPlacement) -> CGWindowID?) {
        let keep = Set(placements.map { $0.columnID })
        for (id, bar) in bars where !keep.contains(id) {
            bar.0.orderOut(nil)
            bars[id] = nil
        }
        for p in placements {
            let w: NSPanel
            let v: TabBarView
            if let existing = bars[p.columnID] {
                w = existing.0
                v = existing.1
            } else {
                w = makeOverlayWindow(clickThrough: false)
                v = TabBarView()
                w.contentView = v
                let colID = p.columnID
                v.onSelect = { [weak self] i in self?.onSelect?(colID, i) }
                bars[p.columnID] = (w, v)
            }
            v.titles = p.windows.map(titles)
            v.active = p.activeIndex
            w.setFrame(appKitRect(p.frame), display: true)
            if let num = above(p) { w.order(.above, relativeTo: Int(num)) } else { w.orderFront(nil) }
        }
    }

    func hideAll() {
        bars.values.forEach { $0.0.orderOut(nil) }
        bars.removeAll()
    }
}
