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
    public var queryTabs: [QueryTab] = [.init(title: "Query 1")]
    public var selectedQueryTabID: QueryTab.ID?
    public var editorText: String {
        get { selectedQueryTab?.text ?? "" }
        set {
            guard let index = selectedQueryTabIndex else { return }
            queryTabs[index].text = newValue
            if lastError != nil { lastError = nil }
        }
    }
    public var lastResult: QueryResult? {
        get { selectedQueryTab?.lastResult }
        set {
            guard let index = selectedQueryTabIndex else { return }
            queryTabs[index].lastResult = newValue
        }
    }
    public var lastError: String?
    public var schema: DatabaseSchema?
    public var schemaError: String?
    public var isLoadingSchema: Bool = false
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
    @ObservationIgnored private var activeQueryRunID: UUID?
    @ObservationIgnored private var lastConnectionRequest: ConnectionRequest?

    public init() {
        selectedQueryTabID = queryTabs.first?.id
    }

    public var selectedQueryTab: QueryTab? {
        guard let selectedQueryTabID else { return queryTabs.first }
        return queryTabs.first { $0.id == selectedQueryTabID } ?? queryTabs.first
    }

    private var selectedQueryTabIndex: Int? {
        guard let selectedQueryTabID,
              let index = queryTabs.firstIndex(where: { $0.id == selectedQueryTabID }) else {
            return queryTabs.indices.first
        }
        return index
    }

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
            await refreshSchema()
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

    public func refreshSchema() async {
        guard let connector else {
            schema = nil
            schemaError = "Not connected"
            return
        }

        isLoadingSchema = true
        schemaError = nil
        defer { isLoadingSchema = false }
        do {
            schema = try await SchemaIntrospector.loadSchema(using: connector)
            schemaError = nil
        } catch {
            schemaError = ErrorRedaction.redactCredentials(in: error)
        }
    }

    public func startQuery() {
        queryTask?.cancel()
        let runID = UUID()
        activeQueryRunID = runID
        queryTask = Task { [weak self] in
            await self?.runCurrentQuery(runID: runID)
        }
    }

    public func cancelQuery() {
        queryTask?.cancel()
        queryTask = nil
        activeQueryRunID = nil
        if isRunning {
            setError("Query cancelled")
        }
        markIdle()
    }

    public func newQueryTab() {
        let nextNumber = queryTabs.count + 1
        let tab = QueryTab(title: "Query \(nextNumber)", text: defaultEditorText)
        queryTabs.append(tab)
        selectedQueryTabID = tab.id
        clearError()
    }

    public func selectQueryTab(id: QueryTab.ID) {
        guard queryTabs.contains(where: { $0.id == id }) else { return }
        selectedQueryTabID = id
        clearError()
    }

    public func closeSelectedQueryTab() {
        guard queryTabs.count > 1, let index = selectedQueryTabIndex else { return }
        let removingSelected = queryTabs[index].id == selectedQueryTabID
        queryTabs.remove(at: index)
        if removingSelected {
            let replacementIndex = min(index, queryTabs.count - 1)
            selectedQueryTabID = queryTabs[replacementIndex].id
        }
        clearError()
    }

    public func selectNextQueryTab() {
        selectQueryTab(offset: 1)
    }

    public func selectPreviousQueryTab() {
        selectQueryTab(offset: -1)
    }

    public func insertSelect(for relation: DatabaseSchema.Relation) {
        editorText = Self.selectSQL(for: relation)
    }

    public static func selectSQL(for relation: DatabaseSchema.Relation) -> String {
        "SELECT * FROM \(quotedIdentifier(relation.schema)).\(quotedIdentifier(relation.name)) LIMIT 100;"
    }

    public func runCurrentQuery() async {
        let runID = UUID()
        activeQueryRunID = runID
        await runCurrentQuery(runID: runID)
    }

    private func runCurrentQuery(runID: UUID) async {
        guard let connector else {
            setError("Not connected")
            clearActiveQuery(if: runID)
            return
        }
        guard let queryTabID = selectedQueryTabID else {
            setError("No query tab is selected.")
            clearActiveQuery(if: runID)
            return
        }
        let sql = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sql.isEmpty else {
            setError("Enter a SQL query first.")
            clearActiveQuery(if: runID)
            return
        }

        markRunning()
        defer { finishQuery(if: runID) }
        do {
            let result = try await connector.execute(sql)
            try Task.checkCancellation()
            if activeQueryRunID == runID {
                setResult(result, for: queryTabID)
            }
        } catch is CancellationError {
            if activeQueryRunID == runID {
                setError("Query cancelled")
            }
        } catch {
            if activeQueryRunID == runID {
                setError(ErrorRedaction.redactCredentials(in: error))
            }
        }
    }

    public func markConnecting() {
        connectionState = .connecting
        schema = nil
        schemaError = nil
        isLoadingSchema = false
    }

    public func markConnected(label: String) {
        connectionState = .connected(label: label)
        lastError = nil
    }

    public func markDisconnected() {
        connectionState = .disconnected
        lastResult = nil
        schema = nil
        schemaError = nil
        isLoadingSchema = false
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
        guard let selectedQueryTabID else { return }
        setResult(result, for: selectedQueryTabID)
    }

    public func setResult(_ result: QueryResult, for queryTabID: QueryTab.ID) {
        guard let index = queryTabs.firstIndex(where: { $0.id == queryTabID }) else { return }
        queryTabs[index].lastResult = result
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

    public let defaultEditorText = "SELECT version();"

    private func selectQueryTab(offset: Int) {
        guard queryTabs.count > 1, let index = selectedQueryTabIndex else { return }
        let nextIndex = (index + offset + queryTabs.count) % queryTabs.count
        selectedQueryTabID = queryTabs[nextIndex].id
        clearError()
    }

    private func finishQuery(if runID: UUID) {
        guard activeQueryRunID == runID else { return }
        clearActiveQuery(if: runID)
        markIdle()
    }

    private func clearActiveQuery(if runID: UUID) {
        guard activeQueryRunID == runID else { return }
        activeQueryRunID = nil
        queryTask = nil
    }

    private static func connectionLabel(for config: ConnectionConfig) -> String {
        "\(config.username)@\(config.host):\(config.port)/\(config.database)"
    }

    private static func quotedIdentifier(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
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
