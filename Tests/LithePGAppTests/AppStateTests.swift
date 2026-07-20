import Foundation
import LithePGCore
import Testing

@testable import LithePGAppUI

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

  @Test("query tab navigation wraps around")
  func queryTabNavigationWrapsAround() {
    let s = AppState()
    let firstID = s.selectedQueryTabID!
    s.newQueryTab()
    let secondID = s.selectedQueryTabID!
    s.newQueryTab()
    let thirdID = s.selectedQueryTabID!

    s.selectNextQueryTab()
    #expect(s.selectedQueryTabID == firstID)
    s.selectPreviousQueryTab()
    #expect(s.selectedQueryTabID == thirdID)
    s.selectPreviousQueryTab()
    #expect(s.selectedQueryTabID == secondID)
  }

  @Test("query results can land in the originating tab after tab switches")
  func queryResultsCanTargetOriginatingTab() {
    let s = AppState()
    let firstID = s.selectedQueryTabID!
    s.newQueryTab()
    let secondID = s.selectedQueryTabID!
    let firstResult = QueryResult(
      columns: [.init(name: "n", typeName: "int4")],
      rows: [.init(id: 0, cells: [.text("1")])],
      rowCount: 1,
      elapsed: .milliseconds(1),
      status: .rows,
      truncated: false
    )

    s.setResult(firstResult, for: firstID)

    #expect(s.selectedQueryTabID == secondID)
    #expect(s.lastResult == nil)
    s.selectQueryTab(id: firstID)
    #expect(s.lastResult?.rows.first?.cells.first == .text("1"))
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

  @Test("insert select quotes schema and relation identifiers")
  func insertSelectQuotesIdentifiers() {
    let s = AppState()
    let relation = DatabaseSchema.Relation(
      schema: "odd schema",
      name: "order\"lines",
      kind: .table,
      columns: []
    )

    s.insertSelect(for: relation)

    #expect(s.editorText == "SELECT * FROM \"odd schema\".\"order\"\"lines\" LIMIT 100;")
  }

  @Test("insert select strips control characters from identifiers")
  func insertSelectStripsControlCharacters() {
    let s = AppState()
    let relation = DatabaseSchema.Relation(
      schema: "public\u{0000}",
      name: "users\u{0008}",
      kind: .table,
      columns: []
    )

    s.insertSelect(for: relation)

    #expect(s.editorText == "SELECT * FROM \"public\".\"users\" LIMIT 100;")
  }

  @Test("ask in English without schema records an AI error and preserves editor text")
  func askInEnglishRequiresSchema() async {
    let s = AppState()
    s.editorText = "SELECT existing"

    await s.askInEnglish("show customers")

    #expect(s.editorText == "SELECT existing")
    #expect(s.aiError == "Refresh schema before asking in English.")
    #expect(s.lastAIDraft == nil)
    #expect(s.isDraftingSQL == false)
  }

  @Test("ask in English inserts deterministic draft SQL into the active query tab")
  func askInEnglishInsertsDraftIntoActiveTab() async throws {
    let s = AppState(aiQueryService: FixtureAIQueryService())
    s.schema = dogfoodSchema
    let firstID = s.selectedQueryTabID!
    s.newQueryTab()
    let secondID = s.selectedQueryTabID!
    s.editorText = "SELECT old"

    await s.askInEnglish("show customers")

    #expect(s.selectedQueryTabID == secondID)
    #expect(s.editorText == "SELECT * FROM \"lithepg_demo\".\"customers\" LIMIT 100;")
    #expect(s.lastAIDraft?.referencedObjects == ["lithepg_demo.customers"])
    #expect(s.lastAIDraft?.status == .ready)
    #expect(s.aiError == nil)
    #expect(s.isDraftingSQL == false)
    s.selectQueryTab(id: firstID)
    #expect(s.editorText.isEmpty)
  }

  @Test("ask in English never auto-runs generated SQL")
  func askInEnglishDoesNotAutoRunDraftSQL() async {
    let s = AppState(aiQueryService: FixtureAIQueryService())
    s.schema = dogfoodSchema

    await s.askInEnglish("show customers")

    #expect(s.isRunning == false)
    #expect(s.lastResult == nil)
    #expect(s.lastError == nil)
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
    let config = try #require(
      StartupConnectionConfig(environment: [
        "LITHEPG_STARTUP_URL": " postgres://user:secret@localhost:5432/app?sslmode=disable ",
        "LITHEPG_STARTUP_QUERY": " SELECT 1 ",
        "LITHEPG_STARTUP_TLS": "yes",
        "LITHEPG_STARTUP_TLS_CA_PATH": " /tmp/root.pem ",
        "LITHEPG_STARTUP_SSH_TARGET": " omar@example.com:22 ",
        "LITHEPG_STARTUP_METRICS_PATH": " /tmp/lithepg-startup.json ",
      ]))

    #expect(config.url == "postgres://user:secret@localhost:5432/app?sslmode=disable")
    #expect(config.query == "SELECT 1")
    #expect(config.tls == true)
    #expect(config.tlsCAPath == "/tmp/root.pem")
    #expect(config.sshTarget == "omar@example.com:22")
    #expect(config.metricsPath == "/tmp/lithepg-startup.json")

    let smokeFallback = try #require(
      StartupConnectionConfig(environment: [
        "LITHEPG_UI_SMOKE_URL":
          "postgres://postgres:postgres@localhost:55432/postgres?sslmode=disable",
        "LITHEPG_UI_SMOKE_QUERY": "SELECT 42",
      ]))
    #expect(smokeFallback.url.contains("localhost:55432"))
    #expect(smokeFallback.query == "SELECT 42")
  }

  @Test("startup config is disabled without a launch URL")
  func startupConfigRequiresURL() {
    #expect(StartupConnectionConfig(environment: ["LITHEPG_STARTUP_QUERY": "SELECT 1"]) == nil)
  }

  @Test("connect sheet display redacts prefilled URL credentials")
  func connectSheetRedactsPrefilledCredentials() {
    let displayed = ConnectSheet.redactedURLForDisplay(
      "postgres://omar:screen-share-secret@db.example.com/postgres")

    #expect(!displayed.contains("screen-share-secret"))
    #expect(displayed == "postgres://omar:[redacted]@db.example.com/postgres")
  }

  @Test("startup metrics path can be provided without auto-connecting")
  func startupMetricsPathCanStandAlone() {
    #expect(
      StartupMetricsConfig.metricsPath(environment: ["LITHEPG_STARTUP_METRICS_PATH": " /tmp/shell.json "])
        == "/tmp/shell.json")
    #expect(
      StartupConnectionConfig(environment: ["LITHEPG_STARTUP_METRICS_PATH": " /tmp/shell.json "])
        == nil)
  }

  @Test("loads saved connections and keeps selection stable")
  func loadsSavedConnections() async throws {
    let betaID = UUID()
    let store = InMemorySavedConnectionStore(connections: [
      SavedConnectionMetadata(
        id: betaID, name: "Beta", host: "b", port: 5432, database: "db", username: "u",
        tlsMode: "disable", environment: .staging),
      SavedConnectionMetadata(
        name: "Alpha", host: "a", port: 5432, database: "db", username: "u", tlsMode: "disable",
        environment: .development),
    ])
    let s = AppState(savedConnectionStore: store)

    await s.loadSavedConnections()

    #expect(s.savedConnections.map(\.name) == ["Alpha", "Beta"])
    #expect(s.selectedSavedConnectionID == s.savedConnections.first?.id)
    s.selectedSavedConnectionID = betaID
    await s.loadSavedConnections()
    #expect(s.selectedSavedConnectionID == betaID)
    #expect(s.persistenceError == nil)
  }

  @Test("saving a connection stores metadata separately from the password")
  func saveConnectionSplitsMetadataAndCredential() async throws {
    let savedStore = InMemorySavedConnectionStore()
    let credentialStore = InMemoryCredentialStore()
    let s = AppState(savedConnectionStore: savedStore, credentialStore: credentialStore)

    let metadata = try #require(
      await s.saveConnection(
        name: " Local dogfood ",
        url: "postgres://omar:s3cr3t@localhost:55432/postgres?sslmode=disable",
        tls: true,
        tlsCAPath: " /tmp/root.pem ",
        sshTarget: nil,
        environment: .development
      ))

    #expect(metadata.name == "Local dogfood")
    #expect(metadata.connectionLabel == "omar@localhost:55432/postgres")
    #expect(metadata.tlsMode == "verify-full")
    #expect(metadata.pinnedRootCertificatePath == "/tmp/root.pem")
    #expect(metadata.environment == .development)
    #expect(metadata.secretReference?.contains("s3cr3t") == false)
    #expect(try await credentialStore.loadSecret(for: metadata.secretReference!) == "s3cr3t")
    #expect(s.savedConnections == [metadata])
    #expect(s.selectedSavedConnectionID == metadata.id)
    #expect(s.persistenceError == nil)
  }

  @Test("saving a connection redacts parse errors")
  func saveConnectionRedactsParseErrors() async throws {
    let s = AppState()

    let metadata = await s.saveConnection(
      name: "Broken",
      url: "postgres://omar:super-secret@localhost:70000/postgres",
      environment: .development
    )

    #expect(metadata == nil)
    #expect(s.persistenceError != nil)
    #expect(s.persistenceError?.contains("super-secret") == false)
  }

  @Test("connecting a saved connection rejects unknown TLS labels")
  func savedConnectionRejectsUnknownTLSLabel() async throws {
    let id = UUID()
    let metadata = SavedConnectionMetadata(
      id: id,
      name: "Tampered",
      host: "db.example.com",
      port: 5432,
      database: "postgres",
      username: "omar",
      tlsMode: "prefer",
      environment: .development,
      secretReference: "ref"
    )
    let s = AppState(
      savedConnectionStore: InMemorySavedConnectionStore(connections: [metadata]),
      credentialStore: InMemoryCredentialStore(secrets: ["ref": "secret"])
    )
    await s.loadSavedConnections()

    await s.connectSavedConnection(id: id)

    #expect(s.connectionState == .disconnected)
    #expect(s.lastError?.contains("unsupported TLS mode") == true)
  }

  @Test("deleting a saved connection removes its credential")
  func deleteSavedConnectionRemovesCredential() async throws {
    let savedStore = InMemorySavedConnectionStore()
    let credentialStore = InMemoryCredentialStore()
    let s = AppState(savedConnectionStore: savedStore, credentialStore: credentialStore)
    let metadata = try #require(
      await s.saveConnection(
        name: "Delete me",
        url: "postgres://omar:pw@localhost:5432/postgres",
        environment: .custom
      ))
    let reference = try #require(metadata.secretReference)

    await s.deleteSavedConnection(id: metadata.id)

    #expect(s.savedConnections.isEmpty)
    #expect(try await credentialStore.loadSecret(for: reference) == nil)
    #expect(s.selectedSavedConnectionID == nil)
    #expect(s.persistenceError == nil)
  }

  @Test("loads, clears, and reuses query history entries")
  func queryHistoryLoadClearAndReuse() async throws {
    let store = InMemoryQueryHistoryStore(entries: [
      QueryHistoryEntry(
        connectionLabel: "omar@localhost:5432/postgres",
        sql: "SELECT newest",
        executedAt: Date(timeIntervalSince1970: 2),
        elapsedMilliseconds: 2,
        summary: "1 row",
        succeeded: true
      ),
      QueryHistoryEntry(
        connectionLabel: "omar@localhost:5432/postgres",
        sql: "SELECT oldest",
        executedAt: Date(timeIntervalSince1970: 1),
        elapsedMilliseconds: 1,
        summary: "1 row",
        succeeded: true
      ),
    ])
    let s = AppState(queryHistoryStore: store)

    await s.loadQueryHistory(limit: 1)

    #expect(s.queryHistory.map(\.sql) == ["SELECT newest"])
    s.useHistoryEntry(s.queryHistory[0])
    #expect(s.editorText == "SELECT newest")

    await s.clearQueryHistory()
    #expect(s.queryHistory.isEmpty)
    #expect(s.persistenceError == nil)
  }

  @Test(
    "query history records successful live queries when enabled",
    .enabled(if: appStateLivePostgresURL != nil))
  func liveQueryHistoryRecordsSuccess() async throws {
    let historyStore = InMemoryQueryHistoryStore()
    let s = AppState(queryHistoryStore: historyStore)
    s.queryHistoryEnabled = true
    await s.connect(url: appStateLivePostgresURL!)
    defer { Task { await s.disconnect() } }

    s.editorText = "SELECT 7 AS history_smoke"
    await s.runCurrentQuery()

    let entry = try #require(s.queryHistory.first)
    #expect(entry.sql == "SELECT 7 AS history_smoke")
    // The label must reflect whatever host POSTGRES_TEST_URL points at (localhost
    // for the dogfood fixture, a remote hostname for live Neon runs).
    let expectedHost = try ConnectionConfig(url: appStateLivePostgresURL!).host
    #expect(entry.connectionLabel.contains(expectedHost))
    #expect(entry.succeeded == true)
    #expect(entry.summary == "1 row")
    #expect(entry.elapsedMilliseconds >= 0)
  }

  @Test(
    "saved connection flow resolves credentials and tracks production environment",
    .enabled(if: appStateLivePostgresURL != nil))
  func liveSavedConnectionFlowTracksEnvironment() async throws {
    let savedStore = InMemorySavedConnectionStore()
    let credentialStore = InMemoryCredentialStore()
    let historyStore = InMemoryQueryHistoryStore()
    let s = AppState(
      savedConnectionStore: savedStore,
      credentialStore: credentialStore,
      queryHistoryStore: historyStore
    )

    let metadata = try #require(
      await s.saveConnection(
        name: "Production smoke",
        url: appStateLivePostgresURL!,
        environment: .production
      ))

    await s.connectSavedConnection(id: metadata.id)
    defer { Task { await s.disconnect() } }

    #expect(s.isConnected == true)
    #expect(s.lastError == nil)
    #expect(s.schema != nil)
    #expect(s.activeSavedConnection?.id == metadata.id)
    #expect(s.activeConnectionEnvironment == .production)
    #expect(s.windowTitle == "LithePG · Production smoke")

    s.queryHistoryEnabled = true
    s.editorText = "SELECT 9 AS saved_connection_smoke"
    await s.runCurrentQuery()

    #expect(s.lastResult?.rows.first?.cells.first == .text("9"))
    let history = try #require(s.queryHistory.first)
    #expect(history.connectionName == "Production smoke")
    #expect(history.environment == .production)
    #expect(history.sql == "SELECT 9 AS saved_connection_smoke")
  }

  @Test(
    "connects through AppState and renders a query result",
    .enabled(if: appStateLivePostgresURL != nil))
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
    #expect(s.windowTitle == "LithePG · alice@db:5432/shop")
    #expect(s.connectionLabel == "alice@db:5432/shop")
    #expect(s.isConnected == true)
    #expect(s.canRunQuery == true)

    s.markRunning()
    #expect(s.canRunQuery == false)
  }

  @Test(
    "refresh schema through AppState sees user tables", .enabled(if: appStateLivePostgresURL != nil)
  )
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

  @Test(
    "reconnect uses the previous successful connection",
    .enabled(if: appStateLivePostgresURL != nil))
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

  @Test(
    "non-connection errors do not offer reconnect", .enabled(if: appStateLivePostgresURL != nil))
  func syntaxErrorDoesNotOfferReconnect() async throws {
    let s = AppState()
    await s.connect(url: appStateLivePostgresURL!)
    defer { Task { await s.disconnect() } }

    s.setError("syntax error at or near SELECT")
    #expect(s.canReconnectFromLastError == false)
  }

  private var dogfoodSchema: DatabaseSchema {
    DatabaseSchema(schemas: [
      .init(name: "lithepg_demo", relations: [
        .init(schema: "lithepg_demo", name: "customers", kind: .table, columns: [
          .init(name: "id", typeName: "uuid", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
          .init(name: "name", typeName: "text", isNullable: false, ordinalPosition: 2),
        ]),
      ]),
    ])
  }

  private struct FixtureAIQueryService: AIQueryService {
    func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft {
      AIQueryDraft(
        sql: "SELECT * FROM \"lithepg_demo\".\"customers\" LIMIT 100;",
        explanation: "Fixture draft for \(request.prompt).",
        referencedObjects: ["lithepg_demo.customers"],
        status: .ready,
        confidence: 1
      )
    }
  }
}

