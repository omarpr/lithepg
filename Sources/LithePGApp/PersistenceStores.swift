import Foundation
import CryptoKit
import Security

public protocol SavedConnectionStore: Sendable {
  func list() async throws -> [SavedConnectionMetadata]
  func save(_ connection: SavedConnectionMetadata) async throws
  func delete(id: SavedConnectionMetadata.ID) async throws
}

public protocol CredentialStore: Sendable {
  func saveSecret(_ secret: String, for reference: String) async throws
  func loadSecret(for reference: String) async throws -> String?
  func deleteSecret(for reference: String) async throws
}

public protocol QueryHistoryStore: Sendable {
  func list(limit: Int?) async throws -> [QueryHistoryEntry]
  func append(_ entry: QueryHistoryEntry) async throws
  func clear() async throws
}

public actor JSONFileSavedConnectionStore: SavedConnectionStore {
  private let fileURL: URL
  private let integrityStore: any CredentialStore
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(
    fileURL: URL = PersistenceFileLocations.savedConnectionsURL,
    integrityStore: any CredentialStore = KeychainCredentialStore(service: "com.omarpr.lithepg.integrity")
  ) {
    self.fileURL = fileURL
    self.integrityStore = integrityStore
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.decoder = JSONDecoder()
  }

  public func list() async throws -> [SavedConnectionMetadata] {
    try await readAll().sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  public func save(_ connection: SavedConnectionMetadata) async throws {
    var connections = try await readAll()
    let signed = try await signedConnection(connection)
    if let index = connections.firstIndex(where: { $0.id == signed.id }) {
      connections[index] = signed
    } else {
      connections.append(signed)
    }
    try writeAll(connections)
  }

  public func delete(id: SavedConnectionMetadata.ID) async throws {
    var connections = try await readAll()
    let removed = connections.first { $0.id == id }
    connections.removeAll { $0.id == id }
    try writeAll(connections)
    if let reference = removed?.integrityKeyReference {
      try await integrityStore.deleteSecret(for: reference)
    }
  }

  private func readAll() async throws -> [SavedConnectionMetadata] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    let connections = try decoder.decode([SavedConnectionMetadata].self, from: data)
    try await verify(connections)
    return connections
  }

  private func writeAll(_ connections: [SavedConnectionMetadata]) throws {
    try PersistenceFileProtection.prepareSecureJSONFile(at: fileURL)
    let data = try encoder.encode(connections)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try PersistenceFileProtection.applyJSONFilePermissions(to: fileURL)
  }

  private func signedConnection(_ connection: SavedConnectionMetadata) async throws -> SavedConnectionMetadata {
    var signed = connection
    let reference = signed.integrityKeyReference ?? Self.integrityKeyReference(for: signed.id)
    signed.integrityKeyReference = reference
    let keyBase64: String
    if let existing = try await integrityStore.loadSecret(for: reference) {
      keyBase64 = existing
    } else {
      keyBase64 = Self.newIntegrityKeyBase64()
      try await integrityStore.saveSecret(keyBase64, for: reference)
    }
    signed.integrityTag = try Self.integrityTag(for: signed, keyBase64: keyBase64)
    return signed
  }

  private func verify(_ connections: [SavedConnectionMetadata]) async throws {
    for connection in connections {
      guard let reference = connection.integrityKeyReference,
        let tag = connection.integrityTag
      else {
        throw PersistenceIntegrityError.missingSignature
      }
      guard let keyBase64 = try await integrityStore.loadSecret(for: reference) else {
        throw PersistenceIntegrityError.missingIntegrityKey
      }
      guard try Self.isValidIntegrityTag(tag, for: connection, keyBase64: keyBase64) else {
        throw PersistenceIntegrityError.invalidSignature
      }
    }
  }

  private static func integrityKeyReference(for id: SavedConnectionMetadata.ID) -> String {
    "lithepg.connection.\(id.uuidString.lowercased()).integrity"
  }

  private static func newIntegrityKeyBase64() -> String {
    SymmetricKey(size: .bits256).withUnsafeBytes { bytes in
      Data(bytes).base64EncodedString()
    }
  }

  private static func integrityTag(
    for connection: SavedConnectionMetadata,
    keyBase64: String
  ) throws -> String {
    let key = try integrityKey(from: keyBase64)
    let data = try canonicalIntegrityData(for: connection)
    let code = HMAC<SHA256>.authenticationCode(for: data, using: key)
    return Data(code).base64EncodedString()
  }

  private static func isValidIntegrityTag(
    _ tag: String,
    for connection: SavedConnectionMetadata,
    keyBase64: String
  ) throws -> Bool {
    guard let code = Data(base64Encoded: tag) else { return false }
    let key = try integrityKey(from: keyBase64)
    let data = try canonicalIntegrityData(for: connection)
    return HMAC<SHA256>.isValidAuthenticationCode(code, authenticating: data, using: key)
  }

  private static func integrityKey(from keyBase64: String) throws -> SymmetricKey {
    guard let data = Data(base64Encoded: keyBase64) else {
      throw PersistenceIntegrityError.missingIntegrityKey
    }
    return SymmetricKey(data: data)
  }

  private static func canonicalIntegrityData(for connection: SavedConnectionMetadata) throws -> Data {
    var payload = connection
    payload.integrityTag = nil
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(payload)
  }
}

