import SwiftUI

struct ConnectionNavigator: View {
  @Bindable var state: AppState
  @State private var pendingDelete: SavedConnectionMetadata?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      connectionList
      Divider()
      NeonScannerButton(state: state)
        .padding(10)
    }
    .frame(minHeight: 150, idealHeight: 230, maxHeight: 300)
    .accessibilityIdentifier("connection-navigator")
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
      Button("Cancel", role: .cancel) { pendingDelete = nil }
    } message: { _ in
      Text("This removes the local connection and its Keychain password. It does not touch the database.")
    }
  }

  private var header: some View {
    HStack {
      VStack(alignment: .leading, spacing: 2) {
        Text("Connections")
          .font(.headline)
        Text("\(state.savedConnections.count) saved")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if state.isScanningNeon {
        ProgressView()
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
  }

  @ViewBuilder
  private var connectionList: some View {
    if state.savedConnections.isEmpty {
      Text("Saved connections and imported Neon databases appear here.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          ForEach(state.savedConnections) { connection in
            connectionRow(connection)
          }
        }
        .padding(8)
      }
    }
  }

  private func connectionRow(_ connection: SavedConnectionMetadata) -> some View {
    Button {
      Task { await state.connectSavedConnection(id: connection.id) }
    } label: {
      HStack(spacing: 8) {
        Image(systemName: state.activeSavedConnection?.id == connection.id
          ? "circle.fill" : "circle")
          .font(.system(size: 8))
          .foregroundStyle(state.activeSavedConnection?.id == connection.id ? .green : .secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(connection.name)
            .font(.callout.weight(.semibold))
            .lineLimit(1)
          Text(connection.connectionLabel)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 4)
        Text(connection.environment.displayName)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 6)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(
      state.connectionState == .connecting
        || state.activeSavedConnection?.id == connection.id
    )
    .contextMenu {
      Button("Connect") {
        Task { await state.connectSavedConnection(id: connection.id) }
      }
      Button("Delete…", role: .destructive) { pendingDelete = connection }
    }
    .accessibilityIdentifier("saved-connection-\(connection.id.uuidString)")
  }
}

struct NeonScannerButton: View {
  @Bindable var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button {
        Task { await state.scanAndImportNeonConnections() }
      } label: {
        Label(
          ConnectionNavigatorPresentation.neonButtonTitle(
            availability: state.neonCLIAvailability,
            isScanning: state.isScanningNeon
          ),
          systemImage: "sparkle.magnifyingglass"
        )
      }
      .buttonStyle(.borderless)
      .disabled(!state.canScanNeon)
      .help(ConnectionNavigatorPresentation.neonButtonHelp(
        availability: state.neonCLIAvailability
      ))
      .accessibilityIdentifier("scan-neon-cli-button")

      if let message = state.neonScanMessage {
        Text(message)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("neon-scan-message")
      }
      if let error = state.neonScanError {
        Text(error)
          .font(.caption2)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("neon-scan-error")
      }
    }
  }
}

enum ConnectionNavigatorPresentation {
  static func neonButtonTitle(
    availability: NeonCLIAvailability,
    isScanning: Bool
  ) -> String {
    if isScanning { return "Scanning Neon…" }
    return availability.isAvailable ? "Scan Neon CLI" : "Neon CLI not installed"
  }

  static func neonButtonHelp(availability: NeonCLIAvailability) -> String {
    availability.isAvailable
      ? "Import Neon branch databases that are not already saved in LithePG"
      : "Install with: brew install neonctl"
  }
}
