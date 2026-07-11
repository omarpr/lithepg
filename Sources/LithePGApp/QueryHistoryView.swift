import SwiftUI

struct QueryHistoryView: View {
  @Bindable var state: AppState

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Toggle("Record query history", isOn: $state.queryHistoryEnabled)
          .toggleStyle(.switch)
        Spacer()
        Button("Clear") {
          Task { await state.clearQueryHistory() }
        }
        .disabled(state.queryHistory.isEmpty)
      }

      Text("History stores SQL, connection metadata, timing and status, never result rows.")
        .font(.caption)
        .foregroundStyle(.secondary)

      Divider()

      if state.queryHistory.isEmpty {
        ContentUnavailableView(
          "No query history yet",
          systemImage: "clock.arrow.circlepath",
          description: Text("Enable history and run a query. Recent SQL will appear here.")
        )
        .frame(minHeight: 180)
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 10) {
            ForEach(state.queryHistory) { entry in
              historyRow(entry)
            }
          }
          .padding(.vertical, 2)
        }
        .frame(minHeight: 220, maxHeight: 360)
      }
    }
    .padding(16)
    .frame(width: 460)
    .task { await state.loadQueryHistory() }
  }

  private func historyRow(_ entry: QueryHistoryEntry) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline) {
        Label(
          entry.succeeded ? "Succeeded" : "Failed",
          systemImage: entry.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill"
        )
        .font(.caption.bold())
        .foregroundStyle(entry.succeeded ? .green : .red)
        Spacer()
        Text("\(entry.elapsedMilliseconds) ms")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }

      Text(entry.sql)
        .font(.caption.monospaced())
        .lineLimit(3)
        .textSelection(.enabled)

      HStack(spacing: 8) {
        Text(entry.connectionName ?? entry.connectionLabel)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
        if let environment = entry.environment {
          Text(environment.displayName)
            .font(.caption2.bold())
            .foregroundStyle(environmentColor(environment))
        }
        Spacer()
        Text(entry.summary)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      HStack {
        Spacer()
        Button("Use SQL") {
          state.useHistoryEntry(entry)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
  }

  private func environmentColor(_ environment: ConnectionEnvironment) -> Color {
    switch environment {
    case .development: .green
    case .staging: .orange
    case .production: .red
    case .custom: .blue
    }
  }
}
