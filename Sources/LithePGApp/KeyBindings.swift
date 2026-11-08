import AppKit
import Foundation
import Observation
import SwiftUI

/// One keyboard shortcut: a key plus modifiers, stored in a form that survives app updates.
public struct KeyShortcut: Codable, Equatable, Hashable, Sendable {
    public enum Modifier: String, Codable, CaseIterable, Sendable {
        // Declaration order is the display order Apple uses: ⌃ ⌥ ⇧ ⌘.
        case control, option, shift, command

        var symbol: String {
            switch self {
            case .control: "⌃"
            case .option: "⌥"
            case .shift: "⇧"
            case .command: "⌘"
            }
        }

        var eventModifier: EventModifiers {
            switch self {
            case .control: .control
            case .option: .option
            case .shift: .shift
            case .command: .command
            }
        }
    }

    /// A single lowercase character, or a named key such as "return", "escape" or "f5".
    public let key: String
    public let modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key.count == 1 ? key.lowercased() : key
        self.modifiers = modifiers
    }

    /// Named keys and the symbols macOS menus show for them.
    static let namedKeys: [String: (symbol: String, equivalent: KeyEquivalent)] = {
        var keys: [String: (String, KeyEquivalent)] = [
            "return": ("↩", .return), "escape": ("⎋", .escape), "delete": ("⌫", .delete),
            "forwarddelete": ("⌦", .deleteForward), "tab": ("⇥", .tab), "space": ("Space", .space),
            "up": ("↑", .upArrow), "down": ("↓", .downArrow), "left": ("←", .leftArrow),
            "right": ("→", .rightArrow), "home": ("↖", .home), "end": ("↘", .end),
            "pageup": ("⇞", .pageUp), "pagedown": ("⇟", .pageDown),
        ]
        for number in 1...12 {
            let scalar = Unicode.Scalar(UInt32(NSF1FunctionKey) + UInt32(number - 1))!
            keys["f\(number)"] = ("F\(number)", KeyEquivalent(Character(scalar)))
        }
        return keys
    }()

    /// How menus and Settings show it, for example "⇧⌘K".
    public var displayString: String {
        let prefix = Modifier.allCases.filter(modifiers.contains).map(\.symbol).joined()
        let keyLabel = Self.namedKeys[key]?.symbol ?? key.uppercased()
        return prefix + keyLabel
    }

    public var keyboardShortcut: KeyboardShortcut? {
        let equivalent: KeyEquivalent
        if let named = Self.namedKeys[key] {
            equivalent = named.equivalent
        } else if let character = key.first, key.count == 1 {
            equivalent = KeyEquivalent(character)
        } else {
            return nil
        }
        let eventModifiers = modifiers.reduce(into: EventModifiers()) { $0.insert($1.eventModifier) }
        return KeyboardShortcut(equivalent, modifiers: eventModifiers)
    }

    /// Reads a key press while recording. Shifted characters are stored unshifted, so ⇧⌘[ is
    /// "[" with shift rather than "{", the way SwiftUI shortcuts expect.
    static func from(event: NSEvent) -> KeyShortcut? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<Modifier> = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if let named = namedKey(forKeyCode: event.keyCode) {
            return KeyShortcut(key: named, modifiers: modifiers)
        }
        guard let character = event.characters(byApplyingModifiers: [])?.first,
            !character.isWhitespace, character.unicodeScalars.allSatisfy({ $0.value < 0xF700 })
        else { return nil }
        return KeyShortcut(key: String(character), modifiers: modifiers)
    }

    private static func namedKey(forKeyCode code: UInt16) -> String? {
        switch code {
        case 36, 76: "return"
        case 53: "escape"
        case 51: "delete"
        case 117: "forwarddelete"
        case 48: "tab"
        case 49: "space"
        case 126: "up"
        case 125: "down"
        case 123: "left"
        case 124: "right"
        case 115: "home"
        case 119: "end"
        case 116: "pageup"
        case 121: "pagedown"
        case 122: "f1"
        case 120: "f2"
        case 99: "f3"
        case 118: "f4"
        case 96: "f5"
        case 97: "f6"
        case 98: "f7"
        case 100: "f8"
        case 101: "f9"
        case 109: "f10"
        case 103: "f11"
        case 111: "f12"
        default: nil
        }
    }
}

