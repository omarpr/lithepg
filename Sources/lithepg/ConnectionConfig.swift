import Foundation

public struct ConnectionConfig: Sendable, Equatable {
    public enum TLSMode: Sendable, Equatable {
        case disable
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
    }

    public let host: String
    public let port: Int
    public let database: String
    public let username: String
    public let password: String
    public let tlsMode: TLSMode
    public let sshConfig: SSHConfig?

    public init(
        host: String,
        port: Int = 5432,
        database: String,
        username: String,
        password: String,
        tlsMode: TLSMode = .disable,
        sshConfig: SSHConfig? = nil
    ) {
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.password = password
        self.tlsMode = tlsMode
        self.sshConfig = sshConfig
    }

    public init(url: String) throws {
        guard let parsed = URL(string: url),
              let scheme = parsed.scheme else {
            throw ParseError.invalidURL
        }
        guard scheme == "postgres" || scheme == "postgresql" else {
            throw ParseError.unsupportedScheme(scheme)
        }
        guard let host = parsed.host else { throw ParseError.missingComponent("host") }
        guard let user = parsed.user else { throw ParseError.missingComponent("user") }
        guard let password = parsed.password else { throw ParseError.missingComponent("password") }
        let db = parsed.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !db.isEmpty else { throw ParseError.missingComponent("database") }

        self.init(
            host: host,
            port: parsed.port ?? 5432,
            database: db,
            username: user,
            password: password
        )
    }
}
