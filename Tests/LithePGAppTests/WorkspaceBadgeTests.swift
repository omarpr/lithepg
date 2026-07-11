import Testing

@testable import LithePGAppUI

@Suite("Workspace version badge")
struct WorkspaceBadgeTests {
  @Test("uses the bundle marketing version when present")
  func usesMarketingVersion() {
    #expect(WorkspaceView.versionBadgeLabel(marketingVersion: "0.5") == "v0.5")
  }

  @Test("falls back to dev for unbundled runs")
  func fallsBackToDev() {
    #expect(WorkspaceView.versionBadgeLabel(marketingVersion: nil) == "dev")
    #expect(WorkspaceView.versionBadgeLabel(marketingVersion: "") == "dev")
  }
}
