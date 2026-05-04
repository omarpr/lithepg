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
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try encoder.encode(connections)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
  }
}

public actor KeychainCredentialStore: CredentialStore {
  private let service: String

  public init(service: String = "com.omarpr.lithepg") {
    self.service = service
  }

  public func saveSecret(_ secret: String, for reference: String) async throws {
    let data = Data(secret.utf8)
    var query = baseQuery(reference: reference)
    SecItemDelete(query as CFDictionary)
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  public func loadSecret(for reference: String) async throws -> String? {
    var query = baseQuery(reference: reference)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = result as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  public func deleteSecret(for reference: String) async throws {
    let status = SecItemDelete(baseQuery(reference: reference) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }

  private func baseQuery(reference: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: reference,
    ]
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
    try FileManager.default.createDirectory(
      at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let data = try encoder.encode(entries)
    try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
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
