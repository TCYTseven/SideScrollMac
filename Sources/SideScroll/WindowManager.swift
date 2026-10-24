import AppKit
import Combine
import SideScrollCore

/// One strip per display per Space.
struct StripKey: Hashable {
    let display: String
    let space: UInt64
}

/// A window SideScroll knows about.
final class ManagedWindow {
    let ax: AXWin
    var floating: Bool
    /// Frame SideScroll last asked for. Used to tell our moves from the user's.
    var lastFrame: CGRect?
    var lastSetAt: CFTimeInterval = 0
    var originalSize: CGSize
    /// Where it sat before being minimized or hidden, to put it back there.
    var parkedAt: (key: StripKey, column: Int)?

    init(ax: AXWin, floating: Bool, originalSize: CGSize) {
        self.ax = ax
        self.floating = floating
        self.originalSize = originalSize
    }

    var id: WinID { ax.id }
}

final class WindowManager {
    let store = Store.shared
    var config: Config { store.config }

    var displays: [Display] = []
    var observers: [pid_t: AppObserver] = [:]
    var windows: [WinID: ManagedWindow] = [:]
    var strips: [StripKey: Strip] = [:]
    var lastLayout: [StripKey: LayoutResult] = [:]
    /// Window IDs of apps and windows the rules say to ignore.
    var ignored: Set<WinID> = []
    var focusedID: WinID?

    let animator = Animator()
    let border = FocusBorder()
    let dim = DimOverlay()
    let tabBars = TabBars()
    let trackpad = TrackpadMonitor()
    var trackpadRunning = false

    var eventMonitors: [Any] = []
    var notificationTokens: [NSObjectProtocol] = []
    var cancellables: Set<AnyCancellable> = []
    var reconcileTimer: Timer?
    var saveWork: DispatchWorkItem?

    // Interaction state
    var restoring = false
    var suppressScrollUntil: CFTimeInterval = 0
    var dragging: WinID?
    var swipeKey: StripKey?
    var swipeStartOffset: Double = 0
    var swipeOffset: Double = 0
    var scrollKey: StripKey?
    var scrollSettleWork: DispatchWorkItem?
    var lastMouseMove: CFTimeInterval = 0

    /// Menu bar text, e.g. "2/5".
    var onStatusChange: ((String) -> Void)?

    // MARK: Lifecycle

