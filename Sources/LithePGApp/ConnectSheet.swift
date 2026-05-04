import SwiftUI
import UniformTypeIdentifiers

struct ConnectSheet: View {
  @Bindable var state: AppState
  @State private var url: String = ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? ""
  @State private var tls = ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] != nil
  @State private var tlsCAPath: String =
    ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] ?? ""
  @State private var useSSH = ProcessInfo.processInfo.environment["POSTGRES_SSH"] != nil
  @State private var sshTarget: String = ProcessInfo.processInfo.environment["POSTGRES_SSH"] ?? ""
  @State private var saveConnection = false
  @State private var connectionName = ""
  @State private var environment: ConnectionEnvironment = .development
  @State private var showingCAImporter = false

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

      Toggle("TLS verify-full", isOn: $tls)
        .onChange(of: tls) { _, enabled in
          if enabled { useSSH = false }
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
    url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || state.connectionState == .connecting
      || (saveConnection && connectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func connectAndMaybeSave() async {
    await state.connect(
      url: url,
      tls: tls,
      tlsCAPath: tls ? tlsCAPath : nil,
      sshTarget: useSSH && !tls ? sshTarget : nil
    )
    guard saveConnection, state.isConnected else { return }
    if let metadata = await state.saveConnection(
      name: connectionName,
      url: url,
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

  private static var certificateTypes: [UTType] {
    [
      UTType(filenameExtension: "pem"),
      UTType(filenameExtension: "crt"),
      .item,
    ].compactMap { $0 }
  }
}
