import AppKit
import SideScrollCore

/// One thing about this Mac that helps or hurts SideScroll.
struct SetupCheck: Identifiable {
    enum Status { case ok, warning }
    let id: String
    let title: String
    let detail: String
    let status: Status
    /// Settings pane or other fix to open.
    let fixTitle: String?
    let fixURL: URL?
}

enum MacSetup {
    /// Other window managers and snapping apps that move windows too.
    static let conflictingApps: [String: String] = [
        "com.knollsoft.Rectangle": "Rectangle",
        "com.knollsoft.Hookshot": "Hookshot",
        "com.crowdcafe.windowmagnet": "Magnet",
        "com.divisiblebyzero.Spectacle": "Spectacle",
        "com.hegenberg.BetterSnapTool": "BetterSnapTool",
        "com.manytricks.Moom": "Moom",
        "com.amethyst.Amethyst": "Amethyst",
        "bobko.aerospace": "AeroSpace",
        "com.mrkai77.Loop": "Loop",
        "co.highlyopinionated.swish": "Swish",
        "com.lwouis.alt-tab-macos.Tiling": "AltTab tiling",
        "org.hammerspoon.Hammerspoon": "Hammerspoon",
        "com.koekeishiya.yabai": "yabai",
        "com.ianyh.Amethyst": "Amethyst",
        "com.sleepingbeast.Divvy": "Divvy",
        "com.lightpillar.WindowTidy": "Window Tidy",
    ]
    static let conflictingProcessNames = ["yabai", "AeroSpace", "Amethyst", "Rectangle", "Magnet", "Hammerspoon"]

    static func runningConflicts() -> [String] {
        var names = Set<String>()
        for app in NSWorkspace.shared.runningApplications {
            if let b = app.bundleIdentifier, let name = conflictingApps[b] { names.insert(name) }
            else if let n = app.localizedName, conflictingProcessNames.contains(n) { names.insert(n) }
        }
        return names.sorted()
    }

    private static func pref(_ key: String, _ domain: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain as CFString)
    }

    private static func intPref(_ key: String, _ domains: [String]) -> Int? {
        for d in domains {
            if let v = pref(key, d) as? Int { return v }
        }
        return nil
    }

    private static func boolPref(_ key: String, _ domain: String) -> Bool? {
        pref(key, domain) as? Bool
    }

    private static let trackpadDomains = ["com.apple.AppleMultitouchTrackpad", "com.apple.driver.AppleBluetoothMultitouch.trackpad"]

    /// macOS's own "swipe between full-screen apps" for the finger count SideScroll uses.
    static func systemSwipeConflicts(fingers: Int) -> Bool {
        let key = fingers == 3 ? "TrackpadThreeFingerHorizSwipeGesture" : "TrackpadFourFingerHorizSwipeGesture"
        // 2 means "swipe between full-screen apps". Four fingers default to on.
        let value = intPref(key, trackpadDomains) ?? (fingers == 4 ? 2 : 0)
        return value == 2
    }

    static func edgeTilingOn() -> Bool {
        guard ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 else { return false }
        let edge = boolPref("EnableTilingByEdgeDrag", "com.apple.WindowManager") ?? true
        let top = boolPref("EnableTopTilingByEdgeDrag", "com.apple.WindowManager") ?? true
        return edge || top
    }

    static func stageManagerOn() -> Bool {
        boolPref("GloballyEnabled", "com.apple.WindowManager") ?? false
    }

    static func checks(config: Config) -> [SetupCheck] {
        var out: [SetupCheck] = []
        let trusted = AX.isTrusted(prompt: false)
        out.append(SetupCheck(
            id: "ax", title: "Accessibility access",
            detail: trusted ? "Granted. SideScroll uses it only to move and resize windows."
                : "Needed to move and resize windows. Turn SideScroll on in the list.",
            status: trusted ? .ok : .warning,
            fixTitle: trusted ? nil : "Open Accessibility Settings",
            fixURL: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")))

        let conflicts = runningConflicts()
        out.append(SetupCheck(
            id: "apps", title: "Other window managers",
            detail: conflicts.isEmpty ? "None running."
                : "\(conflicts.joined(separator: ", ")) also moves windows. Quit it, or turn off its shortcuts and snapping, so the two don't fight.",
            status: conflicts.isEmpty ? .ok : .warning, fixTitle: nil, fixURL: nil))

        if config.swipeEnabled {
            let clash = systemSwipeConflicts(fingers: config.swipeFingers)
            out.append(SetupCheck(
                id: "swipe", title: "Trackpad swipe",
                detail: clash
                    ? "macOS also uses a \(config.swipeFingers)-finger sideways swipe to switch full-screen apps. Turn off \"Swipe between full-screen applications\" in Trackpad → More Gestures, or switch SideScroll to \(config.swipeFingers == 4 ? 3 : 4) fingers."
                    : "\(config.swipeFingers)-finger swipes are free for SideScroll. Switch desktops with ⌃← / ⌃→.",
                status: clash ? .warning : .ok,
                fixTitle: clash ? "Open Trackpad Settings" : nil,
                fixURL: URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")))
        }

        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15 {
            let on = edgeTilingOn()
            out.append(SetupCheck(
                id: "tiling", title: "macOS window tiling",
                detail: on ? "Dragging windows to screen edges makes macOS tile them on its own. Turn off \"Drag windows to screen edges to tile\" and \"Drag windows to menu bar to fill screen\" in Desktop & Dock."
                    : "Off. Good.",
                status: on ? .warning : .ok,
                fixTitle: on ? "Open Desktop & Dock" : nil,
                fixURL: URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")))
        }

        let stage = stageManagerOn()
        out.append(SetupCheck(
            id: "stage", title: "Stage Manager",
            detail: stage ? "Stage Manager rearranges windows too. Turn it off in Control Center or Desktop & Dock." : "Off. Good.",
            status: stage ? .warning : .ok,
            fixTitle: stage ? "Open Desktop & Dock" : nil,
            fixURL: URL(string: "x-apple.systempreferences:com.apple.Desktop-Settings.extension")))
        return out
    }
}
