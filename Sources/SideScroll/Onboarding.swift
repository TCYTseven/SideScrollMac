import AppKit
import SwiftUI
import SideScrollCore

final class OnboardingModel: ObservableObject {
    @Published var trusted = AX.isTrusted(prompt: false)
    @Published var checks: [SetupCheck] = []

    func refresh() {
        trusted = AX.isTrusted(prompt: false)
        checks = MacSetup.checks(config: Store.shared.config)
    }
}

/// Guided start plus Mac Setup: get Accessibility access, learn the five
/// shortcuts, and fix the macOS settings that fight a scrolling window manager.
final class OnboardingWindowController {
    private var window: NSWindow?
    private let model = OnboardingModel()
    private var refreshTimer: Timer?

    static var hasCompletedFirstRun: Bool {
        get { UserDefaults.standard.bool(forKey: "completedFirstRun") }
        set { UserDefaults.standard.set(newValue, forKey: "completedFirstRun") }
    }

    func show() {
        model.refresh()
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "SideScroll Setup"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, close: { [weak self] in
                OnboardingWindowController.hasCompletedFirstRun = true
                self?.window?.close()
            }))
            w.center()
            window = w
        }
        // Keep the checklist current while the window is open (settings change elsewhere).
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] t in
            guard let self, self.window?.isVisible == true else { t.invalidate(); return }
            self.model.refresh()
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func permissionGranted() {
        model.refresh()
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let close: () -> Void

    private struct Lesson: Identifiable {
        let keys: String
        let text: String
        var id: String { keys }
    }

    private let lessons = [
        Lesson(keys: "⌃⌥H  ⌃⌥L", text: "Move focus left and right along the strip (arrows work too)."),
        Lesson(keys: "⌃⌥⇧H  ⌃⌥⇧L", text: "Move the focused column left or right."),
        Lesson(keys: "⌃⌥R", text: "Cycle the window through preset widths."),
        Lesson(keys: "⌃⌥[  ⌃⌥]", text: "Stack the window into the column on its left or right."),
        Lesson(keys: "⌃⌥F", text: "Toggle full width."),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    Image(systemName: "rectangle.split.3x1")
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SideScroll").font(.title.bold())
                        Text("Windows side by side on an endless strip.").foregroundStyle(.secondary)
                    }
                }

                Text("How the strip works").font(.headline)
                Text("Every window gets a column on one long horizontal strip. New windows open to the right and never squeeze the others. Swipe sideways with \(Store.shared.config.swipeFingers) fingers, or use the keyboard, to move along it. Hold ⌃⌥ to see where you are.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(lessons) { lesson in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(lesson.keys).font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(width: 130, alignment: .leading)
                            Text(lesson.text).font(.callout)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))

                HStack {
                    Text("Mac Setup").font(.headline)
                    Spacer()
                    Button("Check Again") { model.refresh() }
                }
                ForEach(model.checks) { check in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: check.status == .ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(check.status == .ok ? .green : .orange)
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(check.title).font(.callout.weight(.semibold))
                            Text(check.detail).font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let title = check.fixTitle, let url = check.fixURL {
                                Button(title) {
                                    if check.id == "ax" { _ = AX.isTrusted(prompt: true) }
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        }
                    }
                }

                HStack {
                    Text(model.trusted ? "SideScroll is running. Find it in the menu bar." : "Waiting for Accessibility access…")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
                .padding(.top, 6)
            }
            .padding(28)
        }
        .frame(width: 600, height: 680)
    }
}
