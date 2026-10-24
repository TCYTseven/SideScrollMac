import AppKit
import Combine
import ServiceManagement
import SideScrollCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store.shared
    private var statusItem: NSStatusItem!
    private var manager: WindowManager?
    private let hotkeys = HotkeyManager()
    private var cancellables: Set<AnyCancellable> = []
    private var permissionTimer: Timer?
    private lazy var settings = SettingsWindowController()
    private lazy var onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        // sidescroll:// links (command-line tool, Raycast).
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURLEvent(_:reply:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))

        if AX.isTrusted(prompt: false) {
            startManaging()
            // First run, or another window manager is fighting us: show Mac Setup.
            if !OnboardingWindowController.hasCompletedFirstRun || !MacSetup.runningConflicts().isEmpty {
                onboarding.show()
            }
        } else {
            onboarding.show()
            // Start on our own as soon as access is granted.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard AX.isTrusted(prompt: false) else { return }
                t.invalidate()
                self?.startManaging()
                self?.onboarding.permissionGranted()
            }
        }

        UpdateChecker.shared.checkInBackground()
        NotificationCenter.default.addObserver(forName: .showMacSetup, object: nil, queue: .main) { [weak self] _ in
            self?.onboarding.show()
        }
        NotificationCenter.default.addObserver(forName: .uninstallRequested, object: nil, queue: .main) { [weak self] _ in
            self?.uninstall()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        manager?.stop()
    }

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let str = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: str) else { return }
        Automation.handle(url, manager: manager) { [weak self] in self?.openSettings() }
    }

    private func startManaging() {
        guard manager == nil else { return }
        let m = WindowManager()
        m.onStatusChange = { [weak self] text in self?.setStatusText(text) }
        manager = m
        m.start()

        hotkeys.onAction = { [weak self] action in self?.manager?.perform(action) }
        hotkeys.register(store.bindings)
        store.$bindings.dropFirst().sink { [weak self] b in
            guard let self, !self.store.recordingShortcut else { return }
            self.hotkeys.register(b)
        }.store(in: &cancellables)
        store.$recordingShortcut.dropFirst().sink { [weak self] recording in
            guard let self else { return }
            if recording { self.hotkeys.unregisterAll() } else { self.hotkeys.register(self.store.bindings) }
        }.store(in: &cancellables)
        store.$enabled.sink { [weak self] on in self?.updateIcon(enabled: on) }.store(in: &cancellables)
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon(enabled: true)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    private func updateIcon(enabled: Bool) {
        guard let button = statusItem?.button else { return }
        let name = enabled ? "rectangle.split.3x1" : "rectangle.split.3x1.fill"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "SideScroll")
        img?.isTemplate = true
        button.image = img
        button.imagePosition = .imageLeading
        button.appearsDisabled = !enabled
    }

    private func setStatusText(_ text: String) {
        guard let button = statusItem?.button else { return }
        button.title = text.isEmpty ? "" : " \(text)"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let trusted = AX.isTrusted(prompt: false)

        if !trusted {
            menu.addItem(item("Grant Accessibility Access…", #selector(showOnboarding)))
            menu.addItem(.separator())
        }

        let toggle = item(store.enabled ? "Pause Tiling" : "Resume Tiling", #selector(toggleEnabled))
        if let combo = store.bindings[.toggleEnabled].first { toggle.title += "  (\(KeyNames.describe(combo)))" }
        toggle.isEnabled = trusted
        menu.addItem(toggle)
        let retile = item("Re-tile All Windows", #selector(retile))
        retile.isEnabled = trusted && store.enabled
        menu.addItem(retile)
        menu.addItem(.separator())

        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Keyboard Shortcuts…", #selector(openShortcuts)))
        menu.addItem(item("Mac Setup & Guide…", #selector(showOnboarding)))
        menu.addItem(.separator())

        let login = item("Launch at Login", #selector(toggleLoginItem))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        let update = item(UpdateChecker.shared.menuTitle, #selector(checkForUpdates))
        menu.addItem(update)
        menu.addItem(item("About SideScroll", #selector(about)))
        menu.addItem(.separator())
        menu.addItem(item("Uninstall SideScroll…", #selector(uninstall)))
        menu.addItem(item("Quit SideScroll", #selector(quit), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleEnabled() { store.enabled.toggle() }
    @objc private func retile() { manager?.perform(.retile) }
    @objc func openSettings() { settings.show(tab: .general) }
    @objc private func uninstall() {
        Uninstaller.run { [weak self] in
            self?.manager?.stop()
            self?.manager = nil
        }
    }
    @objc private func openShortcuts() { settings.show(tab: .shortcuts) }
    @objc private func showOnboarding() { onboarding.show() }
    @objc private func toggleLoginItem() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc private func checkForUpdates() { UpdateChecker.shared.checkInteractively() }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .credits: NSAttributedString(string: "A scrolling window manager for macOS.\nWindows sit side by side on an endless strip."),
        ])
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("SideScroll: login item change failed: \(error)")
        }
    }
}