    func start() {
        displays = Displays.all()
        let ws = NSWorkspace.shared.notificationCenter
        notificationTokens = [
            ws.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.addApp(app) }
            },
            ws.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.removeApp(app.processIdentifier) }
            },
            ws.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
                if let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication { self?.appActivated(app) }
            },
            ws.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.reconcile(animate: false)
            },
            NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                self?.screensChanged()
            },
        ]

        restoring = true
        for app in NSWorkspace.shared.runningApplications { addApp(app) }
        restoring = false
        buildInitialStrips()

        startInputMonitors()
        applyConfig()
        store.$config.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyConfig() }
        }.store(in: &cancellables)
        store.$enabled.dropFirst().receive(on: RunLoop.main).sink { [weak self] on in
            DispatchQueue.main.async { self?.setEnabled(on) }
        }.store(in: &cancellables)

        animator.onStep = { [weak self] in self?.updateDecorations() }
        animator.onSettle = { [weak self] in self?.updateDecorations() }
        tabBars.onSelect = { [weak self] col, i in self?.selectTab(column: col, index: i) }

        // Safety net for events macOS does not report (Mission Control moves, etc.).
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.reconcile(animate: true)
        }
        layoutAll(animate: false)
        syncFocusFromSystem(scroll: true)
    }

    /// Puts every window back on screen so nothing is left parked off an edge.
    func stop() {
        reconcileTimer?.invalidate()
        trackpad.stop()
        animator.cancelAll()
        bringAllOnScreen()
        saveNow()
        border.hide()
        dim.hide()
        tabBars.hideAll()
    }

    func setEnabled(_ on: Bool) {
        if on {
            reconcile(animate: false)
            layoutAll(animate: true)
        } else {
            animator.cancelAll()
            bringAllOnScreen()
            border.hide()
            dim.hide()
            tabBars.hideAll()
            onStatusChange?("")
        }
    }

    func applyConfig() {
        trackpad.fingers = config.swipeFingers
        if config.swipeEnabled && !trackpadRunning {
            trackpadRunning = trackpad.start()
        } else if !config.swipeEnabled && trackpadRunning {
            trackpad.stop()
            trackpadRunning = false
        }
        // Rules win over the automatic choice when they change.
        for mw in windows.values {
            guard let rule = config.rule(for: mw.ax.bundleID) else { continue }
            if rule.action != .tile && !mw.floating {
                mw.floating = true
                removeFromStrips(mw.id)
            } else if rule.action == .tile && mw.floating && mw.ax.isResizable {
                mw.floating = false
            }
        }
        reconcile(animate: false)
        layoutAll(animate: true)
    }

    func bringAllOnScreen() {
        for (key, _) in strips {
            guard let d = display(for: key) else { continue }
            let area = d.visibleFrame
            for id in strips[key]?.allWindows ?? [] {
                guard let mw = windows[id], let f = mw.ax.frame else { continue }
                var r = f
                r.size.width = min(r.width, area.width)
                r.origin.x = min(max(r.minX, area.minX), area.maxX - r.width)
                r.origin.y = min(max(r.minY, area.minY), area.maxY - min(r.height, area.height))
                if r != f { mw.ax.setFrame(r, sizeChanged: r.size != f.size) }
            }
        }
    }

    // MARK: Apps

    func addApp(_ app: NSRunningApplication, attempt: Int = 0) {
        let pid = app.processIdentifier
        guard pid != getpid(), app.activationPolicy == .regular, observers[pid] == nil, !app.isTerminated else { return }
        if let obs = AppObserver(app: app, handler: { [weak self] o, e in self?.handle(o, e) }) {
            observers[pid] = obs
            discoverWindows(pid)
        } else if attempt < 5 {
            // Apps that are still launching are not ready for Accessibility yet.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(attempt + 1)) { [weak self] in
                self?.addApp(app, attempt: attempt + 1)
            }
        }
    }

    func removeApp(_ pid: pid_t) {
        observers[pid]?.stop()
        observers[pid] = nil
        let gone = windows.values.filter { $0.ax.pid == pid }.map { $0.id }
        var touched = Set<StripKey>()
        for id in gone {
            if let k = removeFromStrips(id) { touched.insert(k) }
            windows[id] = nil
        }
        for k in touched { layout(k, animate: true) }
        if let f = focusedID, gone.contains(f) { focusedID = nil }
        updateDecorations()
    }

    func discoverWindows(_ pid: pid_t) {
        let onscreen = Set(onScreenWindowIDs())
        for el in AXApp.windows(of: pid) {
            track(el, pid: pid, focus: false, onscreen: onscreen)
        }
    }

    // MARK: Tracking

    func initialFloating(_ ax: AXWin) -> Bool {
        if let rule = config.rule(for: ax.bundleID) {
            switch rule.action {
            case .float: return true
            case .tile: return false
            case .ignore: return true
            }
        }
        if !ax.isTileable && config.autoFloatDialogs { return true }
        if !ax.isResizable { return true }
        if ax.isModal { return true }
        return false
    }

    @discardableResult
    func track(_ el: AXUIElement, pid: pid_t, focus: Bool, onscreen: Set<WinID>? = nil) -> ManagedWindow? {
        guard let id = AX.windowID(el), !ignored.contains(id) else { return nil }
        if let existing = windows[id] { return existing }
        guard let obs = observers[pid] else { return nil }
        let ax = AXWin(element: el, id: id, pid: pid, bundleID: obs.bundleID, appName: obs.appName)
        let role = ax.role
        guard role == (kAXWindowRole as String) else { return nil }
        let subrole = ax.subrole
        // Popovers, sheets and other non-window chrome.
        if subrole.isEmpty || subrole == "AXUnknown" { return nil }
        if config.rule(for: ax.bundleID)?.action == .ignore {
            ignored.insert(id)
            return nil
        }
        guard let frame = ax.frame else { return nil }
        let mw = ManagedWindow(ax: ax, floating: initialFloating(ax), originalSize: frame.size)
        windows[id] = mw
        obs.watch(el)

        let visible = (onscreen ?? Set(onScreenWindowIDs())).contains(id)
        if !restoring && !mw.floating && visible && !ax.isMinimized && !ax.isFullscreen {
            if let key = adoptTabSwap(mw) {
                layout(key, animate: false)
            } else {
                addToStrip(mw, focus: focus)
            }
        }
        return mw
    }

    /// Native macOS tabs: switching tabs swaps which window is on screen. If a
    /// window of the same app just left the screen at the same spot, the new one
    /// takes over its column instead of opening a new one.
    func adoptTabSwap(_ mw: ManagedWindow, onscreen: Set<WinID>? = nil) -> StripKey? {
        guard let f = mw.ax.frame else { return nil }
        let live = onscreen ?? Set(onScreenWindowIDs())
        for (key, strip) in strips {
            for id in strip.allWindows where id != mw.id && !live.contains(id) {
                guard let other = windows[id], other.ax.pid == mw.ax.pid,
                      let last = other.lastFrame, abs(last.minX - f.minX) < 4, abs(last.minY - f.minY) < 4,
                      !other.ax.isMinimized else { continue }
                strips[key]?.replace(id, with: mw.id)
                mw.lastFrame = last
                if focusedID == id { focusedID = mw.id }
                return key
            }
        }
        return nil
    }

    func forget(_ id: WinID) {
        if let mw = windows[id], let obs = observers[mw.ax.pid] { obs.unwatch(mw.ax.element) }
        let key = removeFromStrips(id)
        windows[id] = nil
        animator.cancel(id)
        if focusedID == id { focusedID = nil }
        if let key { layout(key, animate: true) }
    }

    /// Adds a tiled window to the strip of the display it is on.
    func addToStrip(_ mw: ManagedWindow, focus: Bool, at index: Int? = nil, key forcedKey: StripKey? = nil) {
        guard !mw.floating, let frame = mw.ax.frame else { return }
        let key: StripKey
        if let forcedKey {
            key = forcedKey
        } else {
            guard let d = Displays.containing(frame, in: displays), !config.excludedDisplays.contains(d.uuid) else { return }
            key = StripKey(display: d.uuid, space: d.currentSpace)
        }
        if strips[key]?.contains(mw.id) == true { return }
        let rule = config.rule(for: mw.ax.bundleID)
        var strip = strips[key] ?? Strip()
        strip.insert(mw.id, width: rule?.width ?? config.defaultWidth, position: config.newWindowPosition,
                     slot: index ?? rule?.slot, focus: focus)
        strips[key] = strip
        mw.lastFrame = frame
        if focus {
            focusedID = mw.id
            scrollToFocus(key)
        }
        layout(key, animate: true)
    }

    @discardableResult
    func removeFromStrips(_ id: WinID) -> StripKey? {
        for key in strips.keys where strips[key]!.contains(id) {
            strips[key]!.remove(id)
            if strips[key]!.isEmpty { strips[key] = Strip() }
            return key
        }
        return nil
    }

    func key(of id: WinID) -> StripKey? {
        strips.first { $0.value.contains(id) }?.key
    }

    func display(for key: StripKey) -> Display? {
        displays.first { $0.uuid == key.display }
    }

    func activeKey(for display: Display) -> StripKey {
        StripKey(display: display.uuid, space: display.currentSpace)
    }

    /// Strip to act on: the focused window's, else the one under the mouse.
    func currentKey() -> StripKey? {
        if let f = focusedID, let k = key(of: f), let d = display(for: k), activeKey(for: d) == k { return k }
        guard let d = Displays.containing(point: Displays.mouseLocation, in: displays) else { return nil }
        return activeKey(for: d)
    }

    // MARK: Initial state

    func buildInitialStrips() {
        let onscreen = Set(onScreenWindowIDs())
        let snapshot = config.restoreSession ? store.loadSession() : nil
        var byDisplay: [String: [ManagedWindow]] = [:]
        for mw in windows.values where !mw.floating && onscreen.contains(mw.id) && !mw.ax.isMinimized && !mw.ax.isFullscreen {
            guard let f = mw.ax.frame, let d = Displays.containing(f, in: displays),
                  !config.excludedDisplays.contains(d.uuid) else { continue }
            byDisplay[d.uuid, default: []].append(mw)
        }
        for d in displays {
            // Left-to-right as they currently sit on screen.
            let list = (byDisplay[d.uuid] ?? []).sorted { ($0.ax.frame?.minX ?? 0) < ($1.ax.frame?.minX ?? 0) }
            let ids = list.map { WindowIdentity(windowID: $0.id, bundleID: $0.ax.bundleID, title: $0.ax.title) }
            let key = activeKey(for: d)
            var strip: Strip
            if let snap = snapshot?.strips.first(where: { $0.display == d.uuid }) {
                strip = SessionRestore.rebuild(snap, available: ids, defaultWidth: config.defaultWidth)
            } else {
                strip = Strip()
                for w in list {
                    strip.insert(w.id, width: config.rule(for: w.ax.bundleID)?.width ?? config.defaultWidth,
                                 position: .end, focus: false)
                }
            }
            for mw in list { mw.lastFrame = mw.ax.frame }
            strips[key] = strip
        }
    }

    func screensChanged() {
        let old = Set(displays.map { $0.uuid })
        displays = Displays.all()
        let now = Set(displays.map { $0.uuid })
        // Windows on a display that went away join the main display's strip.
        if let main = displays.first {
            let mainKey = activeKey(for: main)
            for (key, strip) in strips where !now.contains(key.display) && old.contains(key.display) {
                var target = strips[mainKey] ?? Strip()
                for c in strip.columns {
                    target.columns.append(c)
                }
                if let p = strip.pinnedLeft { target.columns.append(p) }
                if let p = strip.pinnedRight { target.columns.append(p) }
                strips[mainKey] = target
                strips[key] = nil
            }
        }
        reconcile(animate: false)
        layoutAll(animate: false)
    }

    // MARK: Reconcile

    /// Brings the strips in line with what is actually on screen.
    func reconcile(animate: Bool) {
        guard store.enabled, swipeKey == nil, dragging == nil else { return }
        displays = Displays.all()
        let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var onscreen = Set<WinID>()
        var unknownPids = Set<pid_t>()
        for info in infos where (info[kCGWindowLayer as String] as? Int) == 0 {
            guard let id = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { continue }
            onscreen.insert(id)
            if windows[id] == nil && !ignored.contains(id),
               let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, observers[pid] != nil {
                unknownPids.insert(pid)
            }
        }
        for pid in unknownPids {
            for el in AXApp.windows(of: pid) { track(el, pid: pid, focus: false, onscreen: onscreen) }
        }

        var touched = Set<StripKey>()
        let activeKeys = Set(displays.map { activeKey(for: $0) })

        // Tab swaps first, so a switched tab keeps its column.
        for mw in windows.values where onscreen.contains(mw.id) && !mw.floating && key(of: mw.id) == nil {
            if let k = adoptTabSwap(mw, onscreen: onscreen) { touched.insert(k) }
        }

        // Drop windows that left the current Space, closed, minimized or hid.
        for key in activeKeys {
            guard let strip = strips[key] else { continue }
            for id in strip.allWindows where !onscreen.contains(id) {
                guard let mw = windows[id] else { strips[key]?.remove(id); touched.insert(key); continue }
                if mw.ax.frame == nil {
                    windows[id] = nil
                    if focusedID == id { focusedID = nil }
                } else if mw.ax.isMinimized || NSRunningApplication(processIdentifier: mw.ax.pid)?.isHidden == true {
                    if case .column(let c, _)? = strip.locate(id) { mw.parkedAt = (key, c) }
                }
                strips[key]?.remove(id)
                touched.insert(key)
            }
        }

        // Adopt on-screen tiled windows that are not on the active strip of their display.
        for mw in windows.values where onscreen.contains(mw.id) && !mw.floating {
            if mw.ax.isFullscreen {
                if let k = removeFromStrips(mw.id) { touched.insert(k) }
                continue
            }
            if let k = key(of: mw.id), activeKeys.contains(k) { continue }
            guard let f = mw.lastFrame ?? mw.ax.frame, let d = Displays.containing(f, in: displays),
                  !config.excludedDisplays.contains(d.uuid) else { continue }
            if let old = removeFromStrips(mw.id) { touched.insert(old) }
            let k = activeKey(for: d)
            var idx: Int?
            if let parked = mw.parkedAt, parked.key == k { idx = parked.column }
            mw.parkedAt = nil
            var strip = strips[k] ?? Strip()
            strip.insert(mw.id, width: config.rule(for: mw.ax.bundleID)?.width ?? config.defaultWidth,
                         position: config.newWindowPosition, slot: idx ?? config.rule(for: mw.ax.bundleID)?.slot, focus: false)
            strips[k] = strip
            touched.insert(k)
        }

        for k in touched where activeKeys.contains(k) { layout(k, animate: animate) }
        if !touched.isEmpty { scheduleSave() }
    }

    // MARK: Persistence

    func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    func saveNow() {
        guard config.restoreSession else { return }
        var snaps: [StripSnapshot] = []
        for d in displays {
            guard let strip = strips[activeKey(for: d)], !strip.isEmpty else { continue }
            snaps.append(SessionRestore.snapshot(strip, display: d.uuid) { [weak self] id in
                guard let mw = self?.windows[id] else { return nil }
                return WindowIdentity(windowID: id, bundleID: mw.ax.bundleID, title: mw.ax.title)
            })
        }
        // Keep snapshots of displays that are not connected right now.
        if let old = store.loadSession() {
            let have = Set(snaps.map { $0.display })
            snaps += old.strips.filter { !have.contains($0.display) && !displays.contains(where: { d in d.uuid == $0.display }) }
        }
        store.saveSession(SessionSnapshot(strips: snaps))
    }
}
