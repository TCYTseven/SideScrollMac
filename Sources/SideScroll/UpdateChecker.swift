import AppKit
import CryptoKit

/// Checks GitHub Releases for a newer build and installs it in place.
/// The download is checked against the SHA-256 digest GitHub publishes for
/// the release asset, and must be a SideScroll bundle, before it replaces
/// the running app. No downloaded script is ever executed.
final class UpdateChecker {
    static let shared = UpdateChecker()
    static let repo = "TCYTseven/SideScrollMac"

    private struct Release {
        let version: String
        let page: URL?
        let zipURL: URL?
        let sha256: String?
    }

    private var latest: Release?
    private var installing = false

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var latestVersion: String? { latest?.version }

    var updateAvailable: Bool {
        guard let l = latest?.version else { return false }
        return Self.isNewer(l, than: currentVersion)
    }

    var menuTitle: String {
        updateAvailable ? "Update to \(latest?.version ?? "")…" : "Check for Updates…"
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
            } else if self.updateAvailable, let r = self.latest {
                alert.messageText = "SideScroll \(r.version) is available"
                alert.informativeText = "You have \(self.currentVersion). Install now? SideScroll restarts when done, and macOS asks for Accessibility access again."
                alert.addButton(withTitle: "Install Update")
                alert.addButton(withTitle: "Release Notes")
                alert.addButton(withTitle: "Later")
                switch alert.runModal() {
                case .alertFirstButtonReturn: self.install(r)
                case .alertSecondButtonReturn: if let u = r.page { NSWorkspace.shared.open(u) }
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
        req.timeoutInterval = 20
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            var ok = false
            if let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let tag = json["tag_name"] as? String {
                let assets = json["assets"] as? [[String: Any]] ?? []
                let zip = assets.first { ($0["name"] as? String) == "SideScroll.zip" }
                var digest = zip?["digest"] as? String
                if let d = digest, d.hasPrefix("sha256:") { digest = String(d.dropFirst(7)) } else { digest = nil }
                let release = Release(
                    version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag,
                    page: (json["html_url"] as? String).flatMap(URL.init(string:)),
                    zipURL: (zip?["browser_download_url"] as? String).flatMap(URL.init(string:)),
                    sha256: digest?.lowercased())
                DispatchQueue.main.async { self?.latest = release }
                ok = true
            }
            DispatchQueue.main.async { done(ok) }
        }.resume()
    }

    // MARK: Install

    private func install(_ r: Release) {
        guard !installing else { return }
        let appURL = Bundle.main.bundleURL
        guard let zipURL = r.zipURL, zipURL.scheme == "https", let expected = r.sha256,
              FileManager.default.isWritableFile(atPath: appURL.deletingLastPathComponent().path) else {
            fail("This update can't be installed automatically. Download it from the release page, or run the installer from the README.", page: r.page)
            return
        }
        installing = true
        URLSession.shared.downloadTask(with: zipURL) { [weak self] tmp, response, error in
            guard let self else { return }
            let result = Result { () throws -> URL in
                guard let tmp, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    throw UpdateError("Download failed: \(error?.localizedDescription ?? "no data")")
                }
                return try self.prepare(zip: tmp, expectedSHA256: expected, near: appURL)
            }
            DispatchQueue.main.async {
                self.installing = false
                switch result {
                case .success(let newApp): self.swapAndRelaunch(newApp: newApp, at: appURL)
                case .failure(let e): self.fail((e as? UpdateError)?.message ?? e.localizedDescription, page: r.page)
                }
            }
        }.resume()
    }

    private struct UpdateError: Error {
        let message: String
        init(_ m: String) { message = m }
    }

    /// Verifies and unpacks the download into a private temporary folder.
    private func prepare(zip: URL, expectedSHA256: String, near appURL: URL) throws -> URL {
        let data = try Data(contentsOf: zip)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == expectedSHA256 else { throw UpdateError("The download didn't match its published checksum, so it was not installed.") }

        let fm = FileManager.default
        let dir = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: appURL, create: true)
        let zipCopy = dir.appendingPathComponent("SideScroll.zip")
        try data.write(to: zipCopy)
        try run("/usr/bin/ditto", ["-x", "-k", zipCopy.path, dir.path])
        let newApp = dir.appendingPathComponent("SideScroll.app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")),
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError("The download wasn't a SideScroll app.")
        }
        try run("/usr/bin/codesign", ["--verify", "--deep", newApp.path])
        return newApp
    }

    private func run(_ tool: String, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw UpdateError("\(tool) failed (\(p.terminationStatus)).") }
    }

    /// A tiny shell helper waits for this process to quit, swaps the bundle
    /// (rolling back on failure) and opens the new one. Paths are passed as
    /// arguments, never spliced into the script.
    private func swapAndRelaunch(newApp: URL, at appURL: URL) {
        let script = """
        pid="$1"; new="$2"; dest="$3"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$dest.old"
        if mv "$dest" "$dest.old" && ditto "$new" "$dest"; then
          rm -rf "$dest.old"
        else
          rm -rf "$dest"; mv "$dest.old" "$dest"
        fi
        xattr -dr com.apple.quarantine "$dest" 2>/dev/null
        tccutil reset Accessibility app.sidescroll.SideScroll >/dev/null 2>&1
        rm -rf "$(dirname "$new")"
        open "$dest"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "sidescroll-update", String(getpid()), newApp.path, appURL.path]
        do {
            try p.run()
            NSApp.terminate(nil)
        } catch {
            fail("The update couldn't start: \(error.localizedDescription)", page: latest?.page)
        }
    }

    private func fail(_ message: String, page: URL?) {
        installing = false
        NSApp.activate(ignoringOtherApps: true)
        let a = NSAlert()
        a.messageText = "Update not installed"
        a.informativeText = message
        if page != nil {
            a.addButton(withTitle: "Open Release Page")
            a.addButton(withTitle: "OK")
        }
        if a.runModal() == .alertFirstButtonReturn, let page { NSWorkspace.shared.open(page) }
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
