import LithePGCore
import SwiftUI

struct WorkspaceView: View {
  @Bindable var state: AppState
  @State private var showingQueryHistory = false
  @State private var showingAskQuery = false

  var body: some View {
    HSplitView {
      SchemaSidebar(state: state)
      VStack(spacing: 0) {
        header
        productionWarning
        Divider()
        VStack(spacing: 0) {
          tabBar
          Divider()
          EditorView(text: $state.editorText)
            .frame(minHeight: 200)
          Divider()
          ErrorBanner(
            message: state.lastError,
            reconnect: state.canReconnectFromLastError
              ? {
                Task { await state.reconnect() }
              } : nil)
          ResultsTable(result: state.lastResult)
            .frame(minHeight: 320, maxHeight: .infinity)
            .layoutPriority(1)
        }
        .frame(maxHeight: .infinity)
      }
      .frame(minWidth: 640)
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

        Button {
          state.newQueryTab()
        } label: {
          Label("New Query Tab", systemImage: "plus")
        }
        .keyboardShortcut("t", modifiers: [.command])

        Button {
          state.closeSelectedQueryTab()
        } label: {
          Label("Close Query Tab", systemImage: "xmark")
        }
        .keyboardShortcut("w", modifiers: [.command])
        .disabled(state.queryTabs.count <= 1)

        Button {
          state.selectPreviousQueryTab()
        } label: {
          Label("Previous Query Tab", systemImage: "chevron.left")
        }
        .keyboardShortcut("[", modifiers: [.command, .shift])
        .disabled(state.queryTabs.count <= 1)

        Button {
          state.selectNextQueryTab()
        } label: {
          Label("Next Query Tab", systemImage: "chevron.right")
        }
        .keyboardShortcut("]", modifiers: [.command, .shift])
        .disabled(state.queryTabs.count <= 1)

        Button {
          showingAskQuery.toggle()
        } label: {
          Label("Ask", systemImage: "wand.and.stars")
        }
        .keyboardShortcut("k", modifiers: [.command, .shift])
        .disabled(state.schema == nil || state.isDraftingSQL)
        .accessibilityIdentifier("ask-query-button")
        .popover(isPresented: $showingAskQuery) {
          AskQueryView(state: state)
        }

        Button {
          showingQueryHistory.toggle()
        } label: {
          Label("Query History", systemImage: "clock.arrow.circlepath")
        }
        .popover(isPresented: $showingQueryHistory) {
          QueryHistoryView(state: state)
        }

        Button("Disconnect") {
          Task { await state.disconnect() }
        }
        .disabled(state.connectionState == .disconnected || state.connectionState == .connecting)
      }
    }
    .onAppear {
      if state.editorText.isEmpty {
        state.editorText = state.defaultEditorText
      }
    }
  }

  private var tabBar: some View {
    HStack(spacing: 6) {
      ForEach(state.queryTabs) { tab in
        Button {
          state.selectQueryTab(id: tab.id)
        } label: {
          Text(tab.title)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
              tab.id == state.selectedQueryTabID
                ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(
          tab.id == state.selectedQueryTabID ? "selected-query-tab" : "query-tab")
      }

      Button {
        state.newQueryTab()
      } label: {
        Label("New Query Tab", systemImage: "plus")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help("New query tab")
      .accessibilityIdentifier("new-query-tab-button")

      Spacer()
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
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
      Text(state.activeConnectionEnvironment?.displayName ?? "v0.3 dogfood")
        .font(.caption.bold())
        .foregroundStyle(environmentColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(environmentColor.opacity(0.14), in: Capsule())
    }
    .padding(14)
  }

  private var productionWarning: some View {
    Group {
      if state.activeConnectionEnvironment?.isProduction == true {
        HStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle.fill")
          Text("Production connection. Double-check destructive SQL before running.")
            .font(.caption.bold())
          Spacer()
        }
        .foregroundStyle(.red)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
        .accessibilityIdentifier("production-warning-banner")
      }
    }
  }

  private var statusText: String {
    switch state.connectionState {
    case .disconnected: "Disconnected"
    case .connecting: "Connecting…"
    case .connected(let label):
      if let active = state.activeSavedConnection {
        "\(active.name) • \(active.environment.displayName) • \(label)"
      } else {
        label
      }
    }
  }

  private var environmentColor: Color {
    switch state.activeConnectionEnvironment {
    case .development: .green
    case .staging: .orange
    case .production: .red
    case .custom: .blue
    case nil: .secondary
    }
  }
}
