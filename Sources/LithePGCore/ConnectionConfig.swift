import Foundation

public struct ConnectionConfig: Sendable, Equatable {
    public enum TLSMode: Sendable, Equatable, Hashable, CaseIterable {
        /// No encryption.
        case disable
        /// Encrypt if the server offers TLS, otherwise fall back to cleartext.
        case prefer
        /// Always encrypt, but do not verify the server certificate.
        case require
        /// Always encrypt, and verify the certificate chain and hostname.
        case verifyFull
    }

    public struct SSHConfig: Sendable, Equatable {
        public let host: String
        public let port: Int
        public let user: String
        public init(host: String, port: Int = 22, user: String) {
            self.host = host
            self.port = port
            self.user = user
        }
    }

    public enum ParseError: Error, Equatable {
        case invalidURL
        case unsupportedScheme(String)
        case missingComponent(String)
        case portOutOfRange(Int)
        case unsupportedSSLMode(String)
    }

    public let host: String
    public let port: Int
    public let database: String
    public let username: String
    public let password: String
    public let tlsMode: TLSMode
    /// Path to a PEM-encoded CA certificate to pin as the sole trust root for server verification.
    /// When set, this CA REPLACES the system default trust store (it does not add to it).
    /// Needed for internal-CA Postgres deployments: NIOSSL's system-default path on Darwin
    /// goes through SecTrust, which rejects self-signed server certs even when added as an
    /// extra anchor. Providing a specific root here routes verification through BoringSSL,
    /// which accepts the pinned CA. System-default verification (public CAs) is used when nil.
    ///
    /// Ignored, and normalized to nil by `init`, unless `tlsMode` is `.verifyFull`. The other
    /// modes do no certificate verification, so a pinned root would have nothing to feed.
    public let pinnedRootCertificatePath: String?
    public let sshConfig: SSHConfig?

    public init(
        host: String,
        port: Int = 5432,
        database: String,
        username: String,
        password: String,
        tlsMode: TLSMode? = nil,
        pinnedRootCertificatePath: String? = nil,
        sshConfig: SSHConfig? = nil
    ) {
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
        let resolvedTLSMode = tlsMode ?? Self.defaultTLSMode(forHost: host)
        self.tlsMode = resolvedTLSMode
        // Certificate verification is off in every mode except verifyFull, so a pinned root
        // would be silently ignored. Normalize it away instead, so the stored value always
        // reflects what verification will actually use.
        self.pinnedRootCertificatePath =
            resolvedTLSMode == .verifyFull ? pinnedRootCertificatePath : nil
        self.sshConfig = sshConfig
    }

    public init(url: String) throws {
        guard let parsed = URL(string: url),
              let rawScheme = parsed.scheme else {
            throw ParseError.invalidURL
        }
        // RFC 3986: URL schemes are case-insensitive.
        let scheme = rawScheme.lowercased()
        guard scheme == "postgres" || scheme == "postgresql" else {
            throw ParseError.unsupportedScheme(rawScheme)
        }
        guard let host = parsed.host else { throw ParseError.missingComponent("host") }
        // `URL.user`/`URL.password` stay percent-encoded; decode them so `%40` in a
        // generated password becomes `@` before we hand credentials to Postgres.
        guard let user = parsed.user?.removingPercentEncoding else {
            throw ParseError.missingComponent("user")
        }
        let password: String
        if let encodedPassword = parsed.password {
            guard let decodedPassword = encodedPassword.removingPercentEncoding else {
                throw ParseError.invalidURL
            }
            password = decodedPassword
        } else {
            password = ""
        }
        let db = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !db.isEmpty else { throw ParseError.missingComponent("database") }

        // `URL.port` does not range-validate; `postgres://h:70000/d` yields 70000.
        let port = parsed.port ?? 5432
        guard (1...65535).contains(port) else { throw ParseError.portOutOfRange(port) }

        self.init(
            host: host,
            port: port,
            database: db,
            username: user,
            password: password,
            tlsMode: try Self.tlsMode(from: parsed, host: host)
        )
    }

    public static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized.hasPrefix("127.")
            || normalized == "::1"
            || normalized.hasSuffix(".localhost")
    }

    private static func defaultTLSMode(forHost host: String) -> TLSMode {
        isLoopbackHost(host) ? .disable : .verifyFull
    }

    private static func tlsMode(from url: URL, host: String) throws -> TLSMode {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name.lowercased() == "sslmode" })?.value?.lowercased()
        else {
            return defaultTLSMode(forHost: host)
        }
        switch raw {
        case "disable":
            return .disable
        case "allow", "prefer":
            // libpq's `allow` tries cleartext first and TLS second. PostgresNIO offers no such
            // ordering, so both land on `prefer`, which tries TLS first. Both end up encrypted
            // whenever the server supports TLS.
            return .prefer
        case "require":
            return .require
        case "verify-ca", "verify-full":
            // verify-ca skips hostname verification. LithePG does not expose that distinction
            // yet, so it is held to the stricter bar.
            return .verifyFull
        default:
            throw ParseError.unsupportedSSLMode(raw)
        }
    }
}
