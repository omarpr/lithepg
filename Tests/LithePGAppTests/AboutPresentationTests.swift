import Testing

@testable import LithePGAppUI

@Suite("About presentation")
struct AboutPresentationTests {
  @Test("shows semantic marketing version and numeric build")
  func semanticVersionAndBuild() {
    #expect(AboutPresentation.versionText(
      marketingVersion: "1.0.0",
      buildVersion: "428"
    ) == "Version 1.0.0 (428)")
  }

  @Test("shows marketing version without an unavailable build")
  func marketingVersionOnly() {
    #expect(AboutPresentation.versionText(
      marketingVersion: "1.0.0",
      buildVersion: nil
    ) == "Version 1.0.0")
  }

  @Test("uses a development label outside an app bundle")
  func developmentFallback() {
    #expect(AboutPresentation.versionText(
      marketingVersion: nil,
      buildVersion: nil
    ) == "Development build")
  }

  @Test("publishes the requested website and developer email")
  func links() {
    #expect(AboutPresentation.websiteURL.absoluteString == "https://www.lithepg.app")
    #expect(AboutPresentation.developerEmailURL.absoluteString == "mailto:omarpr@gmail.com")
  }
}
