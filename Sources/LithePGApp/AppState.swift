import Foundation
import LithePGCore
import Observation

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
  public var savedConnections: [SavedConnectionMetadata] = []
  public var selectedSavedConnectionID: SavedConnectionMetadata.ID?
  public var activeSavedConnection: SavedConnectionMetadata?
  public var isTestingConnection: Bool = false
  public var connectionTestMessage: String?
  public var connectionTestError: String?
  public var neonCLIAvailability: NeonCLIAvailability = .unavailable
  public var isScanningNeon: Bool = false
  public var neonScanMessage: String?
  public var neonScanError: String?
  public var queryHistoryEnabled: Bool = false
  public var queryHistory: [QueryHistoryEntry] = []
  public var persistenceError: String?
  public var isDraftingSQL: Bool = false
  public var lastAIDraft: AIQueryDraft?
  public var aiError: String?
  public var appearancePreference: AppearancePreference = .dark {
    didSet {
      guard !isRestoringAppearancePreference else { return }
      appearanceDefaults.set(appearancePreference.rawValue, forKey: AppearancePreference.storageKey)
    }
  }

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

  public var activeConnectionEnvironment: ConnectionEnvironment? {
    activeSavedConnection?.environment
  }

  public var windowTitle: String {
    if let activeSavedConnection {
      return "LithePG · \(activeSavedConnection.name)"
    }
    return connectionLabel.map { "LithePG · \($0)" } ?? "LithePG"
  }

  @ObservationIgnored private var connector: PostgresConnector?
  @ObservationIgnored private var queryTask: Task<Void, Never>?
  @ObservationIgnored private var activeQueryRunID: UUID?
  @ObservationIgnored private var lastConnectionRequest: ConnectionRequest?
  @ObservationIgnored private let savedConnectionStore: any SavedConnectionStore
  @ObservationIgnored private let credentialStore: any CredentialStore
  @ObservationIgnored private let queryHistoryStore: any QueryHistoryStore
  @ObservationIgnored private let aiQueryService: any AIQueryService
  @ObservationIgnored private let connectionTester: any ConnectionTesting
  @ObservationIgnored private let neonScanner: any NeonCLIScanning
  @ObservationIgnored private let appearanceDefaults: UserDefaults
  @ObservationIgnored private var isRestoringAppearancePreference = false

  public init(
    savedConnectionStore: any SavedConnectionStore = JSONFileSavedConnectionStore(),
    credentialStore: any CredentialStore = KeychainCredentialStore(),
    queryHistoryStore: any QueryHistoryStore = JSONFileQueryHistoryStore(),
    aiQueryService: any AIQueryService = OnDeviceAIQueryService(),
    connectionTester: any ConnectionTesting = PostgresConnectionTester(),
    neonScanner: any NeonCLIScanning = NeonCLIScanner(),
    appearanceDefaults: UserDefaults = .standard
  ) {
    self.savedConnectionStore = savedConnectionStore
    self.credentialStore = credentialStore
    self.queryHistoryStore = queryHistoryStore
    self.aiQueryService = aiQueryService
    self.connectionTester = connectionTester
    self.neonScanner = neonScanner
    self.appearanceDefaults = appearanceDefaults
    neonCLIAvailability = neonScanner.availability()
    isRestoringAppearancePreference = true
    appearancePreference = AppearancePreference(defaults: appearanceDefaults)
    isRestoringAppearancePreference = false
    selectedQueryTabID = queryTabs.first?.id
  }

  public var selectedQueryTab: QueryTab? {
    guard let selectedQueryTabID else { return queryTabs.first }
    return queryTabs.first { $0.id == selectedQueryTabID } ?? queryTabs.first
  }

  private var selectedQueryTabIndex: Int? {
    guard let selectedQueryTabID,
      let index = queryTabs.firstIndex(where: { $0.id == selectedQueryTabID })
    else {
      return queryTabs.indices.first
    }
    return index
  }

  public func connect(
    url: String, tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil
  ) async {
    do {
      let config = try Self.connectionConfig(
        url: url, tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
      await open(
        config: config,
        label: Self.connectionLabel(for: config),
        lastRequest: .init(source: .url(url), tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget),
        savedConnection: nil
      )
    } catch {
      connectionState = .disconnected
      setError(ErrorRedaction.redactCredentials(in: error))
    }
  }

  public func testConnection(
    url: String, tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil
  ) async {
    await testConnection {
      try Self.connectionConfig(
        url: url, tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
    }
  }

  public func clearConnectionTestResult() {
    guard !isTestingConnection else { return }
    connectionTestMessage = nil
    connectionTestError = nil
  }

  public func testConnection(
    host: String, port: Int, database: String, username: String, password: String,
    tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil
  ) async {
    await testConnection {
      try Self.connectionConfig(
        host: host, port: port, database: database, username: username, password: password,
        tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
    }
  }

  public func connect(
    host: String, port: Int, database: String, username: String, password: String,
    tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil
  ) async {
    do {
      let config = try Self.connectionConfig(
        host: host, port: port, database: database, username: username, password: password,
        tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
      await open(
        config: config,
        label: Self.connectionLabel(for: config),
        lastRequest: .init(
          source: .fields(host: host, port: port, database: database, username: username, password: password),
          tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget),
        savedConnection: nil
      )
    } catch {
      connectionState = .disconnected
      setError(ErrorRedaction.redactCredentials(in: error))
    }
  }

  public func loadSavedConnections() async {
    do {
      savedConnections = try await savedConnectionStore.list()
      if let selectedSavedConnectionID,
        !savedConnections.contains(where: { $0.id == selectedSavedConnectionID })
      {
        self.selectedSavedConnectionID = savedConnections.first?.id
      } else if selectedSavedConnectionID == nil {
        selectedSavedConnectionID = savedConnections.first?.id
      }
      persistenceError = nil
    } catch {
      setPersistenceError(error)
    }
  }

  public var canScanNeon: Bool {
    neonCLIAvailability.isAvailable && !isScanningNeon
  }

  public func refreshNeonCLIAvailability() {
    neonCLIAvailability = neonScanner.availability()
  }

  public func scanAndImportNeonConnections() async {
    refreshNeonCLIAvailability()
    guard neonCLIAvailability.isAvailable else {
      neonScanMessage = nil
      neonScanError = "Install Neon CLI to scan your Neon databases."
      return
    }

    isScanningNeon = true
    neonScanMessage = nil
    neonScanError = nil
    defer { isScanningNeon = false }

    do {
      await loadSavedConnections()
      let report = try await neonScanner.scan()
      var known = Set(savedConnections.map(Self.connectionIdentity))
      var imported = 0
      var alreadySaved = 0
      var skipped = report.skippedResources

      for discovered in report.connections {
        guard let config = try? ConnectionConfig(url: discovered.connectionURL) else {
          skipped += 1
          continue
        }
        let identity = Self.connectionIdentity(config)
        guard !known.contains(identity) else {
          alreadySaved += 1
          continue
        }
        if await persistConnection(
          name: discovered.suggestedName,
          config: config,
          environment: .development
        ) != nil {
          known.insert(identity)
          imported += 1
        } else {
          skipped += 1
        }
      }

      neonScanMessage = Self.neonScanSummary(
        imported: imported,
        alreadySaved: alreadySaved,
        skipped: skipped
      )
    } catch {
      neonScanError = Self.neonScanErrorMessage(error)
    }
  }

  @discardableResult
  public func saveConnection(
    name: String,
    host: String, port: Int, database: String, username: String, password: String,
    tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil,
    environment: ConnectionEnvironment = .development
  ) async -> SavedConnectionMetadata? {
    do {
      let config = try Self.connectionConfig(
        host: host, port: port, database: database, username: username, password: password,
        tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
      return await persistConnection(name: name, config: config, environment: environment)
    } catch {
      setPersistenceError(error)
      return nil
    }
  }

  @discardableResult
  public func saveConnection(
    name: String,
    url: String,
    tls: Bool = false,
    tlsCAPath: String? = nil,
    sshTarget: String? = nil,
    environment: ConnectionEnvironment = .development
  ) async -> SavedConnectionMetadata? {
    do {
      let config = try Self.connectionConfig(
        url: url, tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
      return await persistConnection(name: name, config: config, environment: environment)
    } catch {
      setPersistenceError(error)
      return nil
    }
  }

  func savedConnectionPassword(id: SavedConnectionMetadata.ID) async -> String? {
    guard let metadata = savedConnections.first(where: { $0.id == id }) else {
      setPersistenceError(PersistenceError.savedConnectionNotFound)
      return nil
    }

    do {
      guard let secretReference = metadata.secretReference,
        let password = try await credentialStore.loadSecret(for: secretReference)
      else {
        throw PersistenceError.missingSecret
      }
      persistenceError = nil
      return password
    } catch {
      setPersistenceError(error)
      return nil
    }
  }

  @discardableResult
  func updateSavedConnection(
    id: SavedConnectionMetadata.ID,
    name: String,
    host: String, port: Int, database: String, username: String, password: String,
    tls: Bool = false, tlsCAPath: String? = nil, sshTarget: String? = nil,
    environment: ConnectionEnvironment = .development
  ) async -> SavedConnectionMetadata? {
    guard let existing = savedConnections.first(where: { $0.id == id }) else {
      setPersistenceError(PersistenceError.savedConnectionNotFound)
      return nil
    }

    do {
      let config = try Self.connectionConfig(
        host: host, port: port, database: database, username: username, password: password,
        tls: tls, tlsCAPath: tlsCAPath, sshTarget: sshTarget)
      return await persistConnection(
        name: name,
        config: config,
        environment: environment,
        replacing: existing
      )
    } catch {
      setPersistenceError(error)
      return nil
    }
  }

  public func connectSavedConnection(id: SavedConnectionMetadata.ID) async {
    let metadata: SavedConnectionMetadata?
    if let loaded = savedConnections.first(where: { $0.id == id }) {
      metadata = loaded
    } else {
      await loadSavedConnections()
      metadata = savedConnections.first { $0.id == id }
    }

    guard let metadata else {
      setError("Saved connection not found.")
      return
    }

    do {
      guard let secretReference = metadata.secretReference,
        let password = try await credentialStore.loadSecret(for: secretReference)
      else {
        throw PersistenceError.missingSecret
      }
      let config = try Self.connectionConfig(from: metadata, password: password)
      await open(
        config: config,
        label: metadata.connectionLabel,
        lastRequest: nil,
        savedConnection: metadata
      )
    } catch {
      connectionState = .disconnected
      setError(ErrorRedaction.redactCredentials(in: error))
    }
  }

  public func deleteSavedConnection(id: SavedConnectionMetadata.ID) async {
    do {
      let metadata = savedConnections.first { $0.id == id }
      try await savedConnectionStore.delete(id: id)
      if let secretReference = metadata?.secretReference {
        try await credentialStore.deleteSecret(for: secretReference)
      }
      if activeSavedConnection?.id == id {
        activeSavedConnection = nil
      }
      await loadSavedConnections()
      persistenceError = nil
    } catch {
      setPersistenceError(error)
    }
  }

  public func loadQueryHistory(limit: Int? = 50) async {
    do {
      queryHistory = try await queryHistoryStore.list(limit: limit)
      persistenceError = nil
    } catch {
      setPersistenceError(error)
    }
  }

  public func clearQueryHistory() async {
    do {
      try await queryHistoryStore.clear()
      queryHistory = []
      persistenceError = nil
    } catch {
      setPersistenceError(error)
    }
  }

  public func useHistoryEntry(_ entry: QueryHistoryEntry) {
    editorText = entry.sql
    clearError()
  }

  public func askInEnglish(_ prompt: String) async {
    guard let schema else {
      lastAIDraft = nil
      aiError = "Refresh schema before asking in English."
      return
    }

    isDraftingSQL = true
    aiError = nil
    defer { isDraftingSQL = false }

    do {
      let request = try AIQueryRequest(prompt: prompt, schemaIndex: SchemaIndex(schema: schema))
      let draft = try await aiQueryService.draftSQL(for: request)
      lastAIDraft = draft

      switch draft.status {
      case .ready:
        insertLastAIDraftIntoEditor()
      case .needsModel, .rejected:
        aiError = draft.explanation
      }
    } catch AIQueryValidationError.emptyPrompt {
      lastAIDraft = nil
      aiError = "Enter a question first."
    } catch AIQueryValidationError.missingSchema {
      lastAIDraft = nil
      aiError = "Refresh schema before asking in English."
    } catch {
      lastAIDraft = nil
      aiError = ErrorRedaction.redactCredentials(in: error)
    }
  }

  public func insertLastAIDraftIntoEditor() {
    guard lastAIDraft?.status == .ready else { return }
    let sql = lastAIDraft?.sql.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if sql.isEmpty {
      aiError = "The draft service returned an empty SQL draft."
    } else {
      editorText = sql
    }
  }

  public func disconnect() async {
    queryTask?.cancel()
    queryTask = nil
    activeQueryRunID = nil
    if let connector {
      await connector.close()
      try? await connector.shutdown()
    }
    connector = nil
    markDisconnected()
  }

  private func open(
    config: ConnectionConfig,
    label: String,
    lastRequest: ConnectionRequest?,
    savedConnection: SavedConnectionMetadata?
  ) async {
    if let activeConnector = connector {
      await activeConnector.close()
      try? await activeConnector.shutdown()
      connector = nil
    }
    markConnecting()
    do {
      let connector = PostgresConnector()
      try await connector.open(config: config)
      self.connector = connector
      lastConnectionRequest = lastRequest
      activeSavedConnection = savedConnection
      markConnected(label: label)
      await refreshSchema()
    } catch {
      connectionState = .disconnected
      activeSavedConnection = nil
      setError(ErrorRedaction.redactCredentials(in: error))
    }
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

  /// Renames a query tab. Blank names fall back to the tab's current title so
  /// a tab can never end up unlabeled.
  public func renameQueryTab(id: QueryTab.ID, to newTitle: String) {
    guard let index = queryTabs.firstIndex(where: { $0.id == id }) else { return }
    let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    queryTabs[index].title = trimmed
  }

  public func selectQueryTab(id: QueryTab.ID) {
    guard queryTabs.contains(where: { $0.id == id }) else { return }
    selectedQueryTabID = id
    clearError()
  }

  public func closeSelectedQueryTab() {
    guard let selectedQueryTabID else { return }
    closeQueryTab(id: selectedQueryTabID)
  }

  public func closeQueryTab(id: QueryTab.ID) {
    guard queryTabs.count > 1,
      let index = queryTabs.firstIndex(where: { $0.id == id })
    else { return }
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

  /// Sidebar click-through: insert the SELECT and run it immediately when
  /// connected. Disconnected sessions just get the inserted SQL so nothing
  /// errors while browsing a stale schema.
  public func insertAndRunSelect(for relation: DatabaseSchema.Relation) async {
    insertSelect(for: relation)
    guard isConnected, !isRunning else { return }
    await runCurrentQuery()
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
    let startedAt = ContinuousClock.now
    defer { finishQuery(if: runID) }
    do {
      let result = try await connector.execute(sql)
      try Task.checkCancellation()
      if activeQueryRunID == runID {
        setResult(result, for: queryTabID)
        await appendQueryHistory(sql: sql, result: result)
      }
    } catch is CancellationError {
      if activeQueryRunID == runID {
        setError("Query cancelled")
      }
    } catch {
      if activeQueryRunID == runID {
        let message = ErrorRedaction.redactCredentials(in: error)
        setError(message)
        await appendQueryHistory(
          sql: sql,
          elapsed: startedAt.duration(to: ContinuousClock.now),
          summary: message,
          succeeded: false
        )
      }
    }
  }

  /// The most recent parsed query plan, shown by the plan-tree sheet.
  public private(set) var lastQueryPlan: QueryPlan?
  /// Whether `lastQueryPlan` came from EXPLAIN ANALYZE (the query really ran).
  public private(set) var lastQueryPlanIsAnalyze = false
  public private(set) var isExplaining = false

  /// Runs EXPLAIN (FORMAT JSON) on the editor's SQL and parses the plan.
  /// With `analyze` the statement is EXPLAIN (ANALYZE, BUFFERS, ...) which
  /// actually executes the query; callers surface that in the UI copy.
  public func runExplain(analyze: Bool) async {
    let sql = editorText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sql.isEmpty else {
      setError("Enter a SQL query first.")
      return
    }
    guard let connector else {
      setError("Not connected")
      return
    }
    isExplaining = true
    defer { isExplaining = false }
    do {
      let statement = QueryPlan.explainStatement(for: sql, analyze: analyze)
      let result = try await connector.execute(statement)
      lastQueryPlan = try QueryPlan.parse(explainResult: result)
      lastQueryPlanIsAnalyze = analyze
      clearError()
    } catch {
      lastQueryPlan = nil
      setError(ErrorRedaction.redactCredentials(in: error))
    }
  }

  public func clearQueryPlan() {
    lastQueryPlan = nil
  }

  public func markConnecting() {
    connectionState = .connecting
    schema = nil
    schemaError = nil
    isLoadingSchema = false
    activeSavedConnection = nil
  }

  public func markConnected(label: String) {
    connectionState = .connected(label: label)
    lastError = nil
  }

  public func markDisconnected() {
    connectionState = .disconnected
    activeQueryRunID = nil
    queryTask = nil
    lastResult = nil
    schema = nil
    schemaError = nil
    isLoadingSchema = false
    isRunning = false
    activeSavedConnection = nil
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
    switch request.source {
    case .url(let url):
      await connect(
        url: url, tls: request.tls, tlsCAPath: request.tlsCAPath, sshTarget: request.sshTarget)
    case .fields(let host, let port, let database, let username, let password):
      await connect(
        host: host, port: port, database: database, username: username, password: password,
        tls: request.tls, tlsCAPath: request.tlsCAPath, sshTarget: request.sshTarget)
    }
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

  private func appendQueryHistory(sql: String, result: QueryResult) async {
    await appendQueryHistory(
      sql: sql,
      elapsed: result.elapsed,
      summary: Self.historySummary(for: result),
      succeeded: true
    )
  }

  private func appendQueryHistory(
    sql: String,
    elapsed: Duration,
    summary: String,
    succeeded: Bool
  ) async {
    guard queryHistoryEnabled, let connectionLabel else { return }
    let entry = QueryHistoryEntry(
      connectionName: activeSavedConnection?.name,
      connectionLabel: connectionLabel,
      environment: activeSavedConnection?.environment,
      sql: sql,
      elapsedMilliseconds: Self.elapsedMilliseconds(elapsed),
      summary: summary,
      succeeded: succeeded
    )
    do {
      try await queryHistoryStore.append(entry)
      await loadQueryHistory()
    } catch {
      setPersistenceError(error)
    }
  }

  private static func historySummary(for result: QueryResult) -> String {
    switch result.status {
    case .rows:
      return "\(result.rowCount) row\(result.rowCount == 1 ? "" : "s")"
    case .empty:
      return "No rows"
    case .command(let tag, let affected):
      return "\(tag): \(affected) row\(affected == 1 ? "" : "s") affected"
    }
  }

  private static func elapsedMilliseconds(_ duration: Duration) -> Int64 {
    let components = duration.components
    let seconds = Int64(clamping: components.seconds)
    let fractionalMilliseconds = Int64(components.attoseconds / 1_000_000_000_000_000)
    let (milliseconds, overflow) = seconds.multipliedReportingOverflow(by: 1_000)
    if overflow { return seconds < 0 ? Int64.min : Int64.max }
    let (total, addOverflow) = milliseconds.addingReportingOverflow(fractionalMilliseconds)
    if addOverflow { return milliseconds < 0 ? Int64.min : Int64.max }
    return total
  }

  private func persistConnection(
    name: String,
    config: ConnectionConfig,
    environment: ConnectionEnvironment,
    replacing existing: SavedConnectionMetadata? = nil
  ) async -> SavedConnectionMetadata? {
    do {
      let id = existing?.id ?? UUID()
      let secretReference = existing?.secretReference ?? Self.secretReference(for: id)
      let previousSecret: String?
      if existing != nil {
        previousSecret = try await credentialStore.loadSecret(for: secretReference)
      } else {
        previousSecret = nil
      }
      try await credentialStore.saveSecret(config.password, for: secretReference)

      let metadata = SavedConnectionMetadata(
        id: id,
        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
        host: config.host,
        port: config.port,
        database: config.database,
        username: config.username,
        tlsMode: Self.tlsModeLabel(for: config.tlsMode),
        pinnedRootCertificatePath: config.pinnedRootCertificatePath,
        sshTarget: config.sshConfig.map(Self.sshTargetLabel),
        environment: environment,
        secretReference: secretReference,
        integrityKeyReference: existing?.integrityKeyReference,
        integrityTag: existing?.integrityTag,
        createdAt: existing?.createdAt ?? Date(),
        updatedAt: Date()
      )
      do {
        try await savedConnectionStore.save(metadata)
      } catch {
        if let previousSecret {
          try? await credentialStore.saveSecret(previousSecret, for: secretReference)
        } else {
          try? await credentialStore.deleteSecret(for: secretReference)
        }
        throw error
      }
      await loadSavedConnections()
      selectedSavedConnectionID = metadata.id
      persistenceError = nil
      return metadata
    } catch {
      setPersistenceError(error)
      return nil
    }
  }

  private static func connectionLabel(for config: ConnectionConfig) -> String {
    "\(config.username)@\(config.host):\(config.port)/\(config.database)"
  }

  private func testConnection(_ makeConfig: () throws -> ConnectionConfig) async {
    guard !isTestingConnection else { return }
    isTestingConnection = true
    connectionTestMessage = nil
    connectionTestError = nil
    lastError = nil
    defer { isTestingConnection = false }

    do {
      let config = try makeConfig()
      try await connectionTester.test(config: config)
      connectionTestMessage = "Connection successful. SELECT 1 completed."
    } catch {
      connectionTestError = ErrorRedaction.redactCredentials(in: error)
    }
  }

  private static func connectionIdentity(_ metadata: SavedConnectionMetadata) -> String {
    connectionIdentity(
      host: metadata.host,
      port: metadata.port,
      database: metadata.database,
      username: metadata.username
    )
  }

  private static func connectionIdentity(_ config: ConnectionConfig) -> String {
    connectionIdentity(
      host: config.host,
      port: config.port,
      database: config.database,
      username: config.username
    )
  }

  private static func connectionIdentity(
    host: String,
    port: Int,
    database: String,
    username: String
  ) -> String {
    "\(username.lowercased())|\(host.lowercased())|\(port)|\(database.lowercased())"
  }

  private static func neonScanSummary(
    imported: Int,
    alreadySaved: Int,
    skipped: Int
  ) -> String {
    var sentences: [String] = []
    if imported == 0 {
      sentences.append("No new Neon databases found.")
    } else {
      sentences.append("Imported \(imported) Neon database\(imported == 1 ? "" : "s").")
    }
    if alreadySaved > 0 {
      sentences.append(
        "\(alreadySaved) \(alreadySaved == 1 ? "was" : "were") already saved."
      )
    }
    if skipped > 0 {
      sentences.append("Skipped \(skipped) unavailable resource\(skipped == 1 ? "" : "s").")
    }
    return sentences.joined(separator: " ")
  }

  private static func neonScanErrorMessage(_ error: Error) -> String {
    let message: String
    if let localizedError = error as? any LocalizedError,
      let description = localizedError.errorDescription
    {
      message = description
    } else {
      message = String(describing: error)
    }
    return ErrorRedaction.redactCredentials(in: message)
  }

  private static func connectionConfig(
    url: String,
    tls: Bool,
    tlsCAPath: String?,
    sshTarget: String?
  ) throws -> ConnectionConfig {
    let parsed = try ConnectionConfig(url: url)
    return ConnectionConfig(
      host: parsed.host,
      port: parsed.port,
      database: parsed.database,
      username: parsed.username,
      password: parsed.password,
      tlsMode: tls ? .verifyFull : parsed.tlsMode,
      pinnedRootCertificatePath: tlsCAPath?.nilIfBlank,
      sshConfig: try sshTarget?.nilIfBlank.map(Self.parseSSH)
    )
  }

  private static func connectionConfig(
    host: String,
    port: Int,
    database: String,
    username: String,
    password: String,
    tls: Bool,
    tlsCAPath: String?,
    sshTarget: String?
  ) throws -> ConnectionConfig {
    ConnectionConfig(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      tlsMode: tls ? .verifyFull : nil,
      pinnedRootCertificatePath: tlsCAPath?.nilIfBlank,
      sshConfig: try sshTarget?.nilIfBlank.map(Self.parseSSH)
    )
  }

  private static func connectionConfig(from metadata: SavedConnectionMetadata, password: String)
    throws -> ConnectionConfig
  {
    ConnectionConfig(
      host: metadata.host,
      port: metadata.port,
      database: metadata.database,
      username: metadata.username,
      password: password,
      tlsMode: try tlsMode(fromSavedLabel: metadata.tlsMode),
      pinnedRootCertificatePath: metadata.pinnedRootCertificatePath,
      sshConfig: try metadata.sshTarget?.nilIfBlank.map(Self.parseSSH)
    )
  }

  private static func secretReference(for id: SavedConnectionMetadata.ID) -> String {
    "lithepg.connection.\(id.uuidString.lowercased()).password"
  }

  private static func tlsModeLabel(for mode: ConnectionConfig.TLSMode) -> String {
    switch mode {
    case .disable: "disable"
    case .verifyFull: "verify-full"
    }
  }

  private static func tlsMode(fromSavedLabel label: String) throws -> ConnectionConfig.TLSMode {
    switch label {
    case "disable": .disable
    case "verify-full": .verifyFull
    default: throw PersistenceError.unsupportedTLSMode(label)
    }
  }

  private static func sshTargetLabel(for ssh: ConnectionConfig.SSHConfig) -> String {
    "\(ssh.user)@\(ssh.host):\(ssh.port)"
  }

  private func setPersistenceError(_ error: Error) {
    persistenceError = ErrorRedaction.redactCredentials(in: error)
  }

  private static func quotedIdentifier(_ identifier: String) -> String {
    let normalized = identifier.precomposedStringWithCanonicalMapping
    let safe = normalized.unicodeScalars.filter { scalar in
      scalar.value >= 0x20 && scalar.value != 0x7F
    }
    return "\"\(String(String.UnicodeScalarView(safe)).replacingOccurrences(of: "\"", with: "\"\""))\""
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

  private enum ConnectionSource {
    case url(String)
    case fields(host: String, port: Int, database: String, username: String, password: String)
  }

  private struct ConnectionRequest {
    let source: ConnectionSource
    let tls: Bool
    let tlsCAPath: String?
    let sshTarget: String?
  }

  private enum ConnectParseError: Error, CustomStringConvertible {
    case invalidSSH
    var description: String { "SSH target must be user@host[:port]" }
  }

  private enum PersistenceError: Error, CustomStringConvertible {
    case missingSecret
    case savedConnectionNotFound
    case unsupportedTLSMode(String)

    var description: String {
      switch self {
      case .missingSecret:
        "Saved connection password is missing from credential storage."
      case .savedConnectionNotFound:
        "Saved connection not found."
      case .unsupportedTLSMode(let label):
        "Saved connection has unsupported TLS mode: \(label)"
      }
    }
  }
}

extension String {
  fileprivate var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
