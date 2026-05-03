import Foundation
import Testing
@testable import LithePGApp
import LithePGCore

private let appStateLivePostgresURL = ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]

@Suite("AppState")
@MainActor
struct AppStateTests {
    @Test("starts disconnected with empty editor")
    func initialState() {
        let s = AppState()
        #expect(s.connectionState == .disconnected)
        #expect(s.editorText.isEmpty)
        #expect(s.lastResult == nil)
        #expect(s.lastError == nil)
        #expect(s.schema == nil)
        #expect(s.schemaError == nil)
        #expect(s.isLoadingSchema == false)
        #expect(s.isRunning == false)
    }

    @Test("setError moves to error state without clobbering editor text")
    func setErrorPreservesEditor() {
        let s = AppState()
        s.editorText = "SELECT 1"
        s.setError("boom")
        #expect(s.lastError == "boom")
        #expect(s.editorText == "SELECT 1")
    }

    @Test("clearError wipes the banner")
    func clearError() {
        let s = AppState()
        s.setError("boom")
        s.clearError()
        #expect(s.lastError == nil)
    }

    @Test("editing the buffer clears any prior error")
    func editingClearsError() {
        let s = AppState()
        s.setError("boom")
        s.editorText = "SELECT 1"
        #expect(s.lastError == nil)
    }

    @Test("query tabs keep separate editor buffers")
    func queryTabsKeepSeparateBuffers() {
        let s = AppState()
        let firstID = s.selectedQueryTabID
        s.editorText = "SELECT 1"

        s.newQueryTab()
        let secondID = s.selectedQueryTabID
        #expect(secondID != firstID)
        #expect(s.queryTabs.count == 2)
        #expect(s.editorText == s.defaultEditorText)

        s.editorText = "SELECT 2"
        s.selectQueryTab(id: firstID!)
        #expect(s.editorText == "SELECT 1")

        s.selectQueryTab(id: secondID!)
        #expect(s.editorText == "SELECT 2")
    }

    @Test("closing a query tab selects a neighbor and keeps one tab open")
    func closeQueryTabSelectsNeighbor() {
        let s = AppState()
        s.editorText = "SELECT first"
        s.newQueryTab()
        s.editorText = "SELECT second"

        s.closeSelectedQueryTab()
        #expect(s.queryTabs.count == 1)
        #expect(s.editorText == "SELECT first")

        s.closeSelectedQueryTab()
        #expect(s.queryTabs.count == 1)
        #expect(s.editorText == "SELECT first")
    }

    @Test("query tabs keep separate results")
    func queryTabsKeepSeparateResults() {
        let s = AppState()
        let firstID = s.selectedQueryTabID!
        let firstResult = QueryResult(
            columns: [.init(name: "n", typeName: "int4")],
            rows: [.init(id: 0, cells: [.text("1")])],
            rowCount: 1,
            elapsed: .milliseconds(1),
            status: .rows,
            truncated: false
        )
        s.setResult(firstResult)

        s.newQueryTab()
        #expect(s.lastResult == nil)
        let secondID = s.selectedQueryTabID!
        let secondResult = QueryResult(
            columns: [.init(name: "n", typeName: "int4")],
            rows: [.init(id: 0, cells: [.text("2")])],
            rowCount: 1,
            elapsed: .milliseconds(2),
            status: .rows,
            truncated: false
        )
        s.setResult(secondResult)

        s.selectQueryTab(id: firstID)
        #expect(s.lastResult?.rows.first?.cells.first == .text("1"))
        s.selectQueryTab(id: secondID)
        #expect(s.lastResult?.rows.first?.cells.first == .text("2"))
    }

    @Test("setResult stores the result and clears error")
    func setResultClearsError() {
        let s = AppState()
        s.setError("boom")
        let r = QueryResult(
            columns: [.init(name: "n", typeName: "int4")],
            rows: [.init(id: 0, cells: [.text("1")])],
            rowCount: 1,
            elapsed: .milliseconds(5),
            status: .rows,
            truncated: false
        )
        s.setResult(r)
        #expect(s.lastResult?.rowCount == 1)
        #expect(s.lastError == nil)
    }

    @Test("connection lifecycle transitions: disconnected → connecting → connected → disconnected")
    func connectionLifecycle() {
        let s = AppState()
        s.schema = DatabaseSchema(schemas: [.init(name: "stale", relations: [])])
        s.schemaError = "stale schema failure"
        s.isLoadingSchema = true

        #expect(s.connectionState == .disconnected)
        s.markConnecting()
        #expect(s.connectionState == .connecting)
        #expect(s.schema == nil)
        #expect(s.schemaError == nil)
        #expect(s.isLoadingSchema == false)

        s.markConnected(label: "alice@db:5432/shop")
        if case .connected(let label) = s.connectionState {
            #expect(label == "alice@db:5432/shop")
        } else {
            Issue.record("expected .connected, got \(s.connectionState)")
        }
        s.markDisconnected()
        #expect(s.connectionState == .disconnected)
    }

    @Test("markRunning toggles isRunning and clears prior result")
    func markRunningClearsResult() {
        let s = AppState()
        let r = QueryResult(
            columns: [], rows: [], rowCount: 0, elapsed: .zero, status: .empty, truncated: false
        )
        s.setResult(r)
        s.markRunning()
        #expect(s.isRunning == true)
        #expect(s.lastResult == nil)
    }

    @Test("markIdle clears isRunning without touching result")
    func markIdleKeepsResult() {
        let s = AppState()
        s.markRunning()
        let r = QueryResult(
            columns: [], rows: [], rowCount: 0, elapsed: .zero, status: .empty, truncated: false
        )
        s.setResult(r)
        s.markIdle()
        #expect(s.isRunning == false)
        #expect(s.lastResult != nil)
    }

