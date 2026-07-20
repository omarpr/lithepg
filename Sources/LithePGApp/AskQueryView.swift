import LithePGCore
import SwiftUI

struct AskQueryViewModel: Equatable {
  struct Guidance: Equatable {
    let title: String
    let message: String
  }

  var prompt: String
  var isDrafting: Bool
  var draft: AIQueryDraft?
  var error: String?
  var hasSchema: Bool
  var modelAvailability: OnDeviceAIModelAvailability

  init(
    prompt: String,
    isDrafting: Bool = false,
    draft: AIQueryDraft? = nil,
    error: String? = nil,
    hasSchema: Bool,
    modelAvailability: OnDeviceAIModelAvailability = .available
  ) {
    self.prompt = prompt
    self.isDrafting = isDrafting
    self.draft = draft
    self.error = error
    self.hasSchema = hasSchema
    self.modelAvailability = modelAvailability
  }

  var canDraft: Bool {
    hasSchema && modelAvailability == .available && !isDrafting
      && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    return nil
  }

  var referencedObjectsText: String {
    draft?.referencedObjects.joined(separator: ", ") ?? ""
  }

  var guidance: Guidance? {
    guard hasSchema else {
      return Guidance(
        title: "Database schema required",
        message:
          "Connect to a database and refresh its schema. Then reopen Ask and enter your request."
      )
    }

    switch modelAvailability {
    case .available:
      return nil
    case .appleIntelligenceNotEnabled:
      return Guidance(
        title: "Apple Intelligence is turned off",
        message:
          "Open System Settings → Apple Intelligence & Siri and turn on Apple Intelligence. SQL drafting stays disabled until setup completes."
      )
    case .modelNotReady:
      return Guidance(
        title: "Apple's on-device model is not ready",
        message:
          "Open System Settings → Apple Intelligence & Siri and allow model setup to finish. SQL drafting becomes available when Apple's model is ready."
      )
    case .deviceNotEligible:
      return Guidance(
        title: "Apple Intelligence is unavailable on this Mac",
        message:
          "This Mac is not eligible for Apple's on-device model, so Ask in English is unavailable. You can continue writing and running SQL directly."
      )
    case .unsupportedSystem:
      return Guidance(
        title: "The advanced local model requires macOS 26",
        message:
          "Upgrade to macOS 26 or later and enable Apple Intelligence to use Ask in English. Direct SQL editing remains available."
      )
    case .temporarilyUnavailable:
      return Guidance(
        title: "Apple's on-device model is temporarily unavailable",
        message:
          "Check Apple Intelligence in System Settings and try again later. SQL drafting stays disabled while the model is unavailable."
      )
    }
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
      hasSchema: state.schema != nil,
      modelAvailability: OnDeviceAIQueryService.modelAvailability()
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Ask in English")
          .font(.headline)
        Text(
          "Apple's lightweight on-device model drafts against your schema. No cloud model is used, and nothing runs automatically."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }

      if let guidance = model.guidance {
        HStack(alignment: .top, spacing: 10) {
          Image(systemName: "info.circle.fill")
            .foregroundStyle(.blue)
          VStack(alignment: .leading, spacing: 3) {
            Text(guidance.title)
              .font(.subheadline.bold())
            Text(guidance.message)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ask-query-disabled-guidance")
      }

      TextField("List bookings ordered by scheduled_at descending", text: $prompt, axis: .vertical)
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