public enum PersistenceIntegrityError: Error, Equatable, CustomStringConvertible {
  case missingSignature
  case missingIntegrityKey
  case invalidSignature

  public var description: String {
    switch self {
    case .missingSignature:
      "Saved connection metadata is missing its integrity signature."
    case .missingIntegrityKey:
      "Saved connection metadata integrity key is missing from credential storage."
    case .invalidSignature:
      "Saved connection metadata integrity check failed."
    }
  }
}

public actor KeychainCredentialStore: CredentialStore {
  private let service: String

  public init(service: String = "com.omarpr.lithepg") {
    self.service = service
  }

  public func saveSecret(_ secret: String, for reference: String) async throws {
    let data = Data(secret.utf8)
    // Remove any previous value from both the data-protection and legacy keychains, then
    // write the new value to the data-protection keychain so future sandboxed/signed builds
    // scope credentials to the app identity instead of the broad user login keychain.
    SecItemDelete(baseQuery(reference: reference, dataProtection: true) as CFDictionary)
    SecItemDelete(baseQuery(reference: reference, dataProtection: false) as CFDictionary)
    var status = addSecret(data, reference: reference, dataProtection: true)
    if status == errSecMissingEntitlement {
      // Entitlement-less processes (unsigned dev builds, plain `swift test` runners)
      // cannot use the data-protection keychain at all (-34018). Falling back to the
      // legacy login keychain keeps credentials out of plaintext instead of making
      // every save fail; signed builds still take the hardened path above.
      status = addSecret(data, reference: reference, dataProtection: false)
    }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  public func loadSecret(for reference: String) async throws -> String? {
    if let secret = try loadSecret(for: reference, dataProtection: true) { return secret }
    // Backward-compatible read path for secrets saved before the data-protection keychain
    // migration and for entitlement-less builds that write to the legacy keychain.
    return try loadSecret(for: reference, dataProtection: false)
  }

  public func deleteSecret(for reference: String) async throws {
    let first = SecItemDelete(baseQuery(reference: reference, dataProtection: true) as CFDictionary)
    let second = SecItemDelete(baseQuery(reference: reference, dataProtection: false) as CFDictionary)
    for status in [first, second]
    where status != errSecSuccess && status != errSecItemNotFound && status != errSecMissingEntitlement {
      throw KeychainError(status: status)
    }
  }

  private func addSecret(_ data: Data, reference: String, dataProtection: Bool) -> OSStatus {
    var query = baseQuery(reference: reference, dataProtection: dataProtection)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(query as CFDictionary, nil)
  }

  private func loadSecret(for reference: String, dataProtection: Bool) throws -> String? {
    var query = baseQuery(reference: reference, dataProtection: dataProtection)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    // An entitlement-less process cannot query the data-protection keychain (-34018);
    // report "not found here" so the caller falls through to the legacy keychain.
    if status == errSecMissingEntitlement && dataProtection { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  private func baseQuery(reference: String, dataProtection: Bool) -> [String: Any] {
    Self.baseQuery(service: service, reference: reference, dataProtection: dataProtection)
  }

  static func baseQuery(service: String, reference: String, dataProtection: Bool) -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference,
      kSecAttrSynchronizable as String: false,
    ]
    query[kSecUseDataProtectionKeychain as String] = dataProtection
    return query
  }
}

public actor JSONFileQueryHistoryStore: QueryHistoryStore {
  private let fileURL: URL
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(fileURL: URL = PersistenceFileLocations.queryHistoryURL) {
    self.fileURL = fileURL
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.decoder = JSONDecoder()
  }

  public func list(limit: Int? = nil) async throws -> [QueryHistoryEntry] {
    let sorted = try readAll().sorted { $0.executedAt > $1.executedAt }
    guard let limit else { return sorted }
    return Array(sorted.prefix(max(0, limit)))
  }

  public func append(_ entry: QueryHistoryEntry) async throws {
    var entries = try readAll()
    entries.append(entry)
    try writeAll(entries)
  }

  public func clear() async throws {
    try writeAll([])
  }

  private func readAll() throws -> [QueryHistoryEntry] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode([QueryHistoryEntry].self, from: data)
  }

  private func writeAll(_ entries: [QueryHistoryEntry]) throws {
    try PersistenceFileProtection.prepareSecureJSONFile(at: fileURL)
    let data = try encoder.encode(entries)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    try PersistenceFileProtection.applyJSONFilePermissions(to: fileURL)
  }
}