    @Test("refresh schema without a connection records a non-fatal error")
    func refreshSchemaRequiresConnection() async {
        let s = AppState()
        s.schema = DatabaseSchema(schemas: [.init(name: "stale", relations: [])])

        await s.refreshSchema()

        #expect(s.schema == nil)
        #expect(s.schemaError == "Not connected")
        #expect(s.connectionState == .disconnected)
    }

    @Test("startup config reads dogfood and smoke launch environments")
    func startupConfigParsesEnvironment() throws {
        let config = try #require(StartupConnectionConfig(environment: [
            "LITHEPG_STARTUP_URL": " postgres://user:secret@localhost:5432/app?sslmode=disable ",
            "LITHEPG_STARTUP_QUERY": " SELECT 1 ",
            "LITHEPG_STARTUP_TLS": "yes",
            "LITHEPG_STARTUP_TLS_CA_PATH": " /tmp/root.pem ",
            "LITHEPG_STARTUP_SSH_TARGET": " omar@example.com:22 ",
        ]))

        #expect(config.url == "postgres://user:secret@localhost:5432/app?sslmode=disable")
        #expect(config.query == "SELECT 1")
        #expect(config.tls == true)
        #expect(config.tlsCAPath == "/tmp/root.pem")
        #expect(config.sshTarget == "omar@example.com:22")

        let smokeFallback = try #require(StartupConnectionConfig(environment: [
            "LITHEPG_UI_SMOKE_URL": "postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable",
            "LITHEPG_UI_SMOKE_QUERY": "SELECT 42",
        ]))
        #expect(smokeFallback.url.contains("localhost:55432"))
        #expect(smokeFallback.query == "SELECT 42")
    }

    @Test("startup config is disabled without a launch URL")
    func startupConfigRequiresURL() {
        #expect(StartupConnectionConfig(environment: ["LITHEPG_STARTUP_QUERY": "SELECT 1"]) == nil)
    }

    @Test("connects through AppState and renders a query result", .enabled(if: appStateLivePostgresURL != nil))
    func liveConnectAndRunQuery() async throws {
        let s = AppState()
        await s.connect(url: appStateLivePostgresURL!)
        defer { Task { await s.disconnect() } }

        #expect(s.isConnected == true)
        #expect(s.lastError == nil)
        #expect(s.schema != nil)
        #expect(s.schemaError == nil)

        s.editorText = "SELECT 42 AS lithepg_app_smoke"
        await s.runCurrentQuery()

        #expect(s.isRunning == false)
        #expect(s.lastError == nil)
        #expect(s.lastResult?.status == .rows)
        #expect(s.lastResult?.rowCount == 1)
        #expect(s.lastResult?.columns.first?.name == "lithepg_app_smoke")
        #expect(s.lastResult?.rows.first?.cells.first == .text("42"))
    }

    @Test("computed UI state tracks connection and runnable query state")
    func computedUIState() {
        let s = AppState()
        #expect(s.windowTitle == "LithePG")
        #expect(s.connectionLabel == nil)
        #expect(s.isConnected == false)
        #expect(s.canRunQuery == false)
        #expect(s.canReconnectFromLastError == false)

        s.editorText = "SELECT 1"
        #expect(s.canRunQuery == false)

        s.markConnected(label: "alice@db:5432/shop")
        #expect(s.windowTitle == "LithePG — alice@db:5432/shop")
        #expect(s.connectionLabel == "alice@db:5432/shop")
        #expect(s.isConnected == true)
        #expect(s.canRunQuery == true)

        s.markRunning()
        #expect(s.canRunQuery == false)
    }

    @Test("refresh schema through AppState sees user tables", .enabled(if: appStateLivePostgresURL != nil))
    func liveRefreshSchemaSeesUserTables() async throws {
        let s = AppState()
        await s.connect(url: appStateLivePostgresURL!)
        defer { Task { await s.disconnect() } }

        s.editorText = "DROP TABLE IF EXISTS lithepg_app_schema_smoke"
        await s.runCurrentQuery()
        s.editorText = "CREATE TABLE lithepg_app_schema_smoke (id serial PRIMARY KEY, note text)"
        await s.runCurrentQuery()
        defer {
            Task {
                s.editorText = "DROP TABLE IF EXISTS lithepg_app_schema_smoke"
                await s.runCurrentQuery()
            }
        }

        await s.refreshSchema()
        let publicSchema = try #require(s.schema?.schemas.first { $0.name == "public" })
        let smoke = try #require(publicSchema.relations.first { $0.name == "lithepg_app_schema_smoke" })

        #expect(s.schemaError == nil)
        #expect(s.isLoadingSchema == false)
        #expect(smoke.kind == .table)
        #expect(smoke.columns.map { $0.name } == ["id", "note"])
    }

    @Test("reconnect uses the previous successful connection", .enabled(if: appStateLivePostgresURL != nil))
    func liveReconnectUsesPreviousConnection() async throws {
        let s = AppState()
        await s.connect(url: appStateLivePostgresURL!)
        defer { Task { await s.disconnect() } }

        #expect(s.isConnected == true)
        s.setError("connection closed by server")
        #expect(s.canReconnectFromLastError == true)

        await s.reconnect()
        #expect(s.isConnected == true)
        #expect(s.lastError == nil)
        #expect(s.schema != nil)
    }

    @Test("non-connection errors do not offer reconnect", .enabled(if: appStateLivePostgresURL != nil))
    func syntaxErrorDoesNotOfferReconnect() async throws {
        let s = AppState()
        await s.connect(url: appStateLivePostgresURL!)
        defer { Task { await s.disconnect() } }

        s.setError("syntax error at or near SELECT")
        #expect(s.canReconnectFromLastError == false)
    }
}
