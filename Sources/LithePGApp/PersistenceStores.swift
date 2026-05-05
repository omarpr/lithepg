import Foundation
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
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  public init(fileURL: URL = PersistenceFileLocations.savedConnectionsURL) {
    self.fileURL = fileURL
    self.encoder = JSONEncoder()
    self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    self.decoder = JSONDecoder()
  }

  public func list() async throws -> [SavedConnectionMetadata] {
    try readAll().sorted { lhs, rhs in
      lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
    }
  }

  public func save(_ connection: SavedConnectionMetadata) async throws {
    var connections = try readAll()
    if let index = connections.firstIndex(where: { $0.id == connection.id }) {
      connections[index] = connection
    } else {
      connections.append(connection)
    }
    try writeAll(connections)
  }

  public func delete(id: SavedConnectionMetadata.ID) async throws {
    var connections = try readAll()
    connections.removeAll { $0.id == id }
    try writeAll(connections)
  }

  private func readAll() throws -> [SavedConnectionMetadata] {
    guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
    let data = try Data(contentsOf: fileURL)
    return try decoder.decode([SavedConnectionMetadata].self, from: data)
  }

  private func writeAll(_ connections: [SavedConnectionMetadata]) throws {
    try PersistenceFileProtection.prepareSecureJSONFile(at: fileURL)
    let data = try encoder.encode(connections)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
    try PersistenceFileProtection.applyJSONFilePermissions(to: fileURL)
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
    var query = baseQuery(reference: reference, dataProtection: true)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  public func loadSecret(for reference: String) async throws -> String? {
    if let secret = try loadSecret(for: reference, dataProtection: true) { return secret }
    // Backward-compatible read path for secrets saved before the data-protection keychain
    // migration. The next save writes to the hardened path.
    return try loadSecret(for: reference, dataProtection: false)
  }

  public func deleteSecret(for reference: String) async throws {
    let first = SecItemDelete(baseQuery(reference: reference, dataProtection: true) as CFDictionary)
    let second = SecItemDelete(baseQuery(reference: reference, dataProtection: false) as CFDictionary)
    for status in [first, second] where status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError(status: status)
    }
  }

  private func loadSecret(for reference: String, dataProtection: Bool) throws -> String? {
    var query = baseQuery(reference: reference, dataProtection: dataProtection)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
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
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
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
