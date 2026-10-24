import AppKit
import SwiftUI
import SideScrollCore

enum SettingsTab: String, CaseIterable, Identifiable {
    case general, layout, trackpad, appearance, shortcuts, rules, displays
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .layout: return "Layout"
        case .trackpad: return "Trackpad & Mouse"
        case .appearance: return "Appearance"
        case .shortcuts: return "Shortcuts"
        case .rules: return "Window Rules"
        case .displays: return "Displays"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .layout: return "rectangle.split.3x1"
        case .trackpad: return "hand.draw"
        case .appearance: return "paintbrush"
        case .shortcuts: return "keyboard"
        case .rules: return "list.bullet.rectangle"
        case .displays: return "display.2"
        }
    }
}

final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

final class SettingsWindowController {
    private var window: NSWindow?
    private let selection = SettingsSelection()

    func show(tab: SettingsTab) {
        selection.tab = tab
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "SideScroll Settings"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(store: .shared, selection: selection))
            w.setContentSize(NSSize(width: 760, height: 560))
            w.minSize = NSSize(width: 680, height: 460)
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsTab.allCases, selection: Binding(get: { Optional(selection.tab) },
                                                          set: { if let t = $0 { selection.tab = t } })) { tab in
                Label(tab.title, systemImage: tab.icon).tag(tab)
            }
            .listStyle(.sidebar)
            .frame(width: 190)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(selection.tab.title).font(.title2.bold())
                    content
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch selection.tab {
        case .general: GeneralPane(store: store)
        case .layout: LayoutPane(store: store)
        case .trackpad: TrackpadPane(store: store)
        case .appearance: AppearancePane(store: store)
        case .shortcuts: ShortcutsPane(store: store)
        case .rules: RulesPane(store: store)
        case .displays: DisplaysPane(store: store)
        }
    }
}

// MARK: - Panes

private struct Section<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor)))
        }
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(Int($0)) }

    var body: some View {
        HStack {
            Text(title).frame(width: 170, alignment: .leading)
            Slider(value: $value, in: range, step: step)
            Text(format(value)).monospacedDigit().frame(width: 56, alignment: .trailing)
        }
    }
}

private func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

private struct GeneralPane: View {
    @ObservedObject var store: Store
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Section(title: "SideScroll") {
            Toggle("Tiling enabled", isOn: $store.enabled)
            Toggle("Launch at login", isOn: Binding(get: { launchAtLogin }, set: {
                LoginItem.setEnabled($0)
                launchAtLogin = LoginItem.isEnabled
            }))
            Toggle("Restore column order after restart", isOn: $store.config.restoreSession)
            Toggle("Show column position in the menu bar", isOn: $store.config.showPositionInMenuBar)
        }
        Section(title: "New windows") {
            Picker("Open new windows", selection: $store.config.newWindowPosition) {
                Text("Right of the focused column").tag(InsertPosition.afterFocused)
                Text("At the end of the strip").tag(InsertPosition.end)
            }
            Toggle("Don't let background apps steal focus", isOn: $store.config.preventFocusStealing)
            Toggle("Float dialogs, previews and fixed-size windows", isOn: $store.config.autoFloatDialogs)
        }
        Section(title: "About") {
            HStack {
                Text("Version \(UpdateChecker.shared.currentVersion)")
                Spacer()
                Button("Check for Updates…") { UpdateChecker.shared.checkInteractively() }
            }
            Text("Settings live in \(store.directory.path)").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
}

private struct LayoutPane: View {
    @ObservedObject var store: Store
    @State private var newPreset = 0.5

