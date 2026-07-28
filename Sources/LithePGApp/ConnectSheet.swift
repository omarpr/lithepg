import AppKit
import LithePGCore
import SwiftUI
import UniformTypeIdentifiers

struct ConnectSheet: View {
  enum InputMode: String, CaseIterable {
    case url = "Paste connection string"
    case fields = "Enter details"
  }

  struct DiscoveredInstance: Identifiable {
    let port: Int
    var id: Int { port }
    var label: String { "localhost:\(port)" }
  }

  @Bindable var state: AppState
  let closeAction: (() -> Void)?
  @State private var inputMode: InputMode = Self.initialDisplayURL().isEmpty ? .fields : .url
  @State private var url: String = Self.initialDisplayURL()
  @State private var sensitivePrefilledURL: String? = Self.initialSensitiveURL()
  @State private var fieldHost: String = ""
  @State private var fieldPort: String = "5432"
  @State private var fieldDatabase: String = ""
  @State private var fieldUsername: String = ""
  @State private var fieldPassword: String = ""
  @State private var discoveredInstances: [DiscoveredInstance] = []
  @State private var tlsMode: ConnectionConfig.TLSMode = Self.initialTLSMode()
  @State private var tlsCAPath: String =
    ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] ?? ""
  @State private var useSSH = ProcessInfo.processInfo.environment["POSTGRES_SSH"] != nil
  @State private var sshTarget: String = ProcessInfo.processInfo.environment["POSTGRES_SSH"] ?? ""
  @State private var saveConnection: Bool
  @State private var connectionName = ""
  @State private var lastAutoConnectionName: String?
  @State private var environment: ConnectionEnvironment = .development
  @State private var showingCAImporter = false
  @State private var pendingDelete: SavedConnectionMetadata?
  @State private var editingConnection: SavedConnectionMetadata?
  @State private var savedConnectionsExpanded = true
  @State private var savedConnectionsPage = 0
  @FocusState private var urlFieldFocused: Bool

  init(
    state: AppState,
    closeAction: (() -> Void)? = nil,
    saveByDefault: Bool = false
  ) {
    self.state = state
    self.closeAction = closeAction
    _saveConnection = State(initialValue: saveByDefault)
  }

  private var neonProfile: NeonConnectionProfile? {
    guard inputMode == .url else { return nil }
    return NeonConnectionProfile.detect(url: effectiveURL)
  }

  private var neonHint: ConnectSheetPresentation.ProviderHint? {
    ConnectSheetPresentation.neonHint(for: neonProfile)
  }

  private var encryptionWarning: String? {
    guard !useSSH else { return nil }
    let host: String
    if inputMode == .url {
      guard let config = try? ConnectionConfig(url: effectiveURL) else { return nil }
      host = config.host
    } else {
      host = fieldHost
    }
    return ConnectSheetPresentation.encryptionWarning(mode: tlsMode, host: host)
  }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          Image(systemName: "cylinder.split.1x2")
            .font(.title)
            .foregroundStyle(.tint)
          VStack(alignment: .leading) {
            Text("Connect to PostgreSQL")
              .font(.title2.bold())
            Text("Connection details stay on this Mac; passwords remain in Keychain.")
              .foregroundStyle(.secondary)
          }
          Spacer()
          if let closeAction {
            Button(action: closeAction) {
              Label("Close connection window", systemImage: "xmark.circle.fill")
                .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .font(.title3)
            .foregroundStyle(.secondary)
            .buttonAffordance("Close connection window")
            .accessibilityIdentifier("close-connection-form-header-button")
          }
        }
      }

      if !state.savedConnections.isEmpty {
        Section {
          if savedConnectionsExpanded {
            ForEach(
              SavedConnectionPagination.page(
                of: state.savedConnections,
                index: savedConnectionsPage
              )
            ) { connection in
              HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                  Text(connection.name)
                    .font(.subheadline.bold())
                  Text(connection.connectionLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text(connection.environment.displayName)
                  .font(.caption2.bold())
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(environmentColor(connection.environment).opacity(0.16), in: Capsule())
                  .foregroundStyle(environmentColor(connection.environment))
                Button("Connect") {
                  Task {
                    await state.connectSavedConnection(id: connection.id)
                    if state.isConnected { closeAction?() }
                  }
                }
                .buttonStyle(.bordered)
                .buttonAffordance("Connect to \(connection.name)")

                Button {
                  editingConnection = connection
                } label: {
                  Label("Edit saved connection", systemImage: "pencil")
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .buttonAffordance("Edit saved connection \(connection.name)")
                .accessibilityIdentifier("edit-saved-connection-\(connection.id.uuidString)")

                Button(role: .destructive) {
                  pendingDelete = connection
                } label: {
                  Label("Delete saved connection", systemImage: "trash")
                    .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .buttonAffordance("Delete saved connection \(connection.name)")
              }
            }

            SavedConnectionPager(
              page: $savedConnectionsPage,
              itemCount: state.savedConnections.count,
              accessibilityPrefix: "connect-sheet-connections"
            )
          }
        } header: {
          HStack {
            Text("Saved connections")
            Spacer()
            Button {
              withAnimation(.easeInOut(duration: 0.15)) {
                savedConnectionsExpanded.toggle()
              }
            } label: {
              Label(
                savedConnectionsExpanded ? "Collapse connections" : "Expand connections",
                systemImage: savedConnectionsExpanded ? "chevron.up" : "chevron.down"
              )
              .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .buttonAffordance(savedConnectionsExpanded ? "Collapse connections" : "Expand connections")
            .accessibilityIdentifier("toggle-saved-connections-section-button")
          }
        }
      }

      Section("Neon") {
        NeonScannerButton(state: state)
      }

      if !discoveredInstances.isEmpty {
        Section("Local servers") {
          ForEach(discoveredInstances) { instance in
            HStack {
              Label(instance.label, systemImage: "desktopcomputer")
              Spacer()
              Button("Connect") {
                Task { await connectDiscovered(instance) }
              }
              .buttonStyle(.bordered)
              .buttonAffordance("Connect to \(instance.label)")
              .disabled(state.connectionState == .connecting)
            }
          }
        }
      }

      Section {
        Picker("Input mode", selection: $inputMode) {
          ForEach(InputMode.allCases, id: \.self) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .controlAffordance("Choose how to enter the PostgreSQL connection details")

        if inputMode == .url {
          TextField(
            ConnectSheetPresentation.requiredFieldLabel("Connection string"),
            text: $url,
            // The example vanishes on click (focus), not just on first keystroke.
            prompt: urlFieldFocused ? nil : Text("postgres://user:***@host:5432/database")
          )
          .focused($urlFieldFocused)
          .accessibilityIdentifier("postgres-url-field")
          .onChange(of: url) { _, newValue in
            if newValue != Self.redactedURLForDisplay(sensitivePrefilledURL) {
              sensitivePrefilledURL = nil
            }
            tlsMode = ConnectSheetPresentation.preselectedTLSMode(forURL: effectiveURL)
            applyNeonConnectionNameSuggestion()
          }
          if let neonHint {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(neonHint.title)
                  .font(.caption.bold())
                Text(neonHint.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
                if let note = neonHint.note {
                  Text(note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("neon-hint-note")
                }
              }
            } icon: {
              Image(systemName: "sparkle.magnifyingglass")
            }
            .foregroundStyle(.green)
            .accessibilityIdentifier("neon-connection-hint")
          }
        } else {
          TextField(ConnectSheetPresentation.requiredFieldLabel("Host"), text: $fieldHost)
            .accessibilityIdentifier("field-host")
          TextField("Port", text: $fieldPort)
            .accessibilityIdentifier("field-port")
          TextField(ConnectSheetPresentation.requiredFieldLabel("Database"), text: $fieldDatabase)
            .accessibilityIdentifier("field-database")
          TextField(ConnectSheetPresentation.requiredFieldLabel("Username"), text: $fieldUsername)
            .accessibilityIdentifier("field-username")
          SecureField("Password", text: $fieldPassword)
            .accessibilityIdentifier("field-password")
        }

        Text("* Required")
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("required-fields-legend")
      }

      Section {
        Picker("Encryption", selection: $tlsMode) {
          ForEach(ConnectSheetPresentation.tlsModeOrder, id: \.self) { mode in
            Text(ConnectSheetPresentation.tlsModeTitle(mode)).tag(mode)
          }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("picker-tls-mode")
        .controlAffordance("Choose how much the connection to the server is protected")
        .onChange(of: tlsMode) { _, mode in
          if mode != .disable { useSSH = false }
        }

        Text(ConnectSheetPresentation.tlsModeCaption(tlsMode))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("tls-mode-caption")

        if let encryptionWarning {
          Label(encryptionWarning, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if ConnectSheetPresentation.showsCACertificateField(mode: tlsMode) {
          HStack {
            TextField("CA certificate path", text: $tlsCAPath)
            Button("Choose…") {
              showingCAImporter = true
            }
            .buttonAffordance("Choose a CA certificate file")
          }
        }

        Toggle("Use an SSH tunnel", isOn: $useSSH)
          .controlAffordance(
            tlsMode == .disable
              ? "Connect through an SSH tunnel"
              : "Set encryption to Off before enabling an SSH tunnel"
          )
          .disabled(tlsMode != .disable)
          .onChange(of: useSSH) { _, enabled in
            if enabled { tlsMode = .disable }
          }
        if useSSH && tlsMode == .disable {
          TextField(
            ConnectSheetPresentation.requiredFieldLabel("SSH target"),
            text: $sshTarget,
            prompt: Text("user@host[:port]")
          )
        }
      }

      Section {
        Toggle("Save this connection", isOn: $saveConnection)
          .controlAffordance("Store connection metadata locally and keep its password in Keychain")
          .onChange(of: saveConnection) { _, enabled in
            if enabled { applyNeonConnectionNameSuggestion() }
          }
        if saveConnection {
          TextField(
            "Connection name",
            text: $connectionName,
            prompt: Text(defaultConnectionName)
          )
          Picker("Environment", selection: $environment) {
            ForEach(ConnectionEnvironment.allCases) { environment in
              Text(environment.displayName).tag(environment)
            }
          }
          .pickerStyle(.segmented)
          .controlAffordance("Classify the connection so its environment is visible in the workspace")
        }
      }

      if let error = state.lastError ?? state.persistenceError {
        Section {
          ErrorBanner(
            message: error,
            stepDown: state.tlsStepDownAvailable
              ? { Task { await state.retryWithEncryptionOnly() } }
              : nil
          )
        }
      }

      if let message = state.connectionTestMessage {
        Section {
          Label(message, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
            .accessibilityIdentifier("connection-test-success")
        }
      } else if let error = state.connectionTestError {
        Section {
          ErrorBanner(message: error)
            .accessibilityIdentifier("connection-test-error")
        }
      }

      Section {
        HStack {
          if let closeAction {
            Button("Cancel", action: closeAction)
              .buttonStyle(.bordered)
              .keyboardShortcut(.cancelAction)
              .buttonAffordance("Close without connecting")
              .accessibilityIdentifier("close-connection-form-button")
          } else {
            Button {
              NSApplication.shared.terminate(nil)
            } label: {
              Label("Quit LithePG", systemImage: "power")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut("q", modifiers: .command)
            .buttonAffordance("Quit LithePG (⌘Q)")
            .accessibilityIdentifier("quit-application-button")
          }

          Spacer()
          Button {
            Task { await testConnection() }
          } label: {
            if state.isTestingConnection {
              HStack(spacing: 6) {
                ProgressView()
                  .controlSize(.small)
                Text("Testing")
              }
            } else {
              Text("Test connection")
            }
          }
          .buttonStyle(.bordered)
          .buttonAffordance("Test this connection without opening the workspace")
          .accessibilityIdentifier("test-connection-button")
          .disabled(testConnectionDisabled)

          Button {
            Task { await connectAndMaybeSave() }
          } label: {
            if state.connectionState == .connecting {
              ProgressView()
                .controlSize(.small)
            } else {
              Text(ConnectSheetPresentation.primaryActionTitle(saveConnection: saveConnection))
            }
          }
          .accessibilityIdentifier("connect-button")
          .accessibilityLabel(
            state.connectionState == .connecting
              ? "Connecting"
              : ConnectSheetPresentation.primaryActionTitle(saveConnection: saveConnection)
          )
          .buttonStyle(.borderedProminent)
          .buttonAffordance(saveConnection ? "Save this connection locally, then connect" : "Connect without saving")
          .keyboardShortcut(.defaultAction)
          .disabled(connectDisabled)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 560)
    .onChange(of: testInputSignature) { _, _ in
      state.clearConnectionTestResult()
    }
    .onChange(of: state.savedConnections.count) { _, count in
      savedConnectionsPage = SavedConnectionPagination.normalizedPage(
        savedConnectionsPage,
        itemCount: count
      )
    }
    .task {
      await state.loadSavedConnections()
      state.refreshNeonCLIAvailability()
      discoveredInstances = Self.scanLocalInstances()
    }
    .confirmationDialog(
      "Delete saved connection?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }
      ),
      presenting: pendingDelete
    ) { connection in
      Button("Delete \(connection.name)", role: .destructive) {
        Task {
          await state.deleteSavedConnection(id: connection.id)
          pendingDelete = nil
        }
      }
      Button("Cancel", role: .cancel) {
        pendingDelete = nil
      }
    } message: { connection in
      Text(
        "This removes local metadata and its credential-store secret reference. It does not touch the database."
      )
    }
    .sheet(item: $editingConnection) { connection in
      SavedConnectionEditor(state: state, connection: connection)
    }
    .fileImporter(
      isPresented: $showingCAImporter,
      allowedContentTypes: Self.certificateTypes,
      allowsMultipleSelection: false
    ) { result in
      if case .success(let urls) = result, let selected = urls.first {
        tlsCAPath = selected.path(percentEncoded: false)
      }
    }
  }

  private var connectDisabled: Bool {
    ConnectSheetPresentation.primaryActionDisabled(
      connectionInputEmpty: connectionInputEmpty,
      requiredSupplementalInputEmpty: useSSH
        && sshTarget.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
      isConnecting: state.connectionState == .connecting,
      isTestingConnection: state.isTestingConnection
    )
  }

  private var testConnectionDisabled: Bool {
    connectionInputEmpty
      || state.connectionState == .connecting
      || state.isTestingConnection
  }

  private var connectionInputEmpty: Bool {
    let inputEmpty: Bool
    if inputMode == .url {
      inputEmpty = effectiveURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } else {
      inputEmpty =
        fieldHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || fieldDatabase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || fieldUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return inputEmpty
  }

  private var testInputSignature: String {
    [
      inputMode.rawValue, effectiveURL, fieldHost, fieldPort, fieldDatabase,
      fieldUsername, fieldPassword, String(describing: tlsMode), tlsCAPath, String(useSSH), sshTarget,
    ].joined(separator: "\u{1F}")
  }

  private var effectiveURL: String {
    if let sensitivePrefilledURL, url == Self.redactedURLForDisplay(sensitivePrefilledURL) {
      return sensitivePrefilledURL
    }
    // Pasted strings arrive wrapped in quotes, psql commands, env assignments
    // or trailing newlines; sanitize before parsing so console copies just work.
    return ConnectionStringSanitizer.sanitize(url)
  }

  private var defaultConnectionName: String {
    if let suggestedName = neonProfile?.suggestedName {
      return suggestedName
    }
    return ConnectSheetPresentation.savedConnectionName(
      enteredName: "",
      inputMode: inputMode,
      url: effectiveURL,
      fieldHost: fieldHost,
      fieldDatabase: fieldDatabase
    )
  }

  private var savedConnectionName: String {
    return ConnectSheetPresentation.savedConnectionName(
      enteredName: connectionName,
      inputMode: inputMode,
      url: effectiveURL,
      fieldHost: fieldHost,
      fieldDatabase: fieldDatabase
    )
  }

  private func applyNeonConnectionNameSuggestion() {
    let nextSuggestion = neonProfile?.suggestedName
    let nextName = ConnectSheetPresentation.connectionName(
      current: connectionName,
      previousSuggestion: lastAutoConnectionName,
      nextSuggestion: saveConnection ? nextSuggestion : nil
    )
    if nextName != connectionName {
      connectionName = nextName
    }
    lastAutoConnectionName = nextName == nextSuggestion ? nextSuggestion : nil
  }

  private func connectAndMaybeSave() async {
    state.clearConnectionTestResult()
    let tlsCA = tlsMode == .verifyFull ? tlsCAPath : nil
    let ssh = useSSH && tlsMode == .disable ? sshTarget : nil

    if inputMode == .url {
      await state.connect(url: effectiveURL, tlsMode: tlsMode, tlsCAPath: tlsCA, sshTarget: ssh)
    } else {
      let port = Int(fieldPort) ?? 5432
      await state.connect(
        host: fieldHost, port: port, database: fieldDatabase,
        username: fieldUsername, password: fieldPassword,
        tlsMode: tlsMode, tlsCAPath: tlsCA, sshTarget: ssh)
    }

    guard state.isConnected else { return }
    guard saveConnection else {
      closeAction?()
      return
    }

    let metadata: SavedConnectionMetadata?
    if inputMode == .url {
      metadata = await state.saveConnection(
        name: savedConnectionName, url: effectiveURL, tlsMode: tlsMode, tlsCAPath: tlsCA,
        sshTarget: ssh, environment: environment)
    } else {
      let port = Int(fieldPort) ?? 5432
      metadata = await state.saveConnection(
        name: savedConnectionName,
        host: fieldHost, port: port, database: fieldDatabase,
        username: fieldUsername, password: fieldPassword,
        tlsMode: tlsMode, tlsCAPath: tlsCA, sshTarget: ssh, environment: environment)
    }

    if let metadata {
      state.activeSavedConnection = metadata
    }
    closeAction?()
  }

  private func testConnection() async {
    let tlsCA = tlsMode == .verifyFull ? tlsCAPath : nil
    let ssh = useSSH && tlsMode == .disable ? sshTarget : nil

    if inputMode == .url {
      await state.testConnection(
        url: effectiveURL, tlsMode: tlsMode, tlsCAPath: tlsCA, sshTarget: ssh)
    } else {
      await state.testConnection(
        host: fieldHost, port: Int(fieldPort) ?? 5432, database: fieldDatabase,
        username: fieldUsername, password: fieldPassword,
        tlsMode: tlsMode, tlsCAPath: tlsCA, sshTarget: ssh)
    }
  }

  private func connectDiscovered(_ instance: DiscoveredInstance) async {
    let username = NSUserName()
    await state.connect(
      host: "localhost", port: instance.port, database: "postgres",
      username: username, password: "")
    guard !state.isConnected else {
      closeAction?()
      return
    }
    inputMode = .fields
    fieldHost = "localhost"
    fieldPort = String(instance.port)
    fieldDatabase = "postgres"
    fieldUsername = username
    fieldPassword = ""
  }

  private static func scanLocalInstances() -> [DiscoveredInstance] {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: "/tmp") else { return [] }
    return entries.compactMap { name -> DiscoveredInstance? in
      guard name.hasPrefix(".s.PGSQL."), !name.hasSuffix(".lock") else { return nil }
      let portString = String(name.dropFirst(".s.PGSQL.".count))
      guard let port = Int(portString), (1...65535).contains(port) else { return nil }
      return DiscoveredInstance(port: port)
    }
    .sorted { $0.port < $1.port }
  }

  private func environmentColor(_ environment: ConnectionEnvironment) -> Color {
    switch environment {
    case .development: .green
    case .staging: .orange
    case .production: .red
    case .custom: .blue
    }
  }

  private static func initialTLSMode() -> ConnectionConfig.TLSMode {
    if ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] != nil { return .verifyFull }
    return ConnectSheetPresentation.preselectedTLSMode(
      forURL: ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? "")
  }

  private static func initialSensitiveURL() -> String? {
    let raw = ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? ""
    guard redactedURLForDisplay(raw) != raw else { return nil }
    return raw
  }

  private static func initialDisplayURL() -> String {
    redactedURLForDisplay(ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? "")
  }

  static func redactedURLForDisplay(_ raw: String?) -> String {
    guard let raw else { return "" }
    return ErrorRedaction.redactCredentials(in: raw)
  }

  private static func isLoopback(host: String) -> Bool {
    ConnectionConfig.isLoopbackHost(host)
  }

  private static var certificateTypes: [UTType] {
    [
      UTType(filenameExtension: "pem"),
      UTType(filenameExtension: "crt"),
      .item,
    ].compactMap { $0 }
  }
}

enum ConnectSheetPresentation {
  struct ProviderHint: Equatable {
    let title: String
    let detail: String
    /// Explains a preselection that differs from what the URL literally asked for. Nil when
    /// nothing was overridden, so the hint stays quiet in the ordinary case.
    var note: String? = nil
  }

  /// Weakest to strongest, so the picker reads as an escalating scale.
  static let tlsModeOrder: [ConnectionConfig.TLSMode] = [.disable, .prefer, .require, .verifyFull]

  static func tlsModeTitle(_ mode: ConnectionConfig.TLSMode) -> String {
    switch mode {
    case .disable: "Off"
    case .prefer: "Prefer"
    case .require: "Encrypt only"
    case .verifyFull: "Verify"
    }
  }

  static func tlsModeCaption(_ mode: ConnectionConfig.TLSMode) -> String {
    switch mode {
    case .disable: "No encryption."
    case .prefer: "Encrypt if the server supports it."
    case .require: "Encrypts, but does not check the server certificate."
    case .verifyFull: "Checks the server certificate and hostname. Uses PostgreSQL verify-full."
    }
  }

  /// A pinned CA only feeds certificate verification, which no other mode performs.
  static func showsCACertificateField(mode: ConnectionConfig.TLSMode) -> Bool {
    mode == .verifyFull
  }

  /// Warns when a remote connection may travel in cleartext. Returns nil for loopback hosts,
  /// for a host that is not yet known, and for modes that always encrypt.
  static func encryptionWarning(mode: ConnectionConfig.TLSMode, host: String) -> String? {
    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !host.isEmpty, !ConnectionConfig.isLoopbackHost(host) else { return nil }
    switch mode {
    case .disable:
      return "Cleartext remote connection. Turn on encryption before connecting outside localhost."
    case .prefer:
      return "May fall back to cleartext if the server refuses TLS."
    case .require, .verifyFull:
      return nil
    }
  }

  static func neonHint(for profile: NeonConnectionProfile?) -> ProviderHint? {
    guard let profile else { return nil }
    let path = profile.isPooled ? "Pooled" : "Direct"
    let note: String?
    if profile.recommendedTLSMode != profile.tlsMode {
      note = """
        Neon certificates are publicly trusted, so Verify is selected even though the URL asks \
        for \(sslModeName(profile.tlsMode)).
        """
    } else {
      note = nil
    }
    return ProviderHint(
      title: "Neon connection detected",
      detail: "Database \(profile.database) · User \(profile.username) · \(path)",
      note: note
    )
  }

  /// Preselects the encryption picker for a pasted URL.
  ///
  /// A recognized provider whose certificates are known to verify takes precedence over the
  /// literal `sslmode`, so a Neon URL saying `require` still preselects Verify. Falls back to
  /// verify-full for an unparseable URL, so a typo never silently lands the user on a weaker
  /// mode than the remote-host default.
  static func preselectedTLSMode(forURL url: String) -> ConnectionConfig.TLSMode {
    if let recommended = NeonConnectionProfile.recommendedTLSMode(forURL: url) {
      return recommended
    }
    return (try? ConnectionConfig(url: url))?.tlsMode ?? .verifyFull
  }

  /// The PostgreSQL `sslmode` spelling, for quoting back what a pasted URL actually said.
  private static func sslModeName(_ mode: ConnectionConfig.TLSMode) -> String {
    switch mode {
    case .disable: "disable"
    case .prefer: "prefer"
    case .require: "require"
    case .verifyFull: "verify-full"
    }
  }

  static func connectionName(
    current: String,
    previousSuggestion: String?,
    nextSuggestion: String?
  ) -> String {
    guard let nextSuggestion else { return current }
    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || current == previousSuggestion {
      return nextSuggestion
    }
    return current
  }

  static func primaryActionTitle(saveConnection: Bool) -> String {
    saveConnection ? "Save & Connect" : "Connect"
  }

  static func primaryActionDisabled(
    connectionInputEmpty: Bool,
    requiredSupplementalInputEmpty: Bool = false,
    isConnecting: Bool,
    isTestingConnection: Bool
  ) -> Bool {
    connectionInputEmpty || requiredSupplementalInputEmpty || isConnecting || isTestingConnection
  }

  static func requiredFieldLabel(_ label: String) -> String {
    "\(label) *"
  }

  static func savedConnectionName(
    enteredName: String,
    host: String,
    database: String
  ) -> String {
    let enteredName = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
    if !enteredName.isEmpty { return enteredName }

    let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
    let database = database.trimmingCharacters(in: .whitespacesAndNewlines)
    switch (host.isEmpty, database.isEmpty) {
    case (false, false):
      return "\(host) · \(database)"
    case (false, true):
      return host
    case (true, false):
      return database
    case (true, true):
      return "Postgres connection"
    }
  }

  static func savedConnectionName(
    enteredName: String,
    inputMode: ConnectSheet.InputMode,
    url: String,
    fieldHost: String,
    fieldDatabase: String
  ) -> String {
    switch inputMode {
    case .url:
      let config = try? ConnectionConfig(url: url)
      return savedConnectionName(
        enteredName: enteredName,
        host: config?.host ?? "",
        database: config?.database ?? ""
      )
    case .fields:
      return savedConnectionName(
        enteredName: enteredName,
        host: fieldHost,
        database: fieldDatabase
      )
    }
  }
}
