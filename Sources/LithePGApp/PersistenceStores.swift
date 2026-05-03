import Foundation

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
