import AppKit
import SideScrollCore

/// One tile per column, drawn in the indicator.
struct IndicatorTile {
    let icon: NSImage?
    let title: String
    let count: Int
    let focused: Bool
    let pinned: Bool
}

/// Frosted bar of app icons at the bottom of a display. Appears while you
/// navigate and fades out; stays while ⌃⌥ is held. Click a tile to jump to
/// that column, drag a tile to reorder columns.
final class StripIndicator {
    private let panel: NSPanel
    private let blur = NSVisualEffectView()
    private let tilesView = IndicatorTilesView()
    private var fadeWork: DispatchWorkItem?
    private(set) var isVisible = false

    var onSelect: ((Int) -> Void)? {
        get { tilesView.onSelect }
        set { tilesView.onSelect = newValue }
    }
    var onReorder: ((Int, Int) -> Void)? {
        get { tilesView.onReorder }
        set { tilesView.onReorder = newValue }
    }

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none

        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.addSubview(tilesView)
        panel.contentView = blur
    }

    /// `display` is the full display frame in AX coordinates; `visible` its usable area.
    func show(tiles: [IndicatorTile], on visible: CGRect, persistent: Bool) {
        guard !tiles.isEmpty else { hide(); return }
        tilesView.tiles = tiles
        let size = tilesView.preferredSize(maxWidth: visible.width - 40)
        tilesView.frame = NSRect(origin: .zero, size: size)
        let axFrame = CGRect(x: visible.midX - size.width / 2, y: visible.maxY - size.height - 18,
                             width: size.width, height: size.height)
        panel.setFrame(appKitRect(axFrame), display: true)
        if !isVisible {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.12
                panel.animator().alphaValue = 1
            }
        } else {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
        }
        isVisible = true
        fadeWork?.cancel()
        if !persistent { scheduleFade(after: 1.2) }
    }

    func scheduleFade(after delay: Double) {
        fadeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.fade() }
        fadeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func fade() {
        guard isVisible, !tilesView.isTracking else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.panel.alphaValue == 0 else { return }
            self.panel.orderOut(nil)
            self.isVisible = false
        })
    }

    func hide() {
        fadeWork?.cancel()
        panel.orderOut(nil)
        isVisible = false
    }
}

final class IndicatorTilesView: NSView {
    var tiles: [IndicatorTile] = [] { didSet { needsDisplay = true } }
    var onSelect: ((Int) -> Void)?
    var onReorder: ((Int, Int) -> Void)?
    private(set) var isTracking = false
    private var dragFrom: Int?
    private var dragTo: Int?
    private var dragStartX: CGFloat = 0

    private let tile: CGFloat = 40
    private let spacing: CGFloat = 8
    private let pad: CGFloat = 10

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    func preferredSize(maxWidth: CGFloat) -> NSSize {
        let n = CGFloat(tiles.count)
        let w = pad * 2 + n * tile + max(n - 1, 0) * spacing
        return NSSize(width: min(w, maxWidth), height: tile + pad * 2 + 6)
    }

    private var step: CGFloat {
        // Shrink spacing when there are too many tiles to fit.
        let n = CGFloat(max(tiles.count, 1))
        let natural = tile + spacing
        let available = (bounds.width - pad * 2 + spacing) / n
        return min(natural, available)
    }

    private func rect(_ i: Int) -> NSRect {
        let s = step
        let size = min(tile, s - 2)
        return NSRect(x: pad + CGFloat(i) * s, y: pad, width: size, height: size)
    }

    private func index(at x: CGFloat) -> Int {
        min(max(Int((x - pad) / step), 0), max(tiles.count - 1, 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        for (i, t) in tiles.enumerated() {
            var r = rect(i)
            if let from = dragFrom, let to = dragTo, from != to {
                // Show the dragged tile at its drop position.
                if i == from { r = rect(to) } else if from < to, i > from, i <= to { r = rect(i - 1) }
                else if from > to, i >= to, i < from { r = rect(i + 1) }
            }
            if t.focused {
                NSColor.controlAccentColor.withAlphaComponent(0.9).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: -4, dy: -4), xRadius: 9, yRadius: 9).fill()
            }
            if let icon = t.icon {
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: i == dragFrom ? 0.6 : 1)
            } else {
                NSColor.secondaryLabelColor.setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            if t.count > 1 {
                // Small badge with the number of windows in the column.
                let badge = NSRect(x: r.maxX - 13, y: r.maxY - 13, width: 15, height: 15)
                NSColor.black.withAlphaComponent(0.75).setFill()
                NSBezierPath(ovalIn: badge).fill()
                let attrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 9, weight: .bold), .foregroundColor: NSColor.white,
                ]
                let str = "\(t.count)" as NSString
                let sz = str.size(withAttributes: attrs)
                str.draw(at: NSPoint(x: badge.midX - sz.width / 2, y: badge.midY - sz.height / 2), withAttributes: attrs)
            }
            if t.pinned {
                let dot = NSRect(x: r.midX - 2.5, y: r.maxY + 3, width: 5, height: 5)
                NSColor.labelColor.setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        isTracking = true
        dragFrom = index(at: p.x)
        dragTo = dragFrom
        dragStartX = p.x
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard abs(p.x - dragStartX) > 6 else { return }
        dragTo = index(at: p.x)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        defer {
            isTracking = false
            dragFrom = nil
            dragTo = nil
            needsDisplay = true
        }
        guard let from = dragFrom else { return }
        if abs(p.x - dragStartX) > 6, let to = dragTo, to != from {
            onReorder?(from, to)
        } else {
            onSelect?(from)
        }
    }
}
