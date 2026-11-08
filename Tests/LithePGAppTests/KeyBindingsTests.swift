import Foundation
import SwiftUI
import Testing

@testable import LithePGAppUI

@MainActor
@Suite("Key bindings")
struct KeyBindingsTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "lithepg.keybindings.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test("defaults match the shortcuts documented in the README")
    func defaults() {
        let bindings = KeyBindings(defaults: freshDefaults())
        let shown = KeyBindingAction.allCases.map { bindings.shortcut(for: $0)?.displayString }
        #expect(shown == ["⌘↩", "⌘.", "⌘T", "⌘W", "⇧⌘[", "⇧⌘]", "⇧⌘K", "⌘E", "⇧⌘E", "⇧⌘G"])
        #expect(KeyBindingAction.allCases.allSatisfy { bindings.keyboardShortcut(for: $0) != nil })
    }

    @Test("display follows Apple's modifier order and names special keys")
    func displayStrings() {
        #expect(KeyShortcut(key: "R", modifiers: [.command, .option, .control, .shift]).displayString == "⌃⌥⇧⌘R")
        #expect(KeyShortcut(key: "f5", modifiers: [.control]).displayString == "⌃F5")
        #expect(KeyShortcut(key: "space", modifiers: [.control]).displayString == "⌃Space")
        #expect(KeyShortcut(key: "f5", modifiers: [.control]).keyboardShortcut != nil)
    }

    @Test("changes are saved, survive a relaunch and can be reset")
    func persistence() {
        let defaults = freshDefaults()
        let bindings = KeyBindings(defaults: defaults)
        let run = KeyShortcut(key: "r", modifiers: [.command])
        #expect(bindings.set(run, for: .runQuery) == nil)
        #expect(bindings.set(nil, for: .schemaGraph) == nil)

        let relaunched = KeyBindings(defaults: defaults)
        #expect(relaunched.shortcut(for: .runQuery) == run)
        #expect(relaunched.shortcut(for: .schemaGraph) == nil)
        #expect(relaunched.keyboardShortcut(for: .schemaGraph) == nil)
        #expect(relaunched.isCustomized(.runQuery))
        #expect(!relaunched.isCustomized(.newTab))

        #expect(relaunched.reset(.runQuery) == nil)
        relaunched.resetAll()
        #expect(KeyBindings(defaults: defaults).shortcut(for: .schemaGraph)?.displayString == "⇧⌘G")
        #expect(defaults.data(forKey: KeyBindings.storageKey) == nil)
    }

    @Test("unsafe or duplicate shortcuts are refused with a reason")
    func rejections() {
        let bindings = KeyBindings(defaults: freshDefaults())
        #expect(bindings.set(KeyShortcut(key: "r", modifiers: [.shift]), for: .runQuery) == .needsCommandOrControl)
        #expect(bindings.set(KeyShortcut(key: "c", modifiers: [.command]), for: .runQuery) == .reserved("⌘C"))
        #expect(bindings.set(KeyShortcut(key: "t", modifiers: [.command]), for: .runQuery) == .alreadyUsed(by: .newTab))
        #expect(bindings.shortcut(for: .runQuery)?.displayString == "⌘↩")
        // Re-assigning a command its own shortcut is not a conflict.
        #expect(bindings.set(KeyShortcut(key: "return", modifiers: [.command]), for: .runQuery) == nil)

        // A default that another command took cannot be restored until that is changed.
        bindings.set(nil, for: .explain)
        #expect(bindings.set(KeyShortcut(key: "e", modifiers: [.command]), for: .schemaGraph) == nil)
        #expect(bindings.reset(.explain) == .alreadyUsed(by: .schemaGraph))
    }

    @Test("an unreadable saved value falls back to the defaults")
    func corruptStorage() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: KeyBindings.storageKey)
        #expect(KeyBindings(defaults: defaults).shortcut(for: .runQuery)?.displayString == "⌘↩")
    }
}
