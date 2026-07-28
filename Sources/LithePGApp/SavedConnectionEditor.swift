import LithePGCore
import SwiftUI

struct SavedConnectionEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var state: AppState
  let connection: SavedConnectionMetadata

  @State private var name: String
  @State private var host: String
  @State private var port: String
  @State private var database: String
  @State private var username: String
  @State private var password = ""
  @State private var passwordIsAvailable = false
  @State private var tlsMode: ConnectionConfig.TLSMode
  @State private var tlsCAPath: String
  @State private var useSSH: Bool
  @State private var sshTarget: String
  @State private var environment: ConnectionEnvironment
  @State private var isLoadingPassword = true
  @State private var isSaving = false

  init(state: AppState, connection: SavedConnectionMetadata) {
    self.state = state
    self.connection = connection
    _name = State(initialValue: connection.name)
    _host = State(initialValue: connection.host)
    _port = State(initialValue: String(connection.port))
    _database = State(initialValue: connection.database)
    _username = State(initialValue: connection.username)
    // An unreadable label is held to the strongest mode rather than quietly weakened.
    _tlsMode = State(
      initialValue: (try? AppState.tlsMode(fromSavedLabel: connection.tlsMode)) ?? .verifyFull)
    _tlsCAPath = State(initialValue: connection.pinnedRootCertificatePath ?? "")
    _useSSH = State(initialValue: connection.sshTarget != nil)
    _sshTarget = State(initialValue: connection.sshTarget ?? "")
    _environment = State(initialValue: connection.environment)
  }

  var body: some View {
    Form {
      Section {
        Label("Edit saved connection", systemImage: "pencil.circle.fill")
          .font(.title2.bold())
          .foregroundStyle(.tint)
        Text("Changes apply the next time you connect. Passwords, when used, remain in Keychain.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section("Connection") {
        TextField("Name", text: $name)
          .accessibilityIdentifier("edit-connection-name")
        Picker("Environment", selection: $environment) {
          ForEach(ConnectionEnvironment.allCases) { environment in
            Text(environment.displayName).tag(environment)
          }
        }
        .pickerStyle(.segmented)
        .controlAffordance("Classify the connection so its environment is visible in the workspace")

        TextField("Host", text: $host)
          .accessibilityIdentifier("edit-connection-host")
        TextField("Port", text: $port)
          .accessibilityIdentifier("edit-connection-port")
        TextField("Database", text: $database)
          .accessibilityIdentifier("edit-connection-database")
        TextField("Username", text: $username)
          .accessibilityIdentifier("edit-connection-username")
        SecureField(
          isLoadingPassword ? "Loading password…" : "Password",
          text: $password
        )
        .disabled(isLoadingPassword)
        .accessibilityIdentifier("edit-connection-password")
        .onChange(of: password) { _, _ in
          if !isLoadingPassword { passwordIsAvailable = true }
        }
      }

      Section("Security") {
        Picker("Encryption", selection: $tlsMode) {
          ForEach(ConnectSheetPresentation.tlsModeOrder, id: \.self) { mode in
            Text(ConnectSheetPresentation.tlsModeTitle(mode)).tag(mode)
          }
        }
        .pickerStyle(.inline)
        .accessibilityIdentifier("editor-picker-tls-mode")
        .controlAffordance("Choose how much the connection to the server is protected")
        .onChange(of: tlsMode) { _, mode in
          if mode != .disable { useSSH = false }
        }

        Text(ConnectSheetPresentation.tlsModeCaption(tlsMode))
          .font(.caption)
          .foregroundStyle(.secondary)

        if let warning = ConnectSheetPresentation.encryptionWarning(mode: tlsMode, host: host) {
          Label(warning, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }

        if ConnectSheetPresentation.showsCACertificateField(mode: tlsMode) {
          TextField("CA certificate path", text: $tlsCAPath)
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
          TextField("user@host[:port]", text: $sshTarget)
        }
      }

      if let error = state.persistenceError ?? state.connectionTestError {
        Section {
          ErrorBanner(message: error)
        }
      } else if let message = state.connectionTestMessage {
        Section {
          Label(message, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }
      }

      Section {
        HStack {
          Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)
            .buttonAffordance("Discard changes and close")
          Spacer()
          Button("Test connection") {
            Task { await testConnection() }
          }
          .buttonAffordance("Test this connection without opening the workspace")
          .disabled(saveDisabled)

          Button {
            Task { await save() }
          } label: {
            if isSaving {
              ProgressView()
                .controlSize(.small)
            } else {
              Text("Save changes")
            }
          }
          .keyboardShortcut(.defaultAction)
          .accessibilityLabel(isSaving ? "Saving changes" : "Save changes")
          .buttonAffordance("Save changes to this connection")
          .disabled(saveDisabled)
          .accessibilityIdentifier("save-connection-changes-button")
        }
      }
    }
    .formStyle(.grouped)
    .frame(width: 520)
    .interactiveDismissDisabled(isSaving)
    .onChange(of: inputSignature) { _, _ in
      state.clearConnectionTestResult()
    }
    .task {
      defer { isLoadingPassword = false }
      if let storedPassword = await state.savedConnectionPassword(id: connection.id) {
        password = storedPassword
        passwordIsAvailable = true
      }
    }
    .onDisappear {
      state.clearConnectionTestResult()
    }
  }

  private var saveDisabled: Bool {
    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || database.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      || parsedPort == nil
      || !passwordIsAvailable
      || isLoadingPassword
      || isSaving
      || state.isTestingConnection
  }

  private var parsedPort: Int? {
    guard let value = Int(port), (1...65_535).contains(value) else { return nil }
    return value
  }

  private var inputSignature: String {
    [
      name, host, port, database, username, password, String(describing: tlsMode), tlsCAPath,
      String(useSSH), sshTarget, environment.rawValue,
    ].joined(separator: "\u{1F}")
  }

  private func testConnection() async {
    guard let port = parsedPort else { return }
    await state.testConnection(
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      tlsMode: tlsMode,
      tlsCAPath: tlsMode == .verifyFull ? tlsCAPath : nil,
      sshTarget: useSSH && tlsMode == .disable ? sshTarget : nil
    )
  }

  private func save() async {
    guard let port = parsedPort else { return }
    isSaving = true
    defer { isSaving = false }

    let updated = await state.updateSavedConnection(
      id: connection.id,
      name: name,
      host: host,
      port: port,
      database: database,
      username: username,
      password: password,
      tlsMode: tlsMode,
      tlsCAPath: tlsMode == .verifyFull ? tlsCAPath : nil,
      sshTarget: useSSH && tlsMode == .disable ? sshTarget : nil,
      environment: environment
    )
    if updated != nil { dismiss() }
  }
}
