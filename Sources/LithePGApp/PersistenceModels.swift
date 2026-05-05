import Foundation

public enum ConnectionEnvironment: String, CaseIterable, Sendable, Codable, Equatable, Identifiable {
    case development
    case staging
    case production
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .development: "Development"
        case .staging: "Staging"
        case .production: "Production"
        case .custom: "Custom"
        }
    }

    public var isProduction: Bool { self == .production }
}

public struct SavedConnectionMetadata: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    public var database: String
    public var username: String
    public var tlsMode: String
    public var pinnedRootCertificatePath: String?
    public var sshTarget: String?
    public var environment: ConnectionEnvironment
    public var secretReference: String?
    public var integrityKeyReference: String?
    public var integrityTag: String?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int,
        database: String,
        username: String,
        tlsMode: String,
        pinnedRootCertificatePath: String? = nil,
        sshTarget: String? = nil,
        environment: ConnectionEnvironment,
        secretReference: String? = nil,
        integrityKeyReference: String? = nil,
        integrityTag: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.database = database
        self.username = username
        self.tlsMode = tlsMode
        self.pinnedRootCertificatePath = pinnedRootCertificatePath
        self.sshTarget = sshTarget
        self.environment = environment
        self.secretReference = secretReference
        self.integrityKeyReference = integrityKeyReference
        self.integrityTag = integrityTag
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var connectionLabel: String {
        "\(username)@\(host):\(port)/\(database)"
    }
}

public struct QueryHistoryEntry: Identifiable, Sendable, Codable, Equatable {
    public var id: UUID
    public var connectionName: String?
    public var connectionLabel: String
    public var environment: ConnectionEnvironment?
    public var sql: String
    public var executedAt: Date
    public var elapsedMilliseconds: Int64
    public var summary: String
    public var succeeded: Bool

    public init(
        id: UUID = UUID(),
        connectionName: String? = nil,
        connectionLabel: String,
        environment: ConnectionEnvironment? = nil,
        sql: String,
        executedAt: Date = Date(),
        elapsedMilliseconds: Int64,
        summary: String,
        succeeded: Bool
    ) {
        self.id = id
        self.connectionName = connectionName
        self.connectionLabel = connectionLabel
        self.environment = environment
        self.sql = sql
        self.executedAt = executedAt
        self.elapsedMilliseconds = elapsedMilliseconds
        self.summary = summary
        self.succeeded = succeeded
    }
}