    var body: some View {
        Section(title: "Spacing") {
            SliderRow(title: "Gap between windows", value: $store.config.gap, range: 0...48)
            SliderRow(title: "Padding at screen edges", value: $store.config.outerPadding, range: 0...48)
            Toggle("Size windows around the Dock", isOn: $store.config.respectDock)
        }
        Section(title: "Width") {
            SliderRow(title: "Default width", value: $store.config.defaultWidth, range: 0.2...1, step: 0.05, format: percent)
            SliderRow(title: "Wider / narrower step", value: $store.config.resizeStep, range: 0.01...0.25, step: 0.01, format: percent)
            Text("Width presets (⌃⌥R cycles through them)").font(.subheadline)
            HStack {
                ForEach(Array(store.config.widthPresets.sorted().enumerated()), id: \.offset) { _, p in
                    HStack(spacing: 4) {
                        Text(percent(p)).monospacedDigit()
                        Button {
                            store.config.widthPresets.removeAll { abs($0 - p) < 0.001 }
                        } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                }
            }
            HStack {
                Slider(value: $newPreset, in: 0.1...1, step: 0.01).frame(width: 200)
                Text(percent(newPreset)).monospacedDigit().frame(width: 44)
                Button("Add preset") {
                    if !store.config.widthPresets.contains(where: { abs($0 - newPreset) < 0.005 }) {
                        store.config.widthPresets.append(newPreset)
                    }
                }
                Button("Reset") { store.config.widthPresets = Config().widthPresets }
            }
        }
        Section(title: "Scrolling") {
            Picker("Bring focused column into view", selection: $store.config.centerMode) {
                Text("Scroll just enough").tag(CenterMode.never)
                Text("Center it when it doesn't fit").tag(CenterMode.onOverflow)
                Text("Always center it").tag(CenterMode.always)
            }
        }
        Section(title: "Height") {
            Toggle("Keep each window's original height (top aligned)", isOn: $store.config.keepOriginalHeight)
            SliderRow(title: "Tab bar height", value: $store.config.tabBarHeight, range: 18...36)
        }
    }
}

private struct TrackpadPane: View {
    @ObservedObject var store: Store

    var body: some View {
        Section(title: "Swipe") {
            Toggle("Scroll the strip with a trackpad swipe", isOn: $store.config.swipeEnabled)
            Picker("Fingers", selection: $store.config.swipeFingers) {
                Text("3 fingers").tag(3)
                Text("4 fingers").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 260)
            Toggle("Natural direction (content follows fingers)", isOn: $store.config.swipeNatural)
            SliderRow(title: "Sensitivity", value: $store.config.swipeSensitivity, range: 0.3...3, step: 0.1,
                      format: { String(format: "%.1f×", $0) })
            Text("Turn off macOS's own swipe for the same finger count in System Settings → Trackpad → More Gestures, or the two will fight.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Open Trackpad Settings") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Trackpad-Settings.extension")!)
            }
        }
        Section(title: "Mouse") {
            Toggle("Hold ⌃⌥ and scroll to move along the strip", isOn: $store.config.modifierScroll)
            Toggle("Focus follows mouse", isOn: $store.config.focusFollowsMouse)
            Toggle("Drag a window onto another column to reorder", isOn: $store.config.dragToReorder)
        }
    }
}

private struct AppearancePane: View {
    @ObservedObject var store: Store

    var body: some View {
        Section(title: "Animation") {
            Toggle("Animate windows", isOn: $store.config.animationsEnabled)
            SliderRow(title: "Speed", value: $store.config.animationSpeed, range: 0.5...3, step: 0.1,
                      format: { String(format: "%.1f×", $0) })
        }
        Section(title: "Focus border") {
            Toggle("Draw a border around the focused window", isOn: $store.config.focusBorder)
            SliderRow(title: "Width", value: $store.config.focusBorderWidth, range: 1...10)
            ColorPicker("Color", selection: Binding(
                get: { Color(nsColor: NSColor(hex: store.config.focusBorderColor) ?? .systemBlue) },
                set: { store.config.focusBorderColor = NSColor($0).hexString }), supportsOpacity: false)
        }
        Section(title: "Dim") {
            Toggle("Dim everything except the focused window", isOn: $store.config.dimUnfocused)
            SliderRow(title: "Amount", value: $store.config.dimAmount, range: 0.05...0.7, step: 0.05, format: percent)
        }
    }
}

private struct ShortcutsPane: View {
    @ObservedObject var store: Store
    @State private var conflict: String?