/// The commands whose shortcuts can be changed in Settings.
public enum KeyBindingAction: String, CaseIterable, Codable, Identifiable, Sendable {
    case runQuery, cancelQuery, newTab, closeTab, previousTab, nextTab
    case askInEnglish, explain, explainAnalyze, schemaGraph

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .runQuery: "Run query"
        case .cancelQuery: "Cancel running query"
        case .newTab: "New query tab"
        case .closeTab: "Close query tab"
        case .previousTab: "Previous query tab"
        case .nextTab: "Next query tab"
        case .askInEnglish: "Ask in English"
        case .explain: "Explain"
        case .explainAnalyze: "Explain Analyze"
        case .schemaGraph: "Schema graph"
        }
    }

    public var defaultShortcut: KeyShortcut {
        switch self {
        case .runQuery: KeyShortcut(key: "return", modifiers: [.command])
        case .cancelQuery: KeyShortcut(key: ".", modifiers: [.command])
        case .newTab: KeyShortcut(key: "t", modifiers: [.command])
        case .closeTab: KeyShortcut(key: "w", modifiers: [.command])
        case .previousTab: KeyShortcut(key: "[", modifiers: [.command, .shift])
        case .nextTab: KeyShortcut(key: "]", modifiers: [.command, .shift])
        case .askInEnglish: KeyShortcut(key: "k", modifiers: [.command, .shift])
        case .explain: KeyShortcut(key: "e", modifiers: [.command])
        case .explainAnalyze: KeyShortcut(key: "e", modifiers: [.command, .shift])
        case .schemaGraph: KeyShortcut(key: "g", modifiers: [.command, .shift])
        }
    }
}

/// The current shortcut for every command: the default unless the user changed or cleared
/// it. Changes are saved immediately and apply to the toolbar right away.
@Observable
@MainActor
public final class KeyBindings {
    public static let storageKey = "com.lithepg.keyBindings"

    /// A binding the user set, or nil when they cleared it. Absent actions use the default.
    private var overrides: [KeyBindingAction: KeyShortcut?] = [:]
    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
            let stored = try? JSONDecoder().decode([String: KeyShortcut?].self, from: data)
        {
            for (raw, shortcut) in stored {
                guard let action = KeyBindingAction(rawValue: raw) else { continue }
                overrides[action] = .some(shortcut)
            }
        }
    }

    public func shortcut(for action: KeyBindingAction) -> KeyShortcut? {
        if let override = overrides[action] { return override }
        return action.defaultShortcut
    }

    /// For SwiftUI's `.keyboardShortcut`, which takes nil for "no shortcut".
    public func keyboardShortcut(for action: KeyBindingAction) -> KeyboardShortcut? {
        shortcut(for: action)?.keyboardShortcut
    }

    public func isCustomized(_ action: KeyBindingAction) -> Bool {
        shortcut(for: action) != action.defaultShortcut
    }

    public enum Rejection: Error, Equatable, CustomStringConvertible {
        case needsCommandOrControl
        case reserved(String)
        case alreadyUsed(by: KeyBindingAction)

        public var description: String {
            switch self {
            case .needsCommandOrControl:
                "Include ⌘ or ⌃, so the shortcut does not interfere with typing."
            case .reserved(let shortcut):
                "\(shortcut) is used by macOS or text editing."
            case .alreadyUsed(let action):
                "Already used by \(action.title)."
            }
        }
    }

    /// Shortcuts that macOS, the menu bar or text editing already rely on.
    static let reserved: Set<KeyShortcut> = [
        .init(key: "q", modifiers: [.command]), .init(key: "h", modifiers: [.command]),
        .init(key: "h", modifiers: [.command, .option]), .init(key: "m", modifiers: [.command]),
        .init(key: ",", modifiers: [.command]), .init(key: "c", modifiers: [.command]),
        .init(key: "v", modifiers: [.command]), .init(key: "x", modifiers: [.command]),
        .init(key: "a", modifiers: [.command]), .init(key: "z", modifiers: [.command]),
        .init(key: "z", modifiers: [.command, .shift]), .init(key: "`", modifiers: [.command]),
        .init(key: "f", modifiers: [.command]), .init(key: "s", modifiers: [.command]),
        .init(key: "space", modifiers: [.command]), .init(key: "tab", modifiers: [.command]),
    ]

    /// Checks a new shortcut without saving it.
    public func validate(_ shortcut: KeyShortcut, for action: KeyBindingAction) -> Rejection? {
        guard shortcut.modifiers.contains(.command) || shortcut.modifiers.contains(.control) else {
            return .needsCommandOrControl
        }
        if Self.reserved.contains(shortcut) { return .reserved(shortcut.displayString) }
        if let other = KeyBindingAction.allCases.first(where: { $0 != action && self.shortcut(for: $0) == shortcut }) {
            return .alreadyUsed(by: other)
        }
        return nil
    }

    /// Saves a new shortcut, or nil to leave the command without one.
    @discardableResult
    public func set(_ shortcut: KeyShortcut?, for action: KeyBindingAction) -> Rejection? {
        if let shortcut, let rejection = validate(shortcut, for: action) { return rejection }
        if shortcut == action.defaultShortcut {
            overrides[action] = nil
        } else {
            overrides[action] = .some(shortcut)
        }
        persist()
        return nil
    }

    /// Restores the default, unless another command now uses it.
    @discardableResult
    public func reset(_ action: KeyBindingAction) -> Rejection? {
        let original = action.defaultShortcut
        if let other = KeyBindingAction.allCases.first(where: { $0 != action && shortcut(for: $0) == original }) {
            return .alreadyUsed(by: other)
        }
        overrides[action] = nil
        persist()
        return nil
    }

    public func resetAll() {
        overrides.removeAll()
        persist()
    }

    private func persist() {
        guard !overrides.isEmpty else {
            defaults.removeObject(forKey: Self.storageKey)
            return
        }
        let stored = Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }
}
