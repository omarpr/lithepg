import Foundation
import SwiftUI

public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
  case light
  case dark
  case system

  public static let storageKey = "com.lithepg.appearancePreference"

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .light:
      "Light"
    case .dark:
      "Dark"
    case .system:
      "System"
    }
  }

  public var colorScheme: ColorScheme? {
    switch self {
    case .light:
      .light
    case .dark:
      .dark
    case .system:
      nil
    }
  }

  public init(defaults: UserDefaults) {
    guard let rawValue = defaults.string(forKey: Self.storageKey),
      let preference = Self(rawValue: rawValue)
    else {
      self = .dark
      return
    }
    self = preference
  }
}

public enum LaunchBehaviorPreference {
  public static let showConnectionWindowStorageKey =
    "com.lithepg.showConnectionWindowOnLaunch"

  public static func showsConnectionWindow(defaults: UserDefaults) -> Bool {
    guard defaults.object(forKey: showConnectionWindowStorageKey) != nil else {
      return true
    }
    return defaults.bool(forKey: showConnectionWindowStorageKey)
  }
}
