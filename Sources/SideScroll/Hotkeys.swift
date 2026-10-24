import AppKit
import Carbon.HIToolbox
import SideScrollCore

/// Global shortcuts through Carbon's RegisterEventHotKey. Needs no extra
/// permission and swallows the key so the frontmost app never sees it.
final class HotkeyManager {
    private var refs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: Action] = [:]
    private var handlerRef: EventHandlerRef?
    var onAction: ((Action) -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, ctx in
            guard let event, let ctx else { return OSStatus(eventNotHandledErr) }
            var hk = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                        nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard err == noErr else { return err }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(ctx).takeUnretainedValue()
            if let action = mgr.actionsByID[hk.id] {
                mgr.onAction?(action)
                return noErr
            }
            return OSStatus(eventNotHandledErr)
        }, 1, &spec, me, &handlerRef)
    }

    func register(_ bindings: Bindings) {
        unregisterAll()
        var next: UInt32 = 1
        for action in Action.allCases {
            for combo in bindings[action] {
                var ref: EventHotKeyRef?
                let id = EventHotKeyID(signature: OSType(0x5353_4352), id: next) // 'SSCR'
                let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetApplicationEventTarget(), 0, &ref)
                if status == noErr, let ref {
                    refs.append(ref)
                    actionsByID[next] = action
                } else {
                    NSLog("SideScroll: could not register \(KeyNames.describe(combo)) for \(action.rawValue) (\(status))")
                }
                next += 1
            }
        }
    }

    func unregisterAll() {
        for r in refs { UnregisterEventHotKey(r) }
        refs.removeAll()
        actionsByID.removeAll()
    }
}

/// Human-readable names for key codes, using the current keyboard layout.
enum KeyNames {
    private static let special: [UInt32: String] = [
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥", UInt32(kVK_Space): "Space", UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦", UInt32(kVK_Escape): "⎋", UInt32(kVK_Home): "Home", UInt32(kVK_End): "End",
        UInt32(kVK_PageUp): "PgUp", UInt32(kVK_PageDown): "PgDn",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    static func keyName(_ keyCode: UInt32) -> String {
        if let s = special[keyCode] { return s }
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "#\(keyCode)"
        }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "#\(keyCode)" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    static func describe(_ combo: KeyCombo) -> String {
        combo.modifierSymbols + keyName(combo.keyCode)
    }

    /// Converts AppKit modifier flags to Carbon masks.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.command) { m |= Mod.cmd }
        if flags.contains(.shift) { m |= Mod.shift }
        if flags.contains(.option) { m |= Mod.option }
        if flags.contains(.control) { m |= Mod.control }
        return m
    }
}
