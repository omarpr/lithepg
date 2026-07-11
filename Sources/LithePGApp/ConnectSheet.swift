import SwiftUI
import LithePGCore
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
  @State private var inputMode: InputMode = Self.initialDisplayURL().isEmpty ? .fields : .url
  @State private var url: String = Self.initialDisplayURL()
  @State private var sensitivePrefilledURL: String? = Self.initialSensitiveURL()
  @State private var fieldHost: String = ""
  @State private var fieldPort: String = "5432"
  @State private var fieldDatabase: String = ""
  @State private var fieldUsername: String = ""
  @State private var fieldPassword: String = ""
  @State private var discoveredInstances: [DiscoveredInstance] = []
  @State private var tls = Self.initialTLSPreference()
  @State private var tlsCAPath: String =
    ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] ?? ""
  @State private var useSSH = ProcessInfo.processInfo.environment["POSTGRES_SSH"] != nil
  @State private var sshTarget: String = ProcessInfo.processInfo.environment["POSTGRES_SSH"] ?? ""
  @State private var saveConnection = false
  @State private var connectionName = ""
  @State private var lastAutoConnectionName: String?
  @State private var environment: ConnectionEnvironment = .development
  @State private var showingCAImporter = false
  @State private var pendingDelete: SavedConnectionMetadata?
  @FocusState private var urlFieldFocused: Bool

  private var neonProfile: NeonConnectionProfile? {
    guard inputMode == .url else { return nil }
    return NeonConnectionProfile.detect(url: effectiveURL)
  }

  private var neonHint: ConnectSheetPresentation.ProviderHint? {
    ConnectSheetPresentation.neonHint(for: neonProfile)
  }

  private var cleartextWarning: String? {
    guard !tls, !useSSH else { return nil }
    let host: String
    if inputMode == .url {
      guard let config = try? ConnectionConfig(url: effectiveURL), config.tlsMode == .disable else {
        return nil
      }
      host = config.host
    } else {
      host = fieldHost
    }
    guard !host.isEmpty, !Self.isLoopback(host: host) else { return nil }
    return "Cleartext remote connection. Enable TLS before connecting outside localhost."
  }

  var body: some View {
    Form {
      Section {
        HStack(spacing: 10) {
          Image(systemName: "cylinder.split.1x2")
            .font(.title)
            .foregroundStyle(.tint)
          VStack(alignment: .leading) {
            Text("Connect to Postgres")
              .font(.title2.bold())
            Text("Save metadata locally; passwords go through the credential store.")
              .foregroundStyle(.secondary)
          }
        }
      }

      if !state.savedConnections.isEmpty {
        Section("Saved connections") {
          ForEach(state.savedConnections) { connection in
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
                Task { await state.connectSavedConnection(id: connection.id) }
              }
              .buttonStyle(.bordered)

              Button(role: .destructive) {
                pendingDelete = connection
              } label: {
                Label("Delete saved connection", systemImage: "trash")
                  .labelStyle(.iconOnly)
              }
              .buttonStyle(.borderless)
              .help("Delete saved connection")
            }
          }
        }
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

        if inputMode == .url {
          TextField(
            "",
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
              tls = Self.defaultTLSPreference(for: effectiveURL)
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
              }
            } icon: {
              Image(systemName: "sparkle.magnifyingglass")
            }
            .foregroundStyle(.green)
            .accessibilityIdentifier("neon-connection-hint")
          }
        } else {
          TextField("Host", text: $fieldHost)
            .accessibilityIdentifier("field-host")
          TextField("Port", text: $fieldPort)
            .accessibilityIdentifier("field-port")
          TextField("Database", text: $fieldDatabase)
            .accessibilityIdentifier("field-database")
          TextField("Username", text: $fieldUsername)
            .accessibilityIdentifier("field-username")
          SecureField("Password", text: $fieldPassword)
            .accessibilityIdentifier("field-password")
        }
      }

      Section {
        Toggle("TLS verify-full", isOn: $tls)
          .onChange(of: tls) { _, enabled in
            if enabled { useSSH = false }
          }
        if let cleartextWarning {
          Label(cleartextWarning, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
        if tls {
          HStack {
            TextField("CA certificate path", text: $tlsCAPath)
            Button("Choose…") {
              showingCAImporter = true
            }
          }
        }

        Toggle("SSH tunnel", isOn: $useSSH)
          .disabled(tls)
          .onChange(of: useSSH) { _, enabled in
            if enabled { tls = false }
          }
        if useSSH && !tls {
          TextField("user@host[:port]", text: $sshTarget)
        }
      }

      Section {
        Toggle("Save this connection", isOn: $saveConnection)
          .onChange(of: saveConnection) { _, enabled in
            if enabled { applyNeonConnectionNameSuggestion() }
          }
        if saveConnection {
          TextField("Connection name", text: $connectionName)
          Picker("Environment", selection: $environment) {
            ForEach(ConnectionEnvironment.allCases) { environment in
              Text(environment.displayName).tag(environment)
            }
          }
          .pickerStyle(.segmented)
        }
      }

      if let error = state.lastError ?? state.persistenceError {
        Section {
          ErrorBanner(message: error)
        }
      }

      Section {
        HStack {
          Spacer()
          Button {
            Task { await connectAndMaybeSave() }
          } label: {
            if state.connectionState == .connecting {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Connect")
            }
          }
          .accessibilityIdentifier("connect-button")
          .keyboardShortcut(.defaultAction)
          .disabled(connectDisabled)
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 560)
    .task {
      await state.loadSavedConnections()
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
    let inputEmpty: Bool
    if inputMode == .url {
      inputEmpty = effectiveURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    } else {
      inputEmpty = fieldHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || fieldDatabase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || fieldUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    return inputEmpty
      || state.connectionState == .connecting
      || (saveConnection && connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private var effectiveURL: String {
    if let sensitivePrefilledURL, url == Self.redactedURLForDisplay(sensitivePrefilledURL) {
      return sensitivePrefilledURL
    }
    // Pasted strings arrive wrapped in quotes, psql commands, env assignments
    // or trailing newlines; sanitize before parsing so console copies just work.
    return ConnectionStringSanitizer.sanitize(url)
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
    let tlsCA = tls ? tlsCAPath : nil
    let ssh = useSSH && !tls ? sshTarget : nil

    if inputMode == .url {
      await state.connect(url: effectiveURL, tls: tls, tlsCAPath: tlsCA, sshTarget: ssh)
    } else {
      let port = Int(fieldPort) ?? 5432
      await state.connect(
        host: fieldHost, port: port, database: fieldDatabase,
        username: fieldUsername, password: fieldPassword,
        tls: tls, tlsCAPath: tlsCA, sshTarget: ssh)
    }

    guard saveConnection, state.isConnected else { return }

    let metadata: SavedConnectionMetadata?
    if inputMode == .url {
      metadata = await state.saveConnection(
        name: connectionName, url: effectiveURL, tls: tls, tlsCAPath: tlsCA,
        sshTarget: ssh, environment: environment)
    } else {
      let port = Int(fieldPort) ?? 5432
      metadata = await state.saveConnection(
        name: connectionName,
        host: fieldHost, port: port, database: fieldDatabase,
        username: fieldUsername, password: fieldPassword,
        tls: tls, tlsCAPath: tlsCA, sshTarget: ssh, environment: environment)
    }

    if let metadata {
      state.activeSavedConnection = metadata
    }
  }

  private func connectDiscovered(_ instance: DiscoveredInstance) async {
    let username = NSUserName()
    await state.connect(
      host: "localhost", port: instance.port, database: "postgres",
      username: username, password: "")
    guard !state.isConnected else { return }
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

  private static func initialTLSPreference() -> Bool {
    if ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] != nil { return true }
    return defaultTLSPreference(for: ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? "")
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

  private static func defaultTLSPreference(for url: String) -> Bool {
    guard let config = try? ConnectionConfig(url: url) else { return false }
    return config.tlsMode == .verifyFull
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
  }

  static func neonHint(for profile: NeonConnectionProfile?) -> ProviderHint? {
    guard let profile else { return nil }
    let path = profile.isPooled ? "Pooled" : "Direct"
    return ProviderHint(
      title: "Neon connection detected",
      detail: "Database \(profile.database) · User \(profile.username) · \(path)"
    )
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
}
