import Foundation
import Testing

@testable import LithePGAppUI

/// Real-Keychain round-trip coverage for `KeychainCredentialStore`.
///
/// Gated behind `LITHEPG_KEYCHAIN_TESTS=1` because keychain access needs an
/// unlocked login keychain; locked CI runners should skip it. Plain `swift test`
/// runners lack the data-protection keychain entitlement, so these tests also
/// exercise the store's -34018 fallback to the legacy keychain, the same path an
/// unsigned dev build takes. Uses a dedicated test service name and unique
/// references so it never touches real saved-connection secrets.
private let keychainTestsEnabled =
  ProcessInfo.processInfo.environment["LITHEPG_KEYCHAIN_TESTS"] == "1"

@Suite("KeychainCredentialStore")
struct KeychainCredentialStoreTests {
  private static let testService = "com.omarpr.lithepg.tests"

  @Test("round-trips save, load, overwrite and delete", .enabled(if: keychainTestsEnabled))
  func roundTripsSecretLifecycle() async throws {
    let store = KeychainCredentialStore(service: Self.testService)
    let reference = "test-\(UUID().uuidString)"

    do {
      try await store.saveSecret("first-secret", for: reference)
      #expect(try await store.loadSecret(for: reference) == "first-secret")

      // Overwrite must replace, not duplicate or fail on the existing item.
      try await store.saveSecret("second-secret", for: reference)
      #expect(try await store.loadSecret(for: reference) == "second-secret")

      try await store.deleteSecret(for: reference)
      #expect(try await store.loadSecret(for: reference) == nil)
    } catch {
      // Never leave test items behind in the user keychain, even on failure.
      try? await store.deleteSecret(for: reference)
      throw error
    }
  }

  @Test("missing references load as nil and delete without throwing", .enabled(if: keychainTestsEnabled))
  func missingReferencesAreBenign() async throws {
    let store = KeychainCredentialStore(service: Self.testService)
    let reference = "missing-\(UUID().uuidString)"

    #expect(try await store.loadSecret(for: reference) == nil)
    // Deleting an absent item must be a no-op, not an error.
    try await store.deleteSecret(for: reference)
  }

  @Test("secrets are isolated per reference", .enabled(if: keychainTestsEnabled))
  func secretsAreIsolatedPerReference() async throws {
    let store = KeychainCredentialStore(service: Self.testService)
    let first = "isolated-a-\(UUID().uuidString)"
    let second = "isolated-b-\(UUID().uuidString)"

    do {
      try await store.saveSecret("alpha", for: first)
      try await store.saveSecret("beta", for: second)
      #expect(try await store.loadSecret(for: first) == "alpha")
      #expect(try await store.loadSecret(for: second) == "beta")

      try await store.deleteSecret(for: first)
      #expect(try await store.loadSecret(for: first) == nil)
      #expect(try await store.loadSecret(for: second) == "beta")
      try await store.deleteSecret(for: second)
    } catch {
      try? await store.deleteSecret(for: first)
      try? await store.deleteSecret(for: second)
      throw error
    }
  }
}
