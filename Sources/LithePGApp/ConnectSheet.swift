import SwiftUI
import LithePGCore
import UniformTypeIdentifiers

struct ConnectSheet: View {
  @Bindable var state: AppState
  @State private var url: String = Self.initialDisplayURL()
  @State private var sensitivePrefilledURL: String? = Self.initialSensitiveURL()
  @State private var tls = Self.initialTLSPreference()
  @State private var tlsCAPath: String =
    ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] ?? ""
  @State private var useSSH = ProcessInfo.processInfo.environment["POSTGRES_SSH"] != nil
  @State private var sshTarget: String = ProcessInfo.processInfo.environment["POSTGRES_SSH"] ?? ""
  @State private var saveConnection = false
  @State private var connectionName = ""
  @State private var environment: ConnectionEnvironment = .development
  @State private var showingCAImporter = false
  @State private var pendingDelete: SavedConnectionMetadata?

  private var cleartextWarning: String? {
    guard !tls, !useSSH, let config = try? ConnectionConfig(url: effectiveURL), config.tlsMode == .disable else {
      return nil
    }
    guard !Self.isLoopback(host: config.host) else { return nil }
    return "Cleartext remote connection. Enable TLS or add ?sslmode=require before connecting outside localhost."
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
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

      savedConnectionsSection

      TextField("postgres://user:password@host:5432/database", text: $url)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("postgres-url-field")
        .onChange(of: url) { _, newValue in
          if newValue != Self.redactedURLForDisplay(sensitivePrefilledURL) {
            sensitivePrefilledURL = nil
          }
          tls = Self.defaultTLSPreference(for: effectiveURL)
        }

      Toggle("TLS verify-full", isOn: $tls)
        .onChange(of: tls) { _, enabled in
          if enabled { useSSH = false }
        }
      if let cleartextWarning {
        Label(cleartextWarning, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .textSelection(.enabled)
      }
      if tls {
        HStack {
          TextField("CA certificate path", text: $tlsCAPath)
            .textFieldStyle(.roundedBorder)
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
          .textFieldStyle(.roundedBorder)
      }

      saveConnectionSection

      if let error = state.lastError ?? state.persistenceError {
        ErrorBanner(message: error)
          .clipShape(RoundedRectangle(cornerRadius: 8))
      }

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
    .padding(24)
    .frame(width: 560)
    .task {
      await state.loadSavedConnections()
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

  private var savedConnectionsSection: some View {
    Group {
      if !state.savedConnections.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Saved connections")
            .font(.caption.bold())
            .foregroundStyle(.secondary)
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
            .padding(10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
          }
        }
      }
    }
  }

  private var saveConnectionSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Toggle("Save this connection", isOn: $saveConnection)
      if saveConnection {
        TextField("Connection name", text: $connectionName)
          .textFieldStyle(.roundedBorder)
        Picker("Environment", selection: $environment) {
          ForEach(ConnectionEnvironment.allCases) { environment in
            Text(environment.displayName).tag(environment)
          }
        }
        .pickerStyle(.segmented)
      }
    }
  }

  private var connectDisabled: Bool {
    effectiveURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || state.connectionState == .connecting
      || (saveConnection && connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private var effectiveURL: String {
    if let sensitivePrefilledURL, url == Self.redactedURLForDisplay(sensitivePrefilledURL) {
      return sensitivePrefilledURL
    }
    return url
  }

  private func connectAndMaybeSave() async {
    await state.connect(
      url: effectiveURL,
      tls: tls,
      tlsCAPath: tls ? tlsCAPath : nil,
      sshTarget: useSSH && !tls ? sshTarget : nil
    )
    guard saveConnection, state.isConnected else { return }
    if let metadata = await state.saveConnection(
      name: connectionName,
      url: effectiveURL,
      tls: tls,
      tlsCAPath: tls ? tlsCAPath : nil,
      sshTarget: useSSH && !tls ? sshTarget : nil,
      environment: environment
    ) {
      state.activeSavedConnection = metadata
    }
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
