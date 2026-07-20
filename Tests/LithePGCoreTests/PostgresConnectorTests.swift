import Testing
import Foundation
@testable import LithePGCore

@Suite("PostgresConnector")
struct PostgresConnectorTests {
    static var plainURL: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]
    }

    static var tlsURL: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TLS_TEST_URL"]
    }

    static var tlsCAPath: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TLS_CA_PATH"]
    }

    /// Format: "user@sshHost:sshPort,pgHost:pgPort"
    /// e.g., "developer@bastion.example.com:22,pg-internal.example.com:5432"
    static var sshPgTarget: String? {
        ProcessInfo.processInfo.environment["POSTGRES_SSH_TEST_TARGET"]
    }

    /// Format: "user:password:database"
    static var sshPgCreds: String? {
        ProcessInfo.processInfo.environment["POSTGRES_SSH_TEST_CREDS"]
    }

    enum TargetParseError: Error { case malformed }

    @Test("construct and shutdown without connecting")
    func lifecycleSmoke() async throws {
        let connector = PostgresConnector()
        try await connector.shutdown()
        try await connector.shutdown() // idempotent
    }

    @Test("surfaces a typed error when the pinned root cert path is unreadable")
    func pinnedRootUnreadable() async throws {
        let config = ConnectionConfig(
            host: "127.0.0.1",
            database: "postgres",
            username: "postgres",
            password: "postgres",
            tlsMode: .verifyFull,
            pinnedRootCertificatePath: "/tmp/lithepg-does-not-exist.pem"
        )
        let connector = PostgresConnector()
        await #expect(throws: PostgresConnectorError.self) {
            _ = try await connector.runSelect1(config: config)
        }
        try await connector.shutdown()
    }


    @Test("execute requires an open connection")
    func executeRequiresOpenConnection() async throws {
        let connector = PostgresConnector()
        await #expect(throws: PostgresConnector.ExecuteError.notConnected) {
            _ = try await connector.execute("SELECT 1")
        }
        try await connector.shutdown()
    }

    @Test(
        "opens a persistent connection and runs two queries on it",
        .enabled(if: plainURL != nil)
    )
    func persistentExecuteRunsMultipleQueries() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        try await connector.open(config: config)
        defer { Task { await connector.close() } }

        let a = try await connector.execute("SELECT 1 AS n")
        #expect(a.status == .rows)
        #expect(a.rowCount == 1)
        #expect(a.columns.first?.name == "n")
        #expect(a.rows.first?.cells.first == .text("1"))

        let b = try await connector.execute("SELECT 'hello' AS greeting")
        #expect(b.status == .rows)
        #expect(b.rowCount == 1)
        #expect(b.rows.first?.cells.first == .text("hello"))

        try await connector.shutdown()
    }

    @Test(
        "execute surfaces a QueryResult.Status.command for non-returning SQL",
        .enabled(if: plainURL != nil)
    )
    func persistentExecuteCommandStatus() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        try await connector.open(config: config)
        defer { Task { await connector.close() } }

        _ = try await connector.execute("CREATE TEMP TABLE lithepg_v02a_tmp (id int)")
        let ins = try await connector.execute("INSERT INTO lithepg_v02a_tmp VALUES (1), (2), (3)")
        switch ins.status {
        case .command(let tag, let affected):
            #expect(tag == "INSERT")
            #expect(affected == 3)
        default:
            Issue.record("expected .command status, got \(ins.status)")
        }

        try await connector.shutdown()
    }

    @Test(
        "execute decodes NULL as QueryResult.Cell.null",
        .enabled(if: plainURL != nil)
    )
    func persistentExecuteNullCell() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        try await connector.open(config: config)
        defer { Task { await connector.close() } }

        let r = try await connector.execute("SELECT NULL::text AS maybe")
        #expect(r.rows.first?.cells.first == .null)

        try await connector.shutdown()
    }

    @Test(
        "connects over plain TCP and runs SELECT 1",
        .enabled(if: plainURL != nil)
    )
    func plainSelect1() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        do {
            let value = try await connector.runSelect1(config: config)
            #expect(value == 1)
        } catch {
            try await connector.shutdown()
            throw error
        }
        try await connector.shutdown()
    }

    @Test(
        "connects over TLS verify-full and runs SELECT 1",
        .enabled(if: tlsURL != nil && tlsCAPath != nil)
    )
    func tlsVerifyFullSelect1() async throws {
        let parsed = try ConnectionConfig(url: Self.tlsURL!)
        let config = ConnectionConfig(
            host: parsed.host,
            port: parsed.port,
            database: parsed.database,
            username: parsed.username,
            password: parsed.password,
            tlsMode: .verifyFull,
            pinnedRootCertificatePath: Self.tlsCAPath!
        )
        let connector = PostgresConnector()
        do {
            let value = try await connector.runSelect1(config: config)
            #expect(value == 1)
        } catch {
            try await connector.shutdown()
            throw error
        }
        try await connector.shutdown()
    }

    @Test(
        "connects to Postgres over an SSH tunnel and runs SELECT 1",
        .enabled(if: sshPgTarget != nil && sshPgCreds != nil)
    )
    func sshTunnelSelect1() async throws {
        let (sshHost, sshPort, sshUser, pgHost, pgPort) = try Self.parseSSHPgTarget(Self.sshPgTarget!)
        let (pgUser, pgPassword, pgDatabase) = try Self.parseSSHPgCreds(Self.sshPgCreds!)

        let config = ConnectionConfig(
            host: pgHost,
            port: pgPort,
            database: pgDatabase,
            username: pgUser,
            password: pgPassword,
            tlsMode: .disable,
            sshConfig: .init(host: sshHost, port: sshPort, user: sshUser)
        )

        let connector = PostgresConnector()
        do {
            let value = try await connector.runSelect1(config: config)
            #expect(value == 1)
        } catch {
            try await connector.shutdown()
            throw error
        }
        try await connector.shutdown()
    }

    /// Strict parser — malformed targets fail loudly instead of silently defaulting.
    private static func parseSSHPgTarget(
        _ s: String
    ) throws -> (sshHost: String, sshPort: Int, sshUser: String, pgHost: String, pgPort: Int) {
        let halves = s.split(separator: ",", maxSplits: 1).map(String.init)
        guard halves.count == 2 else { throw TargetParseError.malformed }

        let sshParts = halves[0].split(separator: "@", maxSplits: 1).map(String.init)
        guard sshParts.count == 2 else { throw TargetParseError.malformed }
        let sshHostPort = sshParts[1].split(separator: ":").map(String.init)
        guard sshHostPort.count == 2, let sshPort = Int(sshHostPort[1]) else {
            throw TargetParseError.malformed
        }

        let pgHostPort = halves[1].split(separator: ":").map(String.init)
        guard pgHostPort.count == 2, let pgPort = Int(pgHostPort[1]) else {
            throw TargetParseError.malformed
        }

        return (sshHostPort[0], sshPort, sshParts[0], pgHostPort[0], pgPort)
    }

    private static func parseSSHPgCreds(
        _ s: String
    ) throws -> (user: String, password: String, database: String) {
        let parts = s.split(separator: ":", maxSplits: 2).map(String.init)
        guard parts.count == 3 else { throw TargetParseError.malformed }
        return (parts[0], parts[1], parts[2])
    }
}
