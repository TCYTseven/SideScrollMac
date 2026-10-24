import AppKit
import Combine
import SideScrollCore

/// Loads and saves settings, shortcuts and the session as JSON in
/// ~/Library/Application Support/SideScroll.
final class Store: ObservableObject {
    static let shared = Store()

    @Published var config: Config { didSet { if config != oldValue { save(config, "config.json") } } }
    @Published var bindings: Bindings { didSet { if bindings != oldValue { save(bindings, "shortcuts.json") } } }
    @Published var enabled = true
    /// True while the shortcut recorder is listening, so hotkeys do not fire.
    @Published var recordingShortcut = false

    let directory: URL
    /// Set while uninstalling so nothing gets written back.
    var persistenceDisabled = false

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        directory = base.appendingPathComponent("SideScroll", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        config = Store.load(Config.self, "config.json", in: directory) ?? Config()
        if let stored = Store.load(Bindings.self, "shortcuts.json", in: directory) {
            bindings = stored.mergedWithDefaults()
        } else {
            bindings = .defaults
        }
    }

    func loadSession() -> SessionSnapshot? { Store.load(SessionSnapshot.self, "session.json", in: directory) }
    func saveSession(_ s: SessionSnapshot) { save(s, "session.json") }

    func resetShortcuts() { bindings = .defaults }

    private static func load<T: Decodable>(_ type: T.Type, _ name: String, in dir: URL) -> T? {
        guard let data = try? Data(contentsOf: dir.appendingPathComponent(name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard !persistenceDisabled else { return }
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(value) else { return }
        try? data.write(to: directory.appendingPathComponent(name), options: .atomic)
    }
}
