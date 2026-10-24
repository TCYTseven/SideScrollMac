import AppKit
import SwiftUI

final class OnboardingModel: ObservableObject {
    @Published var trusted = AX.isTrusted(prompt: false)
}

/// First-run window: get Accessibility access and fix the macOS settings that
/// fight a scrolling window manager.
final class OnboardingWindowController {
    private var window: NSWindow?
    private let model = OnboardingModel()

    func show() {
        model.trusted = AX.isTrusted(prompt: false)
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.title = "Welcome to SideScroll"
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, close: { [weak w] in w?.close() }))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func permissionGranted() {
        model.trusted = true
    }
}

private struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    let close: () -> Void

    var body: some View {
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

            step(1, done: model.trusted, title: "Allow Accessibility access",
                 detail: "SideScroll moves and resizes windows through the Accessibility API. It uses it for nothing else.") {
                Button(model.trusted ? "Granted" : "Open Accessibility Settings") {
                    _ = AX.isTrusted(prompt: true)
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
                }
                .disabled(model.trusted)
            }

            step(2, done: false, title: "Free up the trackpad swipe",
                 detail: "Turn off \"Swipe between full-screen applications\" (Trackpad → More Gestures) or set it to the other finger count. SideScroll swipes with 4 fingers by default. Switch desktops with ⌃← / ⌃→.") {
                Button("Open Trackpad Settings") { open("x-apple.systempreferences:com.apple.Trackpad-Settings.extension") }
            }

            step(3, done: false, title: "Turn off macOS window tiling (macOS 15+)",
                 detail: "In Desktop & Dock, turn off \"Drag windows to screen edges to tile\" and \"Drag windows to menu bar to fill screen\" so they don't fight the strip.") {
                Button("Open Desktop & Dock") { open("x-apple.systempreferences:com.apple.Desktop-Settings.extension") }
            }

            step(4, done: false, title: "Try it",
                 detail: "⌃⌥H / ⌃⌥L (or arrows) move focus. ⌃⌥R cycles widths. ⌃⌥F full width. ⌃⌥[ / ⌃⌥] stack. Swipe with four fingers to scroll the strip. Every shortcut can be changed in Settings.") {
                EmptyView()
            }

            Spacer()
            HStack {
                Text(model.trusted ? "SideScroll is running. Find it in the menu bar." : "Waiting for access…")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560, height: 600)
    }

    @ViewBuilder
    private func step<Accessory: View>(_ n: Int, done: Bool, title: String, detail: String,
                                       @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(done ? Color.green : Color.accentColor.opacity(0.15)).frame(width: 26, height: 26)
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                } else {
                    Text("\(n)").font(.system(size: 13, weight: .semibold))
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                accessory()
            }
        }
    }

    private func open(_ url: String) {
        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
    }
}