    var body: some View {
        HStack {
            Text("Click + to record. One action can have several shortcuts. Keys are stored by position, so they work on any layout.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
            Button("Restore Defaults") { store.resetShortcuts() }
        }
        if let conflict {
            Text(conflict).font(.callout).foregroundColor(.orange)
        }
        ForEach(Action.groups, id: \.self) { group in
            Section(title: group) {
                ForEach(Action.allCases.filter { $0.group == group }) { action in
                    row(action)
                }
            }
        }
    }

    private func row(_ action: Action) -> some View {
        HStack {
            Text(action.title).frame(width: 230, alignment: .leading)
            ForEach(store.bindings[action], id: \.self) { combo in
                HStack(spacing: 3) {
                    Text(KeyNames.describe(combo)).font(.system(.body, design: .rounded)).monospacedDigit()
                    Button {
                        store.bindings[action].removeAll { $0 == combo }
                    } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(0.13)))
            }
            Spacer()
            ShortcutRecorder { combo in
                let others = store.bindings.conflicts(combo, excluding: action)
                for o in others { store.bindings[o].removeAll { $0 == combo } }
                if !store.bindings[action].contains(combo) { store.bindings[action].append(combo) }
                conflict = others.isEmpty ? nil
                    : "\(KeyNames.describe(combo)) was moved from \"\(others.map { $0.title }.joined(separator: ", "))\"."
            }
            .frame(width: 120, height: 22)
        }
    }
}

private struct RulesPane: View {
    @ObservedObject var store: Store

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    var body: some View {
        Text("Float apps that shouldn't tile, ignore them completely, or give an app a fixed slot and width on the strip.")
            .font(.callout).foregroundStyle(.secondary)
        HStack {
            Menu("Add App") {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    Button(app.localizedName ?? app.bundleIdentifier!) {
                        guard let b = app.bundleIdentifier, store.config.rule(for: b) == nil else { return }
                        store.config.rules.append(AppRule(bundleID: b, appName: app.localizedName ?? b))
                    }
                }
            }
            .frame(width: 140)
            Spacer()
        }
        ForEach($store.config.rules) { $rule in
            Section(title: rule.appName) {
                Text(rule.bundleID).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Picker("Windows", selection: $rule.action) {
                        Text("Tile").tag(RuleAction.tile)
                        Text("Float").tag(RuleAction.float)
                        Text("Ignore").tag(RuleAction.ignore)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                    Spacer()
                    Button(role: .destructive) {
                        store.config.rules.removeAll { $0.id == rule.id }
                    } label: { Image(systemName: "trash") }
                }
                if rule.action == .tile {
                    HStack {
                        Toggle("Fixed slot", isOn: Binding(get: { rule.slot != nil },
                                                           set: { rule.slot = $0 ? 0 : nil }))
                        if let slot = rule.slot {
                            Stepper("Column \(slot + 1)", value: Binding(get: { slot }, set: { rule.slot = max(0, $0) }), in: 0...20)
                        }
                        Spacer()
                        Toggle("Width", isOn: Binding(get: { rule.width != nil },
                                                      set: { rule.width = $0 ? 0.5 : nil }))
                        if let w = rule.width {
                            Slider(value: Binding(get: { w }, set: { rule.width = $0 }), in: 0.1...1, step: 0.05).frame(width: 120)
                            Text(percent(w)).monospacedDigit().frame(width: 40)
                        }
                    }
                }
            }
        }
    }
}

private struct DisplaysPane: View {
    @ObservedObject var store: Store

    var body: some View {
        Text("Each display has its own strip, with its own focus and scroll position.")
            .font(.callout).foregroundStyle(.secondary)
        Section(title: "Managed displays") {
            ForEach(Displays.all(), id: \.uuid) { d in
                Toggle(isOn: Binding(
                    get: { !store.config.excludedDisplays.contains(d.uuid) },
                    set: { on in
                        store.config.excludedDisplays.removeAll { $0 == d.uuid }
                        if !on { store.config.excludedDisplays.append(d.uuid) }
                    })) {
                    VStack(alignment: .leading) {
                        Text(d.name)
                        Text("\(Int(d.frame.width))×\(Int(d.frame.height))").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        Text("Tip: placing a second display above or below the main one keeps scrolled-away windows from peeking onto it. Side by side works too; windows snap flush to the shared edge.")
            .font(.caption).foregroundStyle(.secondary)
    }
}