@Suite("AppState insert-and-run")
@MainActor
struct AppStateInsertAndRunTests {
  @Test("insert and run without a connection only inserts the SQL")
  func insertAndRunWhileDisconnected() async {
    let s = AppState()
    let relation = DatabaseSchema.Relation(
      schema: "public", name: "customers", kind: .table, columns: [])

    await s.insertAndRunSelect(for: relation)

    #expect(s.editorText == "SELECT * FROM \"public\".\"customers\" LIMIT 100;")
    #expect(s.isRunning == false)
    #expect(s.lastError == nil)
    #expect(s.lastResult == nil)
  }
}

@Suite("AppState explain")
@MainActor
struct AppStateExplainTests {
  @Test("explain without a connection reports an error and no plan")
  func explainWhileDisconnected() async {
    let s = AppState()
    s.editorText = "SELECT 1"
    await s.runExplain(analyze: false)
    #expect(s.lastError == "Not connected")
    #expect(s.lastQueryPlan == nil)
    #expect(s.isExplaining == false)
  }

  @Test("explain with an empty editor asks for SQL first")
  func explainWithEmptyEditor() async {
    let s = AppState()
    s.markConnected(label: "test@localhost:5432/db")
    s.editorText = "   "
    await s.runExplain(analyze: false)
    #expect(s.lastError == "Enter a SQL query first.")
    #expect(s.lastQueryPlan == nil)
  }

