import Foundation

/// What to do with an app's windows.
public enum RuleAction: String, Codable, CaseIterable {
    case tile, float, ignore
}

/// Per-app window rule.
public struct AppRule: Codable, Equatable, Identifiable {
    public var id: UUID
    public var bundleID: String
    public var appName: String
    public var action: RuleAction
    /// Fixed column index on the strip for new windows of this app.
    public var slot: Int?
    /// Width fraction new windows of this app open with.
    public var width: Double?

    public init(bundleID: String, appName: String, action: RuleAction = .float, slot: Int? = nil, width: Double? = nil) {
        self.id = UUID()
        self.bundleID = bundleID
        self.appName = appName
        self.action = action
        self.slot = slot
        self.width = width
    }
}

/// Every user setting. Unknown or missing keys fall back to defaults, so
/// settings files from older versions keep loading.
public struct Config: Codable, Equatable {
    // Layout
    public var gap: Double = 8
    public var outerPadding: Double = 8
    public var widthPresets: [Double] = [0.25, 1.0 / 3.0, 0.5, 2.0 / 3.0, 0.75]
    public var defaultWidth: Double = 0.5
    public var resizeStep: Double = 0.05
    public var centerMode: CenterMode = .never
    public var newWindowPosition: InsertPosition = .afterFocused
    public var keepOriginalHeight: Bool = false
    public var tabBarHeight: Double = 24
    public var respectDock: Bool = true

    // Trackpad and mouse
    public var swipeEnabled: Bool = true
    public var swipeFingers: Int = 4
    public var swipeNatural: Bool = true
    public var swipeSensitivity: Double = 1.0
    public var modifierScroll: Bool = true
    public var focusFollowsMouse: Bool = false
    public var mouseFollowsFocus: Bool = false
    public var dragToReorder: Bool = true

    // Look
    public var animationsEnabled: Bool = true
    public var animationSpeed: Double = 1.0
    public var focusBorder: Bool = false
    public var focusBorderWidth: Double = 3
    public var focusBorderColor: String = "#4C8DFF"
    public var dimUnfocused: Bool = false
    public var dimAmount: Double = 0.25
    public var showPositionInMenuBar: Bool = true
    public var showStripIndicator: Bool = true

    // Behaviour
    public var autoFloatDialogs: Bool = true
    public var restoreSession: Bool = true
    public var preventFocusStealing: Bool = true
    public var rules: [AppRule] = Config.defaultRules
    /// Display UUIDs SideScroll leaves alone.
    public var excludedDisplays: [String] = []

    public init() {}

    public static let defaultRules: [AppRule] = [
        AppRule(bundleID: "com.apple.systempreferences", appName: "System Settings", action: .float),
        AppRule(bundleID: "com.apple.calculator", appName: "Calculator", action: .float),
        AppRule(bundleID: "com.apple.ActivityMonitor", appName: "Activity Monitor", action: .tile),
        AppRule(bundleID: "com.apple.FaceTime", appName: "FaceTime", action: .float),
        AppRule(bundleID: "com.apple.PhotoBooth", appName: "Photo Booth", action: .float),
    ]

    public func rule(for bundleID: String?) -> AppRule? {
        guard let b = bundleID else { return nil }
        return rules.first { $0.bundleID == b }
    }

    enum CodingKeys: String, CodingKey {
        case gap, outerPadding, widthPresets, defaultWidth, resizeStep, centerMode, newWindowPosition,
             keepOriginalHeight, tabBarHeight, respectDock,
             swipeEnabled, swipeFingers, swipeNatural, swipeSensitivity, modifierScroll, focusFollowsMouse, mouseFollowsFocus, dragToReorder,
             animationsEnabled, animationSpeed, focusBorder, focusBorderWidth, focusBorderColor, dimUnfocused, dimAmount,
             showPositionInMenuBar, showStripIndicator,
             autoFloatDialogs, restoreSession, preventFocusStealing, rules, excludedDisplays
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        func v<T: Decodable>(_ k: CodingKeys, _ def: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: k)) ?? def
        }
        gap = v(.gap, d.gap)
        outerPadding = v(.outerPadding, d.outerPadding)
        widthPresets = v(.widthPresets, d.widthPresets)
        defaultWidth = v(.defaultWidth, d.defaultWidth)
        resizeStep = v(.resizeStep, d.resizeStep)
        centerMode = v(.centerMode, d.centerMode)
        newWindowPosition = v(.newWindowPosition, d.newWindowPosition)
        keepOriginalHeight = v(.keepOriginalHeight, d.keepOriginalHeight)
        tabBarHeight = v(.tabBarHeight, d.tabBarHeight)
        respectDock = v(.respectDock, d.respectDock)
        swipeEnabled = v(.swipeEnabled, d.swipeEnabled)
        swipeFingers = v(.swipeFingers, d.swipeFingers)
        swipeNatural = v(.swipeNatural, d.swipeNatural)
        swipeSensitivity = v(.swipeSensitivity, d.swipeSensitivity)
        modifierScroll = v(.modifierScroll, d.modifierScroll)
        focusFollowsMouse = v(.focusFollowsMouse, d.focusFollowsMouse)
        mouseFollowsFocus = v(.mouseFollowsFocus, d.mouseFollowsFocus)
        dragToReorder = v(.dragToReorder, d.dragToReorder)
        animationsEnabled = v(.animationsEnabled, d.animationsEnabled)
        animationSpeed = v(.animationSpeed, d.animationSpeed)
        focusBorder = v(.focusBorder, d.focusBorder)
        focusBorderWidth = v(.focusBorderWidth, d.focusBorderWidth)
        focusBorderColor = v(.focusBorderColor, d.focusBorderColor)
        dimUnfocused = v(.dimUnfocused, d.dimUnfocused)
        dimAmount = v(.dimAmount, d.dimAmount)
        showPositionInMenuBar = v(.showPositionInMenuBar, d.showPositionInMenuBar)
        showStripIndicator = v(.showStripIndicator, d.showStripIndicator)
        autoFloatDialogs = v(.autoFloatDialogs, d.autoFloatDialogs)
        restoreSession = v(.restoreSession, d.restoreSession)
        preventFocusStealing = v(.preventFocusStealing, d.preventFocusStealing)
        rules = v(.rules, d.rules)
        excludedDisplays = v(.excludedDisplays, d.excludedDisplays)
    }
}
