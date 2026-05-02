import SwiftUI
import LithePGCore

struct WorkspaceView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 0) {
                EditorView(text: $state.editorText)
                    .frame(minHeight: 260)
                Divider()
                ErrorBanner(message: state.lastError, reconnect: state.canReconnectFromLastError ? {
                    Task { await state.reconnect() }
                } : nil)
                ResultsTable(result: state.lastResult)
                    .frame(minHeight: 220)
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button {
                    state.startQuery()
                } label: {
                    Label(state.isRunning ? "Running" : "Run", systemImage: "play.fill")
                }
                .accessibilityIdentifier("run-query-button")
                .keyboardShortcut(.return, modifiers: [.command])
                .disabled(!state.canRunQuery)

                Button("Cancel") {
                    state.cancelQuery()
                }
                .keyboardShortcut(".", modifiers: [.command])
                .disabled(!state.isRunning)

                Button("Disconnect") {
                    Task { await state.disconnect() }
                }
                .disabled(state.connectionState == .disconnected || state.connectionState == .connecting)
            }
        }
        .onAppear {
            if state.editorText.isEmpty {
                state.editorText = "SELECT version();"
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cylinder.split.1x2")
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("LithePG")
                    .font(.headline)
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("connection-status")
            }
            Spacer()
            Text("v0.2a native editor shell")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.quaternary, in: Capsule())
        }
        .padding(14)
    }

    private var statusText: String {
        switch state.connectionState {
        case .disconnected: "Disconnected"
        case .connecting: "Connecting…"
        case .connected(let label): label
        }
    }
}
