import AppKit
import SwiftUI

struct AboutView: View {
  var body: some View {
    VStack(spacing: 14) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .frame(width: 96, height: 96)
        .accessibilityHidden(true)

      VStack(spacing: 4) {
        Text("LithePG")
          .font(.title.bold())
        Text(AboutPresentation.currentVersionText)
          .font(.callout.monospacedDigit())
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("about-version")
      }

      Link("www.lithepg.app", destination: AboutPresentation.websiteURL)
        .accessibilityIdentifier("about-website")

      Divider()

      VStack(spacing: 4) {
        Text("Main developer")
          .font(.caption)
          .foregroundStyle(.secondary)
        Link(
          "OmaRPR <omarpr@gmail.com>",
          destination: AboutPresentation.developerEmailURL
        )
        .accessibilityIdentifier("about-developer")
      }
    }
    .padding(28)
    .frame(width: 360)
  }
}

struct AboutCommand: Commands {
  @Environment(\.openWindow) private var openWindow

  var body: some Commands {
    CommandGroup(replacing: .appInfo) {
      Button("About LithePG") {
        openWindow(id: AboutPresentation.windowID)
      }
    }
  }
}

enum AboutPresentation {
  static let windowID = "about-lithepg"
  static let websiteURL = URL(string: "https://www.lithepg.app")!
  static let developerEmailURL = URL(string: "mailto:omarpr@gmail.com")!

  static var currentVersionText: String {
    versionText(
      marketingVersion: Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
      ) as? String,
      buildVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    )
  }

  static func versionText(
    marketingVersion: String?,
    buildVersion: String?
  ) -> String {
    guard let marketingVersion, !marketingVersion.isEmpty else {
      return "Development build"
    }
    guard let buildVersion, !buildVersion.isEmpty else {
      return "Version \(marketingVersion)"
    }
    return "Version \(marketingVersion) (\(buildVersion))"
  }
}
