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
}
