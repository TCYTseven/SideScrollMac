import AppKit
import ApplicationServices

/// Things an app's windows report through Accessibility notifications.
enum WindowEvent {
    case created(AXUIElement)
    case destroyed(AXUIElement)
    case focused(AXUIElement)
    case moved(AXUIElement)
    case resized(AXUIElement)
    case minimized(AXUIElement)
    case deminimized(AXUIElement)
    case titleChanged(AXUIElement)
    case appHidden
    case appShown
}

/// Watches one running app.
final class AppObserver {
    let pid: pid_t
    let bundleID: String
    let appName: String
    private var observer: AXObserver?
    private let appElement: AXUIElement
    private let handler: (AppObserver, WindowEvent) -> Void
    private var watched: [AXUIElement] = []

    private static let appNotifications = [
        kAXWindowCreatedNotification,
        kAXFocusedWindowChangedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]
    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXTitleChangedNotification,
    ]

    init?(app: NSRunningApplication, handler: @escaping (AppObserver, WindowEvent) -> Void) {
        pid = app.processIdentifier
        bundleID = app.bundleIdentifier ?? "pid.\(app.processIdentifier)"
        appName = app.localizedName ?? bundleID
        appElement = AXUIElementCreateApplication(pid)
        self.handler = handler

        var obs: AXObserver?
        guard AXObserverCreate(pid, appObserverCallback, &obs) == .success, let obs else { return nil }
        observer = obs
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var ok = false
        for n in Self.appNotifications {
            if AXObserverAddNotification(obs, appElement, n as CFString, refcon) == .success { ok = true }
        }
        // Apps that are still launching refuse notifications; the caller retries.
        guard ok else { return nil }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
    }

    deinit { stop() }

    func stop() {
        guard let obs = observer else { return }
        for n in Self.appNotifications { AXObserverRemoveNotification(obs, appElement, n as CFString) }
        for w in watched {
            for n in Self.windowNotifications { AXObserverRemoveNotification(obs, w, n as CFString) }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        watched.removeAll()
        observer = nil
    }

    func watch(_ window: AXUIElement) {
        guard let obs = observer, !watched.contains(where: { CFEqual($0, window) }) else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for n in Self.windowNotifications {
            AXObserverAddNotification(obs, window, n as CFString, refcon)
        }
        watched.append(window)
    }

    func unwatch(_ window: AXUIElement) {
        guard let obs = observer, let i = watched.firstIndex(where: { CFEqual($0, window) }) else { return }
        for n in Self.windowNotifications { AXObserverRemoveNotification(obs, window, n as CFString) }
        watched.remove(at: i)
    }

    fileprivate func dispatch(_ element: AXUIElement, _ name: String) {
        let event: WindowEvent?
        switch name {
        case kAXWindowCreatedNotification: event = .created(element)
        case kAXUIElementDestroyedNotification: event = .destroyed(element)
        case kAXFocusedWindowChangedNotification: event = .focused(element)
        case kAXWindowMovedNotification: event = .moved(element)
        case kAXWindowResizedNotification: event = .resized(element)
        case kAXWindowMiniaturizedNotification: event = .minimized(element)
        case kAXWindowDeminiaturizedNotification: event = .deminimized(element)
        case kAXTitleChangedNotification: event = .titleChanged(element)
        case kAXApplicationHiddenNotification: event = .appHidden
        case kAXApplicationShownNotification: event = .appShown
        default: event = nil
        }
        if let event { handler(self, event) }
    }
}

private func appObserverCallback(_ observer: AXObserver, _ element: AXUIElement,
                                 _ notification: CFString, _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    let me = Unmanaged<AppObserver>.fromOpaque(refcon).takeUnretainedValue()
    me.dispatch(element, notification as String)
}
