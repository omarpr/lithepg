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
        // First reading treats an existing `%XX` as an escape, so already-encoded URLs are
        // untouched. If that yields credentials Foundation cannot decode, the `%` was literal
        // after all (`p%bcss` looks like an escape for byte 0xBC, which is not valid UTF-8), so
        // read it again with every `%` escaped.
        var candidate = Self.percentEncodingUserInfo(in: url, preservingExistingEscapes: true)
        if !Self.userInfoDecodes(candidate) {
            candidate = Self.percentEncodingUserInfo(in: url, preservingExistingEscapes: false)
        }
        guard let parsed = URL(string: candidate),
              let rawScheme = parsed.scheme else {
            throw ParseError.invalidURL
        }
        // RFC 3986: URL schemes are case-insensitive.
        let scheme = rawScheme.lowercased()
        guard scheme == "postgres" || scheme == "postgresql" else {
            throw ParseError.unsupportedScheme(rawScheme)
        }
        guard let host = parsed.host else { throw ParseError.missingComponent("host") }
        // Ask for the decoded form explicitly. The bare `URL.user`/`URL.password` properties
        // already percent-decode, so running `removingPercentEncoding` over them decoded twice:
        // a credential containing a literal `%` came back mangled, or nil when the second pass
        // saw an invalid escape. That stayed hidden while decoded credentials held no `%`.
        guard let user = parsed.user(percentEncoded: false) else {
            throw ParseError.missingComponent("user")
        }
        // A present-but-undecodable password must not collapse to "", which would silently
        // authenticate with the wrong credential and surface as a confusing auth failure.
        let password: String
        if parsed.password(percentEncoded: true) != nil {
            guard let decoded = parsed.password(percentEncoded: false) else {
                throw ParseError.invalidURL
            }
            password = decoded
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

    // MARK: - Credential normalization

    /// True when the credentials in an already-encoded URL survive percent-decoding. Used to
    /// decide whether a `%XX` in the input was a real escape or a literal percent sign.
    private static func userInfoDecodes(_ url: String) -> Bool {
        guard let parsed = URL(string: url) else { return false }
        if parsed.user(percentEncoded: true) != nil, parsed.user(percentEncoded: false) == nil {
            return false
        }
        if parsed.password(percentEncoded: true) != nil,
            parsed.password(percentEncoded: false) == nil {
            return false
        }
        return true
    }

    /// Percent-encodes the credentials in a connection string so strict URL parsing accepts
    /// characters people actually paste.
    ///
    /// RFC 3986 makes `#` begin a fragment, so `postgres://a#b:pw@host/db` parses as host `a`
    /// with a fragment, losing the credentials entirely. `libpq` has the same rule and expects
    /// the caller to encode. People paste straight from a dashboard instead, so encode the
    /// userinfo region for them rather than rejecting the string.
    ///
    /// With `preservingExistingEscapes`, an existing `%XX` passes through untouched, so an
    /// already-encoded URL is unchanged and the transform is idempotent. Passing `false` treats
    /// every `%` as literal, which is the fallback for a credential like `p%bcss` where the
    /// escape reading produces bytes that are not valid UTF-8.
    ///
    /// Returns the input unchanged when there is no userinfo.
    ///
    /// Raw `/` and `?` in credentials remain unsupported: both terminate the authority, so
    /// `postgres://u:p/w@host/db` is genuinely ambiguous and `libpq` rejects it too. A literal
    /// `:` in a username is likewise indistinguishable from the user/password separator. Those
    /// still have to be percent-encoded by hand.
    static func percentEncodingUserInfo(
        in url: String,
        preservingExistingEscapes: Bool = true
    ) -> String {
        guard let schemeSeparator = url.range(of: "://") else { return url }
        let authorityStart = schemeSeparator.upperBound

        // The authority ends at the first `/` or `?`. `#` is deliberately not a terminator
        // here, because rescuing a literal `#` in the credentials is the whole point.
        let authorityEnd =
            url[authorityStart...].firstIndex { $0 == "/" || $0 == "?" } ?? url.endIndex
        let authority = url[authorityStart..<authorityEnd]

        // A host cannot contain `@`, so the last one in the authority delimits the credentials.
        guard let atSign = authority.lastIndex(of: "@") else { return url }
        let userInfo = authority[authority.startIndex..<atSign]
        let hostAndPort = authority[authority.index(after: atSign)...]

        // Split on the first `:`, matching how a URL separates user from password. A literal
        // `:` inside a username is indistinguishable from that separator and stays unsupported.
        let user: Substring
        let password: Substring?
        if let colon = userInfo.firstIndex(of: ":") {
            user = userInfo[userInfo.startIndex..<colon]
            password = userInfo[userInfo.index(after: colon)...]
        } else {
            user = userInfo
            password = nil
        }

        var rebuilt = String(url[url.startIndex..<authorityStart])
        rebuilt += percentEncodingUserInfoComponent(
            user, preservingExistingEscapes: preservingExistingEscapes)
        if let password {
            rebuilt += ":"
                + percentEncodingUserInfoComponent(
                    password, preservingExistingEscapes: preservingExistingEscapes)
        }
        rebuilt += "@"
        rebuilt += hostAndPort
        rebuilt += url[authorityEnd...]
        return rebuilt
    }

    /// Unreserved and sub-delim characters, the set RFC 3986 allows in userinfo unencoded.
    private static let userInfoAllowedCharacters: Set<Character> = {
        var allowed = Set<Character>("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        allowed.formUnion("abcdefghijklmnopqrstuvwxyz")
        allowed.formUnion("0123456789")
        allowed.formUnion("-._~")
        allowed.formUnion("!$&'()*+,;=")
        return allowed
    }()

    private static func percentEncodingUserInfoComponent(
        _ raw: Substring,
        preservingExistingEscapes: Bool
    ) -> String {
        let characters = Array(raw)
        var encoded = ""
        var index = 0
        while index < characters.count {
            let character = characters[index]
            // Pass an existing escape through, so encoding never runs twice on the same input.
            if preservingExistingEscapes, character == "%", index + 2 < characters.count,
                characters[index + 1].isHexDigit, characters[index + 2].isHexDigit {
                encoded.append(contentsOf: characters[index...(index + 2)])
                index += 3
                continue
            }
            if userInfoAllowedCharacters.contains(character) {
                encoded.append(character)
            } else {
                for byte in String(character).utf8 {
                    encoded += String(format: "%%%02X", byte)
                }
            }
            index += 1
        }
        return encoded
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
