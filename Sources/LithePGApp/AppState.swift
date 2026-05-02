import Foundation
import Observation
import LithePGCore

@Observable
@MainActor
public final class AppState {
    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(label: String)
    }

    public var connectionState: ConnectionState = .disconnected
    public var editorText: String = "" {
        didSet {
            if lastError != nil { lastError = nil }
        }
    }
    public var lastResult: QueryResult?
    public var lastError: String?
    public var isRunning: Bool = false

    public var connectionLabel: String? {
        guard case .connected(let label) = connectionState else { return nil }
        return label
    }

    public var isConnected: Bool {
        connectionLabel != nil
    }

    public var canRunQuery: Bool {
        isConnected && !isRunning && !editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var canReconnectFromLastError: Bool {
        guard lastConnectionRequest != nil, let lastError else { return false }
        return Self.isConnectionLevelError(lastError)
    }

    public var windowTitle: String {
        connectionLabel.map { "LithePG — \($0)" } ?? "LithePG"
    }

    @ObservationIgnored private var connector: PostgresConnector?
    @ObservationIgnored private var queryTask: Task<Void, Never>?
    @ObservationIgnored private var lastConnectionRequest: ConnectionRequest?

    public init() {}

    public func connect(url: String, tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil) async {
        markConnecting()
        do {
            let parsed = try ConnectionConfig(url: url)
            let config = ConnectionConfig(
                host: parsed.host,
                port: parsed.port,
                database: parsed.database,
                username: parsed.username,
                password: parsed.password,
                tlsMode: tls ? .verifyFull : parsed.tlsMode,
                pinnedRootCertificatePath: tlsCAPath?.nilIfBlank,
                sshConfig: try sshTarget?.nilIfBlank.map(Self.parseSSH)
            )
            let connector = PostgresConnector()
            try await connector.open(config: config)
            self.connector = connector
            lastConnectionRequest = .init(url: url, tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
            markConnected(label: Self.connectionLabel(for: config))
        } catch {
            connectionState = .disconnected
            setError(ErrorRedaction.redactCredentials(in: error))
        }
    }

    public func disconnect() async {
        queryTask?.cancel()
        queryTask = nil
        if let connector {
            await connector.close()
            try? await connector.shutdown()
        }
        connector = nil
        markDisconnected()
    }

    public func startQuery() {
        queryTask?.cancel()
        queryTask = Task { [weak self] in
            await self?.runCurrentQuery()
        }
    }

    public func cancelQuery() {
        queryTask?.cancel()
        queryTask = nil
        markIdle()
    }

    public func runCurrentQuery() async {
        guard let connector else {
            setError("Not connected")
            return
        }
        let sql = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else {
            setError("Enter a SQL query first.")
            return
        }

        markRunning()
        defer { markIdle() }
        do {
            let result = try await connector.execute(sql)
            try Task.checkCancellation()
            setResult(result)
        } catch is CancellationError {
            setError("Query cancelled")
        } catch {
            setError(ErrorRedaction.redactCredentials(in: error))
        }
    }

    public func markConnecting() {
        connectionState = .connecting
    }

    public func markConnected(label: String) {
        connectionState = .connected(label: label)
        lastError = nil
    }

    public func markDisconnected() {
        connectionState = .disconnected
        lastResult = nil
        isRunning = false
    }

    public func markRunning() {
        isRunning = true
        lastResult = nil
        lastError = nil
    }

    public func markIdle() {
        isRunning = false
    }

    public func setResult(_ result: QueryResult) {
        lastResult = result
        lastError = nil
    }

    public func setError(_ message: String) {
        lastError = message
    }

    public func reconnect() async {
        guard let request = lastConnectionRequest else {
            setError("No previous connection is available to reconnect.")
            return
        }
        await disconnect()
        await connect(url: request.url, tls: request.tls, tlsCAPath: request.tlsCAPath, sshTarget: request.sshTarget)
    }

    public func clearError() {
        lastError = nil
    }

    private static func connectionLabel(for config: ConnectionConfig) -> String {
        "\(config.username)@\(config.host):\(config.port)/\(config.database)"
    }

    private static func isConnectionLevelError(_ message: String) -> Bool {
        let lowercased = message.lowercased()
        return [
            "connection closed",
            "connection refused",
            "connection reset",
            "server closed",
            "not connected",
            "broken pipe",
            "network is unreachable",
            "timed out",
            "timeout",
        ].contains { lowercased.contains($0) }
    }

    private static func parseSSH(_ raw: String) throws -> ConnectionConfig.SSHConfig {
        let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else { throw ConnectParseError.invalidSSH }
        let hostPort = parts[1].split(separator: ":").map(String.init)
        let host: String
        let port: Int
        switch hostPort.count {
        case 1:
            host = hostPort[0]
            port = 22
        case 2:
            host = hostPort[0]
            guard let parsedPort = Int(hostPort[1]), (1...65535).contains(parsedPort) else {
                throw ConnectParseError.invalidSSH
            }
            port = parsedPort
        default:
            throw ConnectParseError.invalidSSH
        }
        guard !host.isEmpty else { throw ConnectParseError.invalidSSH }
        return .init(host: host, port: port, user: parts[0])
    }

    private struct ConnectionRequest {
        let url: String
        let tls: Bool
        let tlsCAPath: String?
        let sshTarget: String?
    }

    private enum ConnectParseError: Error, CustomStringConvertible {
        case invalidSSH
        var description: String { "SSH target must be user@host[:port]" }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