  @Test("clearing the plan removes it")
  func clearQueryPlan() {
    let s = AppState()
    s.clearQueryPlan()
    #expect(s.lastQueryPlan == nil)
  }
}

@Suite("AppState tab rename")
@MainActor
struct AppStateTabRenameTests {
  @Test("renames a tab and trims whitespace")
  func renamesAndTrims() {
    let s = AppState()
    let id = s.selectedQueryTabID!
    s.renameQueryTab(id: id, to: "  revenue report  ")
    #expect(s.queryTabs[0].title == "revenue report")
  }

  @Test("blank names keep the current title")
  func blankNamesKeepTitle() {
    let s = AppState()
    let id = s.selectedQueryTabID!
    let before = s.queryTabs[0].title
    s.renameQueryTab(id: id, to: "   ")
    #expect(s.queryTabs[0].title == before)
  }

  @Test("renaming an unknown tab does nothing")
  func unknownTabIsIgnored() {
    let s = AppState()
    let before = s.queryTabs.map(\.title)
    s.renameQueryTab(id: UUID(), to: "ghost")
    #expect(s.queryTabs.map(\.title) == before)
  }
}

@Suite("AppState connection testing")
@MainActor
struct AppStateConnectionTestingTests {
  @Test("successful test validates SELECT 1 without connecting the workspace")
  func successfulTestIsNonPersistent() async throws {
    let tester = FixtureConnectionTester()
    let state = AppState(connectionTester: tester)

    await state.testConnection(
      url: "postgresql://owner:secret@ep-blue.neon.tech/app?sslmode=require")

    #expect(state.connectionTestMessage == "Connection successful. SELECT 1 completed.")
    #expect(state.connectionTestError == nil)
    #expect(state.connectionState == .disconnected)
    #expect(state.savedConnections.isEmpty)
    let config = try #require(await tester.lastConfig)
    #expect(config.host == "ep-blue.neon.tech")
    #expect(config.database == "app")
    #expect(config.tlsMode == .verifyFull)
  }

