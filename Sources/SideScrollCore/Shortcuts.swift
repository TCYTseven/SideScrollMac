import Foundation

/// Everything a shortcut can trigger.
public enum Action: String, Codable, CaseIterable, Identifiable {
    case focusLeft, focusRight, focusUp, focusDown
    case moveLeft, moveRight, moveUp, moveDown
    case focusFirst, focusLast
    case focusColumn1, focusColumn2, focusColumn3, focusColumn4, focusColumn5,
         focusColumn6, focusColumn7, focusColumn8, focusColumn9
    case moveToColumn1, moveToColumn2, moveToColumn3, moveToColumn4, moveToColumn5,
         moveToColumn6, moveToColumn7, moveToColumn8, moveToColumn9
    case cycleWidth, cycleWidthBack, wider, narrower, fullWidth, center
    case taller, shorter, resetHeights
    case stackLeft, stackRight, popLeft, popRight, toggleTabbed
    case toggleFloat, pinLeft, pinRight
    case focusNextDisplay, moveToNextDisplay
    case retile, toggleEnabled, closeWindow

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .focusLeft: return "Focus column left"
        case .focusRight: return "Focus column right"
        case .focusUp: return "Focus window up"
        case .focusDown: return "Focus window down"
        case .moveLeft: return "Move column left"
        case .moveRight: return "Move column right"
        case .moveUp: return "Move window up in stack"
        case .moveDown: return "Move window down in stack"
        case .focusFirst: return "Focus first column"
        case .focusLast: return "Focus last column"
        case .cycleWidth: return "Cycle width presets"
        case .cycleWidthBack: return "Cycle width presets backwards"
        case .wider: return "Make wider"
        case .narrower: return "Make narrower"
        case .fullWidth: return "Toggle full width"
        case .center: return "Center column"
        case .taller: return "Make window taller"
        case .shorter: return "Make window shorter"
        case .resetHeights: return "Reset heights in stack"
        case .stackLeft: return "Stack into left column"
        case .stackRight: return "Stack into right column"
        case .popLeft: return "Pop out to the left"
        case .popRight: return "Pop out to the right"
        case .toggleTabbed: return "Toggle tabbed column"
        case .toggleFloat: return "Float / unfloat window"
        case .pinLeft: return "Pin to left edge"
        case .pinRight: return "Pin to right edge"
        case .focusNextDisplay: return "Focus next display"
        case .moveToNextDisplay: return "Move window to next display"
        case .retile: return "Re-tile all windows"
        case .toggleEnabled: return "Pause / resume tiling"
        case .closeWindow: return "Close window"
        default:
            if let n = columnNumber {
                return rawValue.hasPrefix("move") ? "Move column to position \(n)" : "Focus column \(n)"
            }
            return rawValue
        }
    }

    /// 1...9 for the numbered actions.
    public var columnNumber: Int? {
        guard let last = rawValue.last, let n = Int(String(last)),
              rawValue.hasPrefix("focusColumn") || rawValue.hasPrefix("moveToColumn") else { return nil }
        return n
    }

    public var group: String {
        switch self {
        case .focusLeft, .focusRight, .focusUp, .focusDown, .focusFirst, .focusLast: return "Navigate"
        case .moveLeft, .moveRight, .moveUp, .moveDown: return "Move"
        case .cycleWidth, .cycleWidthBack, .wider, .narrower, .fullWidth, .center,
             .taller, .shorter, .resetHeights: return "Size"
        case .stackLeft, .stackRight, .popLeft, .popRight, .toggleTabbed: return "Stacks & tabs"
        case .toggleFloat, .pinLeft, .pinRight: return "Float & pin"
        case .focusNextDisplay, .moveToNextDisplay: return "Displays"
        case .retile, .toggleEnabled, .closeWindow: return "Other"
        default: return columnNumber != nil ? "Jump to column" : "Other"
        }
    }

    public static let groups = ["Navigate", "Move", "Size", "Stacks & tabs", "Float & pin", "Jump to column", "Displays", "Other"]
}

/// Carbon modifier masks, so key combos can be registered with RegisterEventHotKey.
public enum Mod {
    public static let cmd: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000
}

/// A physical key plus modifiers. Stored by key code, so it works the same on
/// any keyboard layout.
public struct KeyCombo: Codable, Hashable {
    public var keyCode: UInt32
    public var modifiers: UInt32

