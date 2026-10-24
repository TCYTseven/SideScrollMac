import AppKit
import SideScrollCore

/// sidescroll:// URLs, used by the command-line tool and Raycast scripts.
///
///   sidescroll://focus-left           any action, by its kebab-case name
///   sidescroll://pause                stop tiling (windows come back on screen)
///   sidescroll://resume               start tiling again
///   sidescroll://settings             open Settings
///
/// Closing windows is never available from a URL, so a link can't destroy work.
enum Automation {
    static func handle(_ url: URL, manager: WindowManager?, openSettings: () -> Void) {
        guard url.scheme?.lowercased() == "sidescroll" else { return }
        // Accept both sidescroll://focus-left and sidescroll:///focus-left or sidescroll://action/focus-left.
        var parts = [url.host ?? ""] + url.pathComponents.filter { $0 != "/" }
        parts = parts.filter { !$0.isEmpty }
        if parts.first == "action" { parts.removeFirst() }
        guard let name = parts.first?.lowercased() else { return }

        switch name {
        case "pause", "disable": Store.shared.enabled = false
        case "resume", "enable": Store.shared.enabled = true
        case "toggle": Store.shared.enabled.toggle()
        case "settings", "preferences": openSettings()
        default:
            guard let action = Action(slug: name), action.allowedFromAutomation else {
                NSLog("SideScroll: unknown or disallowed URL action \(name)")
                return
            }
            manager?.perform(action)
        }
    }

    /// Names printed by `sidescroll --list`.
    static var commandNames: [String] {
        ["pause", "resume", "toggle", "settings"] + Action.allCases.filter { $0.allowedFromAutomation }.map { $0.slug }
    }

    // MARK: Command-line tool

    static var bundledTool: URL? { Bundle.main.url(forResource: "sidescroll", withExtension: nil) }

    static let toolLinkCandidates = ["/usr/local/bin/sidescroll", "/opt/homebrew/bin/sidescroll",
                                     NSHomeDirectory() + "/.local/bin/sidescroll"]

    /// Where the tool is linked right now, if anywhere.
    static var installedToolLink: String? {
        toolLinkCandidates.first { isOurLink($0) }
    }

    static func isOurLink(_ path: String) -> Bool {
        guard let dest = try? FileManager.default.destinationOfSymbolicLink(atPath: path) else { return false }
        return dest.contains("SideScroll.app/")
    }

    /// Links the bundled `sidescroll` script into the first writable bin folder.
    @discardableResult
    static func installTool() -> String? {
        guard let tool = bundledTool else { return nil }
        let fm = FileManager.default
        for path in toolLinkCandidates {
            let dir = (path as NSString).deletingLastPathComponent
            if path.hasPrefix(NSHomeDirectory()) { try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true) }
            guard fm.isWritableFile(atPath: dir) else { continue }
            // Never replace something that isn't ours.
            if fm.fileExists(atPath: path) || (try? fm.destinationOfSymbolicLink(atPath: path)) != nil {
                guard isOurLink(path) else { continue }
                try? fm.removeItem(atPath: path)
            }
            if (try? fm.createSymbolicLink(atPath: path, withDestinationPath: tool.path)) != nil { return path }
        }
        return nil
    }

    static func uninstallTool() {
        for path in toolLinkCandidates where isOurLink(path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

/// Removes SideScroll completely: windows back on screen, login item,
/// settings, command-line tool, Accessibility entry, and the app itself.
enum Uninstaller {
    static func run(stopManager: () -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Uninstall SideScroll?"
        alert.informativeText = "All windows go back on screen, and SideScroll's settings, login item, command-line tool and Accessibility entry are removed. The app moves to the Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        stopManager()
        Store.shared.persistenceDisabled = true
        LoginItem.setEnabled(false)
        Automation.uninstallTool()
        try? FileManager.default.removeItem(at: Store.shared.directory)
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            p.arguments = ["reset", "Accessibility", id]
            try? p.run()
            p.waitUntilExit()
        }
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
