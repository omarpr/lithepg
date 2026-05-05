import Testing
@testable import LithePGCore

@Suite("ConnectionConfig")
struct ConnectionConfigTests {
    @Test("defaults localhost to port 5432 and tlsMode .disable when not specified")
    func defaultsLocalhost() {
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

    @Test("defaults non-loopback hosts to verified TLS")
    func defaultsRemoteHostsToVerifiedTLS() {
        let c = ConnectionConfig(
            host: "db.example.com",
            database: "postgres",
            username: "postgres",
            password: "postgres"
        )
        #expect(c.tlsMode == .verifyFull)
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
        #expect(c.tlsMode == .verifyFull)
    }

    @Test("keeps loopback URLs cleartext by default")
    func parsesLoopbackURLAsCleartextByDefault() throws {
        let c = try ConnectionConfig(url: "postgres://alice:secret@localhost/shop")
        #expect(c.tlsMode == .disable)
    }

    @Test("recognizes IPv4 loopback aliases")
    func recognizesIPv4LoopbackAliases() throws {
        let c = try ConnectionConfig(url: "postgres://alice:secret@127.0.0.2/shop")
        #expect(c.tlsMode == .disable)
    }



    @Test("parses sslmode disable as cleartext")
    func parsesSSLModeDisable() throws {
        let c = try ConnectionConfig(url: "postgres://alice:secret@db/shop?sslmode=disable")
        #expect(c.tlsMode == .disable)
    }

    @Test("parses encrypted sslmode values as verifyFull")
    func parsesEncryptedSSLModes() throws {
        for mode in ["require", "verify-ca", "verify-full"] {
            let c = try ConnectionConfig(url: "postgres://alice:secret@db/shop?sslmode=\(mode)")
            #expect(c.tlsMode == .verifyFull)
        }
    }

    @Test("rejects unsupported sslmode values")
    func rejectsUnsupportedSSLMode() {
        #expect(throws: ConnectionConfig.ParseError.unsupportedSSLMode("bogus")) {
            try ConnectionConfig(url: "postgres://alice:secret@db/shop?sslmode=bogus")
        }
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