    public init(_ keyCode: UInt32, _ modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var modifierSymbols: String {
        var s = ""
        if modifiers & Mod.control != 0 { s += "⌃" }
        if modifiers & Mod.option != 0 { s += "⌥" }
        if modifiers & Mod.shift != 0 { s += "⇧" }
        if modifiers & Mod.cmd != 0 { s += "⌘" }
        return s
    }
}

/// Virtual key codes (kVK_*) used by the defaults.
public enum Key {
    public static let a: UInt32 = 0x00, d: UInt32 = 0x02, f: UInt32 = 0x03, h: UInt32 = 0x04
    public static let c: UInt32 = 0x08, q: UInt32 = 0x0C, w: UInt32 = 0x0D, r: UInt32 = 0x0F, t: UInt32 = 0x11
    public static let one: UInt32 = 0x12, two: UInt32 = 0x13, three: UInt32 = 0x14, four: UInt32 = 0x15
    public static let six: UInt32 = 0x16, five: UInt32 = 0x17, equal: UInt32 = 0x18, nine: UInt32 = 0x19
    public static let seven: UInt32 = 0x1A, minus: UInt32 = 0x1B, eight: UInt32 = 0x1C, zero: UInt32 = 0x1D
    public static let rightBracket: UInt32 = 0x1E, leftBracket: UInt32 = 0x21, p: UInt32 = 0x23
    public static let l: UInt32 = 0x25, j: UInt32 = 0x26, k: UInt32 = 0x28, m: UInt32 = 0x2E
    public static let home: UInt32 = 0x73, end: UInt32 = 0x77
    public static let left: UInt32 = 0x7B, right: UInt32 = 0x7C, down: UInt32 = 0x7D, up: UInt32 = 0x7E
    public static let digits: [UInt32] = [one, two, three, four, five, six, seven, eight, nine]
}

/// Action -> list of combos. One action can have several bindings.
public struct Bindings: Codable, Equatable {
    public var map: [String: [KeyCombo]]

    public init(map: [String: [KeyCombo]] = [:]) { self.map = map }

    public subscript(_ a: Action) -> [KeyCombo] {
        get { map[a.rawValue] ?? [] }
        set { map[a.rawValue] = newValue }
    }

    public func action(for combo: KeyCombo) -> Action? {
        for a in Action.allCases where self[a].contains(combo) { return a }
        return nil
    }

    public static var defaults: Bindings {
        let co = Mod.control | Mod.option
        let cos = co | Mod.shift
        var b = Bindings()
        b[.focusLeft] = [KeyCombo(Key.h, co), KeyCombo(Key.left, co)]
        b[.focusRight] = [KeyCombo(Key.l, co), KeyCombo(Key.right, co)]
        b[.focusDown] = [KeyCombo(Key.j, co), KeyCombo(Key.down, co)]
        b[.focusUp] = [KeyCombo(Key.k, co), KeyCombo(Key.up, co)]
        b[.moveLeft] = [KeyCombo(Key.h, cos), KeyCombo(Key.left, cos)]
        b[.moveRight] = [KeyCombo(Key.l, cos), KeyCombo(Key.right, cos)]
        b[.moveDown] = [KeyCombo(Key.j, cos), KeyCombo(Key.down, cos)]
        b[.moveUp] = [KeyCombo(Key.k, cos), KeyCombo(Key.up, cos)]
        b[.focusFirst] = [KeyCombo(Key.home, co)]
        b[.focusLast] = [KeyCombo(Key.end, co)]
        for (i, key) in Key.digits.enumerated() {
            b.map["focusColumn\(i + 1)"] = [KeyCombo(key, co)]
            b.map["moveToColumn\(i + 1)"] = [KeyCombo(key, cos)]
        }
        b[.cycleWidth] = [KeyCombo(Key.r, co)]
        b[.cycleWidthBack] = []
        b[.wider] = [KeyCombo(Key.equal, co)]
        b[.narrower] = [KeyCombo(Key.minus, co)]
        b[.fullWidth] = [KeyCombo(Key.f, co)]
        b[.center] = [KeyCombo(Key.c, co)]
        b[.taller] = [KeyCombo(Key.equal, cos)]
        b[.shorter] = [KeyCombo(Key.minus, cos)]
        b[.resetHeights] = [KeyCombo(Key.r, cos)]
        b[.stackLeft] = [KeyCombo(Key.leftBracket, co)]
        b[.stackRight] = [KeyCombo(Key.rightBracket, co)]
        b[.popLeft] = [KeyCombo(Key.leftBracket, cos)]
        b[.popRight] = [KeyCombo(Key.rightBracket, cos)]
        b[.toggleTabbed] = [KeyCombo(Key.t, cos)]
        b[.toggleFloat] = [KeyCombo(Key.t, co)]
        b[.pinLeft] = [KeyCombo(Key.p, co)]
        b[.pinRight] = [KeyCombo(Key.p, cos)]
        b[.focusNextDisplay] = [KeyCombo(Key.d, co)]
        b[.moveToNextDisplay] = [KeyCombo(Key.d, cos)]
        b[.retile] = [KeyCombo(Key.zero, cos)]
        b[.toggleEnabled] = []
        b[.closeWindow] = []
        return b
    }

    /// Fills in actions the stored set has never seen, using the default combo
    /// only where that combo is still free. Existing bindings are never touched.
    public func mergedWithDefaults() -> Bindings {
        var out = self
        let used = Set(map.values.flatMap { $0 })
        for a in Action.allCases where map[a.rawValue] == nil {
            out[a] = Bindings.defaults[a].filter { !used.contains($0) }
        }
        return out
    }

    /// Other actions already using `combo`.
    public func conflicts(_ combo: KeyCombo, excluding: Action) -> [Action] {
        Action.allCases.filter { $0 != excluding && self[$0].contains(combo) }
    }
}
