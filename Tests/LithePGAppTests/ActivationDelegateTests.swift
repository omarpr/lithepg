import AppKit
import Foundation
import Testing

@testable import LithePGAppUI

@Suite("UnbundledActivationDelegate")
struct ActivationDelegateTests {
  @Test("manual activation applies to bare executables but not app bundles")
  func manualActivationOnlyOutsideAppBundles() {
    #expect(
      UnbundledActivationDelegate.needsManualActivation(
        bundleURL: URL(fileURLWithPath: "/tmp/lithepg/.build/debug/LithePGApp")
      )
    )
    #expect(
      !UnbundledActivationDelegate.needsManualActivation(
        bundleURL: URL(fileURLWithPath: "/Applications/LithePG.app")
      )
    )
  }

  @Test("closing the last window terminates LithePG")
  @MainActor
  func closingLastWindowTerminatesApplication() {
    let delegate = UnbundledActivationDelegate()

    #expect(delegate.applicationShouldTerminateAfterLastWindowClosed(NSApplication.shared))
  }
}