  @Test("failed test redacts credentials and leaves workspace disconnected")
  func failureIsRedacted() async {
    let tester = FixtureConnectionTester(error: FixtureConnectionTestError(
      message: "authentication failed for postgresql://owner:super-secret@db.example.com/app"
    ))
    let state = AppState(connectionTester: tester)

    await state.testConnection(
      url: "postgresql://owner:super-secret@db.example.com/app")

    #expect(state.connectionTestMessage == nil)
    #expect(state.connectionTestError?.contains("super-secret") == false)
    #expect(state.connectionTestError != nil)
    #expect(state.connectionState == .disconnected)
  }

  @Test("invalid connection input fails before opening a test connection")
  func invalidInputDoesNotReachTester() async {
    let tester = FixtureConnectionTester()
    let state = AppState(connectionTester: tester)

    await state.testConnection(url: "not a postgres URL")

    #expect(state.connectionTestMessage == nil)
    #expect(state.connectionTestError != nil)
    #expect(await tester.callCount == 0)
  }
}

private actor FixtureConnectionTester: ConnectionTesting {
  private(set) var lastConfig: ConnectionConfig?
  private(set) var callCount = 0
  let error: (any Error & Sendable)?

  init(error: (any Error & Sendable)? = nil) {
    self.error = error
  }

  func test(config: ConnectionConfig) async throws {
    callCount += 1
    lastConfig = config
    if let error { throw error }
  }
}

private struct FixtureConnectionTestError: Error, Sendable, LocalizedError {
  let message: String
  var errorDescription: String? { message }
}
