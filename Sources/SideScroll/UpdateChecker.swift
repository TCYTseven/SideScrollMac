import AppKit

/// Checks GitHub Releases for a newer build and installs it with the same
/// script the README uses.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "TCYTseven/SideScrollMac"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repo)/main/install.sh | bash"

    private(set) var latestVersion: String?
    private(set) var latestURL: URL?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var updateAvailable: Bool {
        guard let l = latestVersion else { return false }
        return Self.isNewer(l, than: currentVersion)
    }

    var menuTitle: String {
        updateAvailable ? "Update to \(latestVersion ?? "")…" : "Check for Updates…"
    }

    func checkInBackground() {
        fetch { _ in }
    }

    func checkInteractively() {
        fetch { [weak self] ok in
            guard let self else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            if !ok {
                alert.messageText = "Couldn't check for updates"
                alert.informativeText = "GitHub could not be reached. Try again later."
                alert.runModal()
            } else if self.updateAvailable {
                alert.messageText = "SideScroll \(self.latestVersion ?? "") is available"
                alert.informativeText = "You have \(self.currentVersion). Install now? SideScroll restarts when done."
                alert.addButton(withTitle: "Install Update")
                alert.addButton(withTitle: "Release Notes")
                alert.addButton(withTitle: "Later")
                switch alert.runModal() {
                case .alertFirstButtonReturn: self.install()
                case .alertSecondButtonReturn: if let u = self.latestURL { NSWorkspace.shared.open(u) }
                default: break
                }
            } else {
                alert.messageText = "You're up to date"
                alert.informativeText = "SideScroll \(self.currentVersion) is the latest version."
                alert.runModal()
            }
        }
    }

    private func fetch(_ done: @escaping (Bool) -> Void) {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repo)/releases/latest") else { return }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            var ok = false
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                self?.latestVersion = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                self?.latestURL = (json["html_url"] as? String).flatMap(URL.init(string:))
                ok = true
            }
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    /// Runs the installer in the background; it replaces the app and relaunches it.
    private func install() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", "(\(Self.installCommand)) > /tmp/sidescroll-update.log 2>&1"]
        do { try p.run() } catch {
            let a = NSAlert()
            a.messageText = "Update failed to start"
            a.informativeText = "Run this in Terminal instead:\n\(Self.installCommand)"
            a.runModal()
        }
    }

    static func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
