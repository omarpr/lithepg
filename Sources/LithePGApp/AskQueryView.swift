import LithePGCore
import SwiftUI

struct AskQueryViewModel: Equatable {
  var prompt: String
  var isDrafting: Bool
  var draft: AIQueryDraft?
  var error: String?
  var hasSchema: Bool

  init(
    prompt: String,
    isDrafting: Bool = false,
    draft: AIQueryDraft? = nil,
    error: String? = nil,
    hasSchema: Bool
  ) {
    self.prompt = prompt
    self.isDrafting = isDrafting
    self.draft = draft
    self.error = error
    self.hasSchema = hasSchema
  }

  var canDraft: Bool {
    hasSchema && !isDrafting && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  var canInsert: Bool {
    draft?.status == .ready && !sqlPreview.isEmpty
  }

  var sqlPreview: String {
    guard draft?.status == .ready else { return "" }
    return draft?.sql.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
  }

  var statusMessage: String? {
    if isDrafting { return "Drafting SQL…" }
    if let error, !error.isEmpty { return error }
    if let draft { return draft.explanation }
    if !hasSchema { return "Refresh schema before asking in English." }
    return nil
  }

  var referencedObjectsText: String {
    draft?.referencedObjects.joined(separator: ", ") ?? ""
  }
}

struct AskQueryView: View {
  @Bindable var state: AppState
  @State private var prompt = ""

  private var model: AskQueryViewModel {
    AskQueryViewModel(
      prompt: prompt,
      isDrafting: state.isDraftingSQL,
      draft: state.lastAIDraft,
      error: state.aiError,
      hasSchema: state.schema != nil
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Ask in English")
          .font(.headline)
        Text("Draft SQL from the loaded schema. Nothing runs automatically.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      TextField("Show customers ordered by revenue", text: $prompt, axis: .vertical)
        .lineLimit(2...4)
        .textFieldStyle(.roundedBorder)
        .accessibilityIdentifier("ask-query-prompt")
        .onSubmit { draft() }

      HStack(spacing: 10) {
        Button {
          draft()
        } label: {
          Label(model.isDrafting ? "Drafting" : "Draft SQL", systemImage: "wand.and.stars")
        }
        .keyboardShortcut(.return, modifiers: [.command])
        .disabled(!model.canDraft)
        .accessibilityIdentifier("ask-query-draft-button")

        Button {
          state.insertLastAIDraftIntoEditor()
        } label: {
          Label("Insert into editor", systemImage: "text.insert")
        }
        .disabled(!model.canInsert)
        .accessibilityIdentifier("ask-query-insert-button")

        if model.isDrafting {
          ProgressView()
            .controlSize(.small)
            .accessibilityIdentifier("ask-query-progress")
        }
      }

      if let status = model.statusMessage {
        Label(status, systemImage: statusIcon)
          .font(.caption)
          .foregroundStyle(statusColor)
          .accessibilityIdentifier("ask-query-status")
      }

      if !model.sqlPreview.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          Text("Generated SQL")
            .font(.caption.bold())
          ScrollView {
            Text(model.sqlPreview)
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(10)
          }
          .frame(minHeight: 90, maxHeight: 160)
          .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
          .accessibilityIdentifier("ask-query-sql-preview")
        }
      }

      if !model.referencedObjectsText.isEmpty {
        Text("References: \(model.referencedObjectsText)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .accessibilityIdentifier("ask-query-references")
      }
    }
    .padding(16)
    .frame(width: 460)
  }

  private var statusIcon: String {
    if state.isDraftingSQL { return "hourglass" }
    if state.aiError != nil { return "exclamationmark.triangle" }
    if state.lastAIDraft?.status == .ready { return "checkmark.circle" }
    return "info.circle"
  }

  private var statusColor: Color {
    if state.aiError != nil { return .red }
    if state.lastAIDraft?.status == .ready { return .green }
    return .secondary
  }

  private func draft() {
    guard model.canDraft else { return }
    Task { await state.askInEnglish(prompt) }
  }
}
