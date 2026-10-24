import AppKit
import ServiceManagement
import SideScrollCore

// Command-line flags, used by the `sidescroll` tool and uninstall.sh.
let args = CommandLine.arguments.dropFirst()
if args.contains("--list-actions") {
    for name in Automation.commandNames { print(name) }
    exit(0)
}
if args.contains("--unregister-login-item") {
    try? SMAppService.mainApp.unregister()
    exit(0)
}

// Only one copy may manage windows at a time.
let bundleID = Bundle.main.bundleIdentifier ?? "app.sidescroll.SideScroll"
let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
    .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
if !others.isEmpty {
    others.first?.activate(options: [])
    exit(0)
}

// `kill` / `pkill` send SIGTERM, which would skip applicationWillTerminate and
// leave scrolled-away windows parked off screen. Turn it into a normal quit.
signal(SIGTERM, SIG_IGN)
let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
termSource.setEventHandler { NSApp.terminate(nil) }
termSource.resume()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
