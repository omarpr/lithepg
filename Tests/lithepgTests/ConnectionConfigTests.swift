import Testing
@testable import lithepg

@Suite("ConnectionConfig")
struct ConnectionConfigTests {
    @Test("defaults to port 5432 and tlsMode .disable when not specified")
    func defaults() {
        let c = ConnectionConfig(
            host: "localhost",
            database: "postgres",
            username: "postgres",
            password: "postgres"
        )
        #expect(c.port == 5432)
        #expect(c.tlsMode == .disable)
        #expect(c.pinnedRootCertificatePath == nil)
        #expect(c.sshConfig == nil)
    }

    @Test("parses a postgres:// URL")
    func parseURL() throws {
        let c = try ConnectionConfig(
            url: "postgres://alice:secret@db.example.com:6543/shop"
        )
        #expect(c.host == "db.example.com")
        #expect(c.port == 6543)
        #expect(c.username == "alice")
        #expect(c.password == "secret")
        #expect(c.database == "shop")
    }

    @Test("rejects non-postgres URL schemes")
    func rejectsBadScheme() {
        #expect(throws: ConnectionConfig.ParseError.self) {
            try ConnectionConfig(url: "mysql://x/y")
        }
    }

    @Test("accepts mixed-case postgres scheme (RFC 3986)")
    func acceptsMixedCaseScheme() throws {
        let c = try ConnectionConfig(url: "PostgreSQL://alice:secret@db/shop")
        #expect(c.host == "db")
        #expect(c.database == "shop")
    }

    @Test("rejects ports outside 1...65535")
    func rejectsOutOfRangePort() {
        #expect(throws: ConnectionConfig.ParseError.portOutOfRange(70000)) {
            try ConnectionConfig(url: "postgres://alice:secret@db:70000/shop")
        }
    }

    @Test("percent-decodes user and password")
    func percentDecodesCredentials() throws {
        // p%40ss → p@ss, a%23b → a#b
        let c = try ConnectionConfig(url: "postgres://a%23b:p%40ss@db/shop")
        #expect(c.username == "a#b")
        #expect(c.password == "p@ss")
    }
}
