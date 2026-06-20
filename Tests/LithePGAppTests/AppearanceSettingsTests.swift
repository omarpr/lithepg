import Foundation
import SwiftUI
import Testing

@testable import LithePGAppUI

@Suite("Appearance settings")
@MainActor
struct AppearanceSettingsTests {
  @Test("defaults to dark appearance without writing test defaults")
  func defaultAppearanceIsDark() {
    let scopedDefaults = ScopedDefaults.make()
    defer { scopedDefaults.destroy() }

    let state = AppState(appearanceDefaults: scopedDefaults.defaults)

    #expect(state.appearancePreference == .dark)
    #expect(state.appearancePreference.colorScheme == .dark)
    #expect(scopedDefaults.defaults.string(forKey: AppearancePreference.storageKey) == nil)
  }

  @Test("selecting light dark and system persists across app state instances")
  func appearanceSelectionPersists() {
    let scopedDefaults = ScopedDefaults.make()
    defer { scopedDefaults.destroy() }
    let defaults = scopedDefaults.defaults

    let state = AppState(appearanceDefaults: defaults)
    state.appearancePreference = .light

    #expect(defaults.string(forKey: AppearancePreference.storageKey) == AppearancePreference.light.rawValue)
    #expect(AppState(appearanceDefaults: defaults).appearancePreference == .light)
    #expect(state.appearancePreference.colorScheme == .light)

    state.appearancePreference = .system

    #expect(defaults.string(forKey: AppearancePreference.storageKey) == AppearancePreference.system.rawValue)
    #expect(AppState(appearanceDefaults: defaults).appearancePreference == .system)
    #expect(state.appearancePreference.colorScheme == nil)

    state.appearancePreference = .dark

    #expect(defaults.string(forKey: AppearancePreference.storageKey) == AppearancePreference.dark.rawValue)
    #expect(AppState(appearanceDefaults: defaults).appearancePreference == .dark)
    #expect(state.appearancePreference.colorScheme == .dark)
  }

  private struct ScopedDefaults {
    let suiteName: String
    let defaults: UserDefaults

    static func make() -> Self {
      let suiteName = "com.lithepg.tests.appearance.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suiteName)!
      defaults.removePersistentDomain(forName: suiteName)
      return Self(suiteName: suiteName, defaults: defaults)
    }

    func destroy() {
      defaults.removePersistentDomain(forName: suiteName)
    }
  }
}
