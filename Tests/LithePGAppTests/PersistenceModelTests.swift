import Foundation
import Testing
@testable import LithePGApp

@Suite("Persistence models")
struct PersistenceModelTests {
    @Test("saved connection metadata has labels and no password field")
    func savedConnectionMetadataHasNoPasswordField() throws {
        let connection = SavedConnectionMetadata(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            name: "Local dev",
            host: "localhost",
            port: 5432,
            database: "app",
            username: "omar",
            tlsMode: "disable",
            environment: .development,
            secretReference: "lithepg-connection-secret"
        )

        #expect(connection.connectionLabel == "omar@localhost:5432/app")
        #expect(connection.environment.displayName == "Development")
        #expect(connection.environment.isProduction == false)

        let encoded = try JSONEncoder().encode(connection)
        let json = String(decoding: encoded, as: UTF8.self)
        #expect(!json.lowercased().contains("password"))
        #expect(!json.contains("super-secret"))
    }

    @Test("in-memory saved connection store upserts, sorts, and deletes")
    func inMemorySavedConnectionStore() async throws {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let store = InMemorySavedConnectionStore()
        let beta = SavedConnectionMetadata(id: id, name: "Beta", host: "b", port: 5432, database: "db", username: "u", tlsMode: "disable", environment: .staging)
        let alpha = SavedConnectionMetadata(name: "Alpha", host: "a", port: 5432, database: "db", username: "u", tlsMode: "disable", environment: .development)

        try await store.save(beta)
        try await store.save(alpha)
        #expect(try await store.list().map(\.name) == ["Alpha", "Beta"])

        var updated = beta
        updated.name = "Gamma"
        try await store.save(updated)
        #expect(try await store.list().map(\.name) == ["Alpha", "Gamma"])

        try await store.delete(id: id)
        #expect(try await store.list().map(\.name) == ["Alpha"])
    }

    @Test("in-memory credential store keeps secrets outside metadata")
    func inMemoryCredentialStore() async throws {
        let store = InMemoryCredentialStore()

        try await store.saveSecret("super-secret", for: "ref-1")

        #expect(try await store.loadSecret(for: "ref-1") == "super-secret")
        try await store.deleteSecret(for: "ref-1")
        #expect(try await store.loadSecret(for: "ref-1") == nil)
    }

    @Test("query history lists newest first and can clear")
    func inMemoryQueryHistoryStore() async throws {
        let store = InMemoryQueryHistoryStore()
        try await store.append(.init(
            connectionLabel: "a@localhost:5432/app",
            sql: "SELECT 1",
            executedAt: Date(timeIntervalSince1970: 1),
            elapsedMilliseconds: 3,
            summary: "1 row",
            succeeded: true
        ))
        try await store.append(.init(
            connectionLabel: "a@localhost:5432/app",
            sql: "SELECT 2",
            executedAt: Date(timeIntervalSince1970: 2),
            elapsedMilliseconds: 4,
            summary: "1 row",
            succeeded: true
        ))

        #expect(try await store.list(limit: 1).map(\.sql) == ["SELECT 2"])
        try await store.clear()
        #expect(try await store.list(limit: nil).isEmpty)
    }
}
