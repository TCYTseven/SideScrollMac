import AppKit
import ApplicationServices
import SideScrollCore

// Private but stable APIs, used by most macOS window managers.
@_silgen_name("_AXUIElementGetWindow") @discardableResult
func _AXUIElementGetWindow(_ element: AXUIElement, _ wid: inout CGWindowID) -> AXError

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> Int32

@_silgen_name("CGSGetActiveSpace")
func CGSGetActiveSpace(_ cid: Int32) -> UInt64

@_silgen_name("CGSManagedDisplayGetCurrentSpace")
func CGSManagedDisplayGetCurrentSpace(_ cid: Int32, _ display: CFString) -> UInt64

enum AX {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func attr<T>(_ el: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v else { return nil }
        return v as? T
    }

    static func point(_ el: AXUIElement, _ name: String) -> CGPoint? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var p = CGPoint.zero
        return AXValueGetValue(v as! AXValue, .cgPoint, &p) ? p : nil
    }

    static func size(_ el: AXUIElement, _ name: String) -> CGSize? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &v) == .success, let v,
              CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
        var s = CGSize.zero
        return AXValueGetValue(v as! AXValue, .cgSize, &s) ? s : nil
    }

    static func windowID(_ el: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        return _AXUIElementGetWindow(el, &id) == .success && id != 0 ? id : nil
    }
}

/// A window of another app, reached through the Accessibility API.
final class AXWin {
    let element: AXUIElement
    let id: WinID
    let pid: pid_t
    let bundleID: String
    let appName: String

    init(element: AXUIElement, id: WinID, pid: pid_t, bundleID: String, appName: String) {
        self.element = element
        self.id = id
        self.pid = pid
        self.bundleID = bundleID
        self.appName = appName
    }

    var title: String { AX.attr(element, kAXTitleAttribute) ?? "" }
    var role: String { AX.attr(element, kAXRoleAttribute) ?? "" }
    var subrole: String { AX.attr(element, kAXSubroleAttribute) ?? "" }
    var isMinimized: Bool { AX.attr(element, kAXMinimizedAttribute) ?? false }
    var isFullscreen: Bool { AX.attr(element, "AXFullScreen") ?? false }
    var isModal: Bool { AX.attr(element, kAXModalAttribute) ?? false }

    var isResizable: Bool {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(element, kAXSizeAttribute as CFString, &settable)
        return settable.boolValue
    }

    /// Frame in top-left-origin global coordinates.
    var frame: CGRect? {
        guard let p = AX.point(element, kAXPositionAttribute), let s = AX.size(element, kAXSizeAttribute) else { return nil }
        return CGRect(origin: p, size: s)
    }

    func setPosition(_ p: CGPoint) {
        var p = p
        guard let v = AXValueCreate(.cgPoint, &p) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, v)
    }

    func setSize(_ s: CGSize) {
        var s = s
        guard let v = AXValueCreate(.cgSize, &s) else { return }
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, v)
    }

    /// Size, then position, then size again: some apps clamp the size to the
    /// screen space left at their old position.
    func setFrame(_ f: CGRect, sizeChanged: Bool = true) {
        AXApp.withoutEnhancedUI(pid) {
            if sizeChanged { setSize(f.size) }
            setPosition(f.origin)
            if sizeChanged { setSize(f.size) }
        }
    }

    func focus() {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(app, kAXFocusedWindowAttribute as CFString, element)
        AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        if let running = NSRunningApplication(processIdentifier: pid), !running.isActive {
            running.activate(options: [.activateIgnoringOtherApps])
        }
    }

    func close() {
        if let button: AXUIElement = AX.attr(element, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(button, kAXPressAction as CFString)
        }
    }

    /// Standard, resizable document-style window that belongs on the strip.
    var isTileable: Bool {
        role == kAXWindowRole && subrole == kAXStandardWindowSubrole
    }
}

enum AXApp {

    /// Some apps (Chrome, Firefox, Office) animate frame changes when
    /// AXEnhancedUserInterface is on, which makes tiling laggy. Turn it off
    /// for the duration of the change.
    static func withoutEnhancedUI(_ pid: pid_t, _ body: () -> Void) {
        let app = AXUIElementCreateApplication(pid)
        let enabled: Bool = AX.attr(app, "AXEnhancedUserInterface") ?? false
        if enabled { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        body()
        if enabled { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
    }

    static func windows(of pid: pid_t) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        return AX.attr(app, kAXWindowsAttribute) ?? []
    }

    static func focusedWindow(of pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        return AX.attr(app, kAXFocusedWindowAttribute)
    }
}

/// IDs of normal-layer windows on the current Spaces, front to back.
func onScreenWindowIDs() -> [CGWindowID] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
    return list.compactMap { info in
        guard (info[kCGWindowLayer as String] as? Int) == 0 else { return nil }
        return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
    }
}
