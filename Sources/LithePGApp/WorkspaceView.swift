import LithePGCore
import SwiftUI

struct WorkspaceView: View {
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
      .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
      VStack(spacing: 0) {
        header
        productionWarning
        Divider()
        VStack(spacing: 0) {
          tabBar
          Divider()
          EditorView(
            text: $state.editorText,
            selection: state.editorSelection,
            onSelectionChange: { state.updateEditorSelection($0) },
            completionIndex: state.completionIndex
          )
          .frame(minHeight: 200)
          Divider()
          ErrorBanner(
            message: state.lastError,
            reconnect: state.canReconnectFromLastError
              ? {
                Task { await state.reconnect() }
              } : nil,
            stepDown: state.tlsStepDownAvailable
              ? {
                Task { await state.retryWithEncryptionOnly() }
              } : nil)
          ResultsTable(
            result: state.lastResult,
            editing: ResultEditingActions(
              editability: { await state.editability(forColumn: $0) },
              preview: { state.cellUpdatePreview(row: $0, column: $1, newValue: $2) },
              save: { await state.saveCell(row: $0, column: $1, newValue: $2) },
              isProduction: state.activeConnectionEnvironment?.isProduction == true
            )
          )
          .frame(minHeight: 320, maxHeight: .infinity)
          .layoutPriority(1)
        }
        .frame(maxHeight: .infinity)
      }
      .frame(minWidth: 640)
    }
    .toolbar {
      // Three groups, like Xcode: run, inspect, browse. Then disconnect on its own.
      ToolbarItemGroup {
        Button {
          state.startQuery()
        } label: {
          Label(state.isRunning ? "Running" : "Run", systemImage: "play.fill")
            .labelStyle(ToolbarCommandLabelStyle(prominent: true))
        }
        // The main action is an accent colored chip when it can run and plainly dimmed when not.
        .buttonStyle(.plain)
        .accessibilityIdentifier("run-query-button")
        .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .runQuery))
        .buttonAffordance(runQueryHelp)
        .disabled(!state.canRunQuery)

        // Stop only exists while a query runs; a permanently dim button was noise.
        if state.isRunning {
          Button {
            state.cancelQuery()
          } label: {
            Label("Stop", systemImage: "stop.fill")
              .labelStyle(ToolbarCommandLabelStyle())
              .toolbarIconStyle(enabled: state.isRunning)
          }
          .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .cancelQuery))
          .buttonAffordance("Cancel the running query")
          .disabled(!state.isRunning)
          .buttonStyle(.plain)
          .accessibilityIdentifier("cancel-query-button")
        }
      }

      ToolbarItemGroup {
        Menu {
          Button("Explain (plan only)") {
            Task {
              await state.runExplain(analyze: false)
              showingPlanTree = state.lastQueryPlan != nil
            }
          }
          .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .explain))
          Button("Explain Analyze (runs the query)") {
            Task {
              await state.runExplain(analyze: true)
              showingPlanTree = state.lastQueryPlan != nil
            }
          }
          .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .explainAnalyze))
        } label: {
          Label("Explain", systemImage: "list.bullet.indent")
            .labelStyle(ToolbarCommandLabelStyle())
            .toolbarIconStyle(enabled: state.canRunQuery && !state.isExplaining)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .buttonAffordance(explainHelp)
        .disabled(!state.canRunQuery || state.isExplaining)
        .accessibilityIdentifier("explain-menu")
        .sheet(isPresented: $showingPlanTree, onDismiss: { state.clearQueryPlan() }) {
          if let plan = state.lastQueryPlan {
            PlanTreeView(plan: plan, isAnalyze: state.lastQueryPlanIsAnalyze)
          }
        }

        Button {
          showingAskQuery.toggle()
        } label: {
          Label("Ask", systemImage: "wand.and.stars")
            .labelStyle(ToolbarCommandLabelStyle())
            .toolbarIconStyle(enabled: !state.isDraftingSQL)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .askInEnglish))
        .buttonAffordance(
          state.isDraftingSQL
            ? "A local SQL draft is already in progress"
            : state.schema == nil
              ? "Connect and refresh the schema to enable AI drafting"
              : "Ask in English"
        )
        .disabled(state.isDraftingSQL)
        .accessibilityIdentifier("ask-query-button")
        .popover(isPresented: $showingAskQuery) {
          AskQueryView(state: state)
        }
      }

      ToolbarItemGroup {
        Button {
          showingSchemaGraph = true
        } label: {
          Label("Graph", systemImage: "point.3.connected.trianglepath.dotted")
            .labelStyle(ToolbarCommandLabelStyle())
            .toolbarIconStyle(enabled: state.schema != nil)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .schemaGraph))
        .buttonAffordance(
          state.schema == nil
            ? "Connect and refresh the schema to enable the schema graph"
            : "Show the schema as a graph of tables and foreign keys"
        )
        .disabled(state.schema == nil)
        .accessibilityIdentifier("schema-graph-button")
        .sheet(isPresented: $showingSchemaGraph) {
          if let schema = state.schema {
            SchemaGraphView(schema: schema)
          }
        }

        Button {
          showingQueryHistory.toggle()
        } label: {
          Label("History", systemImage: "clock.arrow.circlepath")
            .labelStyle(ToolbarCommandLabelStyle())
            .toolbarIconStyle(enabled: true)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingQueryHistory) {
          QueryHistoryView(state: state)
        }
        .buttonAffordance("Show recent query history")
        .accessibilityLabel("Query History")
      }

      ToolbarItemGroup {
        if isConnectedOrLost {
          Button {
            Task { await state.disconnect() }
          } label: {
            Label("Disconnect", systemImage: "power")
              .labelStyle(ToolbarCommandLabelStyle())
              .toolbarIconStyle(enabled: isConnectedOrLost)
          }
          .buttonAffordance(
            state.connectionState == .connecting
              ? "Wait for the connection attempt to finish"
              : state.connectionState == .disconnected
                ? "No database is connected"
                : "Disconnect from the current database"
          )
          .disabled(!isConnectedOrLost)
          .buttonStyle(.plain)
          .accessibilityIdentifier("disconnect-button")
        }
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
          .accessibilityLabel("Query tab \(tab.title)")
          .accessibilityHint("Double-click to rename")
          .accessibilityAddTraits(tab.id == state.selectedQueryTabID ? .isSelected : [])
          .buttonAffordance("Select query tab \(tab.title)")
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
            .buttonAffordance("Close \(tab.title)")
            .accessibilityIdentifier("close-query-tab-\(tab.id.uuidString)")
          }
        }
        .padding(.leading, 9)
        .padding(.trailing, state.queryTabs.count > 1 ? 5 : 9)
        .padding(.vertical, 5)
        .background(
          tab.id == state.selectedQueryTabID
            ? Color.accentColor.opacity(0.22) : Color.secondary.opacity(0.08),
          in: RoundedRectangle(cornerRadius: 7, style: .continuous)
        )
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
              .buttonAffordance("Rename this query tab")
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
      .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .newTab))
      .buttonAffordance("New query tab")
      .accessibilityIdentifier("new-query-tab-button")
      .background {
        // Close-tab has no visible button of its own (each tab has its ×), so its shortcut
        // lives on this invisible one. Window shortcuts run before the menu bar, so ⌘W
        // closes the query tab rather than the window while more than one tab is open.
        // Previous and next tab moved out of the toolbar, where they sat disabled most of
        // the time; their shortcuts live here the same way.
        ZStack {
          Button("Close Query Tab") { state.closeSelectedQueryTab() }
            .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .closeTab))
          Button("Previous Query Tab") { state.selectPreviousQueryTab() }
            .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .previousTab))
          Button("Next Query Tab") { state.selectNextQueryTab() }
            .keyboardShortcut(state.keyBindings.keyboardShortcut(for: .nextTab))
        }
        .disabled(state.queryTabs.count <= 1)
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
      }

      Spacer()
    }
    .padding(.horizontal, UIMetrics.inset)
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
        Text(headerTitle)
          .font(.headline)
        Text(statusText)
          .font(.callout)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("connection-status")
      }
      Spacer()
      if state.canReconnectLostConnection {
        Button {
          Task { await state.reconnect() }
        } label: {
          Label("Reconnect", systemImage: "arrow.clockwise")
        }
        .buttonStyle(.borderedProminent)
        .buttonAffordance("Reconnect to the database whose connection was lost")
        .accessibilityIdentifier("reconnect-from-header-button")
      } else if state.connectionState == .disconnected {
        Button {
          showingConnectionForm = true
        } label: {
          Label("Connect", systemImage: "cable.connector")
        }
        .buttonStyle(.borderedProminent)
        .buttonAffordance("Add a connection or connect to a saved database")
        .accessibilityIdentifier("connect-from-workspace-button")
      }
      // The app version lives in About; here a badge would read like the server's version.
      if let environment = state.activeConnectionEnvironment {
        EnvironmentCapsule(environment: environment, long: true)
      }
    }
    .padding(.horizontal, UIMetrics.inset)
    .padding(.vertical, UIMetrics.headerVertical)
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
        .padding(.horizontal, UIMetrics.inset)
        .padding(.vertical, 8)
        .background(Color.red.opacity(0.10))
        .accessibilityIdentifier("production-warning-banner")
      }
    }
  }

  private var headerTitle: String {
    switch state.connectionState {
    case .disconnected: state.lostConnectionLabel == nil ? "No connection" : "LithePG"
    case .connecting, .connected: "LithePG"
    }
  }

  private var statusText: String {
    switch state.connectionState {
    case .disconnected:
      if let lost = state.lostConnectionLabel {
        "Connection lost · \(lost)"
      } else {
        "Choose a saved connection or add a new one"
      }
    case .connecting: "Connecting…"
    case .connected(let label):
      if let active = state.activeSavedConnection {
        "\(active.name) • \(active.environment.displayName) • \(label)"
      } else {
        label
      }
    }
  }

  private var runQueryHelp: String {
    if state.isRunning {
      return "Query is running"
    }
    if state.editorText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Enter SQL before running a query"
    }
    switch state.connectionState {
    case .disconnected:
      return "Connect to a database before running a query"
    case .connecting:
      return "Wait for the connection attempt to finish"
    case .connected:
      return "Run the statement under the cursor, or the selected SQL"
    }
  }

  private var explainHelp: String {
    if state.isExplaining {
      return "A query plan is already being generated"
    }
    if !state.canRunQuery {
      return runQueryHelp
    }
    return "Show the query plan; Explain Analyze executes the query for real timings"
  }

  private var isConnectedOrLost: Bool {
    !(state.connectionState == .disconnected || state.connectionState == .connecting)
  }
}

private extension View {
  /// Toolbar icons render in a muted gray by default, which made usable commands look
  /// disabled. Usable icons get full label contrast; unusable ones stay clearly dimmed.
  func toolbarIconStyle(enabled: Bool) -> some View {
    foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
  }
}
