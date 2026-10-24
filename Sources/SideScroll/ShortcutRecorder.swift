import AppKit
import Carbon.HIToolbox
import SwiftUI
import SideScrollCore

/// Click, then press a key combo. Esc cancels. Needs at least ⌃, ⌥ or ⌘
/// (or a function key) so plain typing is never captured.
final class RecorderField: NSView {
    var onRecord: ((KeyCombo) -> Void)?
    var onCancel: (() -> Void)?
    private var recording = false { didSet { needsDisplay = true } }
    private var liveModifiers: NSEvent.ModifierFlags = []

    override var acceptsFirstResponder: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 120, height: 22) }

    private var resignObserver: NSObjectProtocol?

    // Recording starts only on a click, never because the window picked this
    // view as its first responder, and it always ends when focus leaves.
    override func mouseDown(with event: NSEvent) {
        guard window?.makeFirstResponder(self) == true else { return }
        recording = true
        Store.shared.recordingShortcut = true
    }

    override func resignFirstResponder() -> Bool {
        stop()
        return true
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        stop()
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        resignObserver = nil
        guard let newWindow else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: newWindow, queue: .main) { [weak self] _ in
            self?.stop()
        }
    }

    deinit {
        if let o = resignObserver { NotificationCenter.default.removeObserver(o) }
        if recording { Store.shared.recordingShortcut = false }
    }

    private func stop() {
        guard recording else { return }
        recording = false
        liveModifiers = []
        Store.shared.recordingShortcut = false
    }

    override func flagsChanged(with event: NSEvent) {
        liveModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        let code = UInt32(event.keyCode)
        let mods = KeyNames.carbonModifiers(event.modifierFlags)
        if code == UInt32(kVK_Escape) && mods == 0 {
            stop()
            onCancel?()
            window?.makeFirstResponder(nil)
            return
        }
        let isFunctionKey = (0x60...0x7A).contains(Int(code)) && ![0x73, 0x77].contains(Int(code))
        guard mods & (Mod.control | Mod.option | Mod.cmd) != 0 || isFunctionKey else { NSSound.beep(); return }
        let combo = KeyCombo(code, mods)
        stop()
        window?.makeFirstResponder(nil)
        onRecord?(combo)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘-combos arrive here instead of keyDown.
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
        (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.controlBackgroundColor).setFill()
        path.fill()
        (recording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        path.stroke()
        var text = "Record shortcut"
        if recording {
            let m = KeyNames.carbonModifiers(liveModifiers)
            text = m == 0 ? "Press keys…" : KeyCombo(0, m).modifierSymbols + "…"
        }
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: recording ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
            .paragraphStyle: style,
        ]
        (text as NSString).draw(in: bounds.insetBy(dx: 4, dy: 3), withAttributes: attrs)
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (KeyCombo) -> Void

    func makeNSView(context: Context) -> RecorderField {
        let v = RecorderField()
        v.onRecord = onRecord
        return v
    }

    func updateNSView(_ nsView: RecorderField, context: Context) {
        nsView.onRecord = onRecord
    }
}