enum PersistenceFileProtection {
  static func prepareSecureJSONFile(at fileURL: URL) throws {
    let directory = fileURL.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  static func applyJSONFilePermissions(to fileURL: URL) throws {
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
  }
}

public actor InMemorySavedConnectionStore: SavedConnectionStore {
  private var connections: [SavedConnectionMetadata]

  public init(connections: [SavedConnectionMetadata] = []) {
    self.connections = connections
  }

  public func list() async throws -> [SavedConnectionMetadata] {
    connections.sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  public func save(_ connection: SavedConnectionMetadata) async throws {
    if let index = connections.firstIndex(where: { $0.id == connection.id }) {
      connections[index] = connection
    } else {
      connections.append(connection)
    }
  }

  public func delete(id: SavedConnectionMetadata.ID) async throws {
    connections.removeAll { $0.id == id }
  }
}

public actor InMemoryCredentialStore: CredentialStore {
  private var secrets: [String: String]

  public init(secrets: [String: String] = [:]) {
    self.secrets = secrets
  }

  public func saveSecret(_ secret: String, for reference: String) async throws {
    secrets[reference] = secret
  }

  public func loadSecret(for reference: String) async throws -> String? {
    secrets[reference]
  }

  public func deleteSecret(for reference: String) async throws {
    secrets[reference] = nil
  }
}

public actor InMemoryQueryHistoryStore: QueryHistoryStore {
  private var entries: [QueryHistoryEntry]

  public init(entries: [QueryHistoryEntry] = []) {
    self.entries = entries
  }

  public func list(limit: Int? = nil) async throws -> [QueryHistoryEntry] {
    let sorted = entries.sorted { $0.executedAt > $1.executedAt }
    guard let limit else { return sorted }
    return Array(sorted.prefix(max(0, limit)))
  }

  public func append(_ entry: QueryHistoryEntry) async throws {
    entries.append(entry)
  }

  public func clear() async throws {
    entries.removeAll()
  }
}

public enum PersistenceFileLocations {
  public static let applicationSupportDirectory: URL = {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
        "Library/Application Support")
    return base.appendingPathComponent("LithePG", isDirectory: true)
  }()

  public static let savedConnectionsURL = applicationSupportDirectory.appendingPathComponent(
    "saved-connections.json")
  public static let queryHistoryURL = applicationSupportDirectory.appendingPathComponent(
    "query-history.json")
}

public struct KeychainError: Error, CustomStringConvertible, Equatable {
  public let status: OSStatus

  public init(status: OSStatus) {
    self.status = status
  }

  public var description: String {
    if let message = SecCopyErrorMessageString(status, nil) as String? {
      return "Keychain error: \(message) (\(status))"
    }
    return "Keychain error: \(status)"
  }
}
