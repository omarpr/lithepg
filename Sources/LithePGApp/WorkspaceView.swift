import LithePGCore
import SwiftUI

struct WorkspaceView: View {
  /// Badge fallback when no connection environment is active: the bundle's
  /// marketing version for packaged builds, "dev" for bare-executable runs.
  static func versionBadgeLabel(
    marketingVersion: String? =
      Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
  ) -> String {
    guard let marketingVersion, !marketingVersion.isEmpty else { return "dev" }
    return "v\(marketingVersion)"
  }


  @Bindable var state: AppState
  @State private var showingQueryHistory = false
  @State private var showingAskQuery = false
  @State private var showingSchemaGraph = false
  @State private var showingPlanTree = false
  @State private var showingConnectionForm = false
  @State private var renamingTabID: QueryTab.ID?
  @State private var renameDraft = ""

  var body: some View {
    HSplitView {
      VStack(spacing: 0) {
        ConnectionNavigator(
          state: state,
          onAddConnection: { showingConnectionForm = true }
        )
        Divider()
        SchemaSidebar(state: state)
      }
      .frame(minWidth: 240, idealWidth: 280, maxWidth: 340)
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

        Menu {
          Button("Explain (plan only)") {
            Task {
              await state.runExplain(analyze: false)
              showingPlanTree = state.lastQueryPlan != nil
            }
          }
          .keyboardShortcut("e", modifiers: [.command])
          Button("Explain Analyze (runs the query)") {
            Task {
              await state.runExplain(analyze: true)
              showingPlanTree = state.lastQueryPlan != nil
            }
          }
          .keyboardShortcut("e", modifiers: [.command, .shift])
        } label: {
          Label("Explain", systemImage: "list.bullet.indent")
        }
        .disabled(!state.canRunQuery || state.isExplaining)
        .accessibilityIdentifier("explain-menu")
        .help("Show the query plan; Explain Analyze executes the query for real timings")
        .sheet(isPresented: $showingPlanTree, onDismiss: { state.clearQueryPlan() }) {
          if let plan = state.lastQueryPlan {
            PlanTreeView(plan: plan, isAnalyze: state.lastQueryPlanIsAnalyze)
          }
        }

        Button {
          showingSchemaGraph = true
        } label: {
          Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])
        .disabled(state.schema == nil)
        .accessibilityIdentifier("schema-graph-button")
        .help("Show the schema as a graph of tables and foreign keys")
        .sheet(isPresented: $showingSchemaGraph) {
          if let schema = state.schema {
            SchemaGraphView(schema: schema)
          }
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
    .task {
      await state.loadSavedConnections()
      state.refreshNeonCLIAvailability()
    }
    .sheet(isPresented: $showingConnectionForm) {
      ConnectSheet(
        state: state,
        closeAction: { showingConnectionForm = false },
        saveByDefault: true
      )
    }
  }

  private var tabBar: some View {
    HStack(spacing: 6) {
      ForEach(state.queryTabs) { tab in
        HStack(spacing: 2) {
          Button {
            state.selectQueryTab(id: tab.id)
          } label: {
            Text(tab.title)
              .lineLimit(1)
          }
          .buttonStyle(.plain)
          .simultaneousGesture(
            TapGesture(count: 2).onEnded { beginRenamingTab(tab) }
          )

          if state.queryTabs.count > 1 {
            Button {
              state.closeQueryTab(id: tab.id)
            } label: {
              Label("Close \(tab.title)", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.caption2.bold())
            }
            .buttonStyle(.borderless)
            .help("Close \(tab.title)")
            .accessibilityIdentifier("close-query-tab-\(tab.id.uuidString)")
          }
        }
        .padding(.leading, 9)
        .padding(.trailing, state.queryTabs.count > 1 ? 5 : 9)
        .padding(.vertical, 5)
        .background(
          tab.id == state.selectedQueryTabID
            ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.12), in: Capsule())
        .contextMenu {
          Button("Rename Tab…") { beginRenamingTab(tab) }
          if state.queryTabs.count > 1 {
            Button("Close Tab") { state.closeQueryTab(id: tab.id) }
          }
        }
        .popover(
          isPresented: Binding(
            get: { renamingTabID == tab.id },
            set: { if !$0 { renamingTabID = nil } }
          )
        ) {
          HStack(spacing: 8) {
            TextField("Tab name", text: $renameDraft)
              .frame(width: 180)
              .accessibilityIdentifier("rename-tab-field")
              .onSubmit { commitTabRename(tab) }
            Button("Rename") { commitTabRename(tab) }
              .keyboardShortcut(.defaultAction)
          }
          .padding(10)
        }
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

  private func beginRenamingTab(_ tab: QueryTab) {
    renameDraft = tab.title
    renamingTabID = tab.id
  }

  private func commitTabRename(_ tab: QueryTab) {
    state.renameQueryTab(id: tab.id, to: renameDraft)
    renamingTabID = nil
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
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("connection-status")
      }
      Spacer()
      Text(state.activeConnectionEnvironment?.displayName ?? Self.versionBadgeLabel())
        .font(.callout.bold())
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
            .font(.callout.bold())
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
