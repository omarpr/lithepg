import AppKit
import SwiftUI

/// Settings > Keyboard: shows every command's shortcut and records new ones.
///
/// Click a shortcut, then press the new keys. Delete removes the shortcut, Esc cancels.
/// Unsafe or duplicate shortcuts are refused with the reason shown under the row.
struct KeyboardSettingsView: View {
    @Bindable var bindings: KeyBindings
    @State private var recording: KeyBindingAction?
    @State private var feedback: (action: KeyBindingAction, text: String)?
    @State private var monitor: Any?

    var body: some View {
        Form {
            Section {
                ForEach(KeyBindingAction.allCases) { action in
                    row(for: action)
                }
            } header: {
                Text("Shortcuts")
            } footer: {
                Text("Click a shortcut, then press the new keys. Delete removes it and Esc cancels. Shortcuts need ⌘ or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Spacer()
                    Button("Restore Defaults") {
                        stopRecording()
                        bindings.resetAll()
                        feedback = nil
                    }
                    .disabled(!KeyBindingAction.allCases.contains(where: bindings.isCustomized))
                    .buttonAffordance("Put every shortcut back to its default")
                    .accessibilityIdentifier("restore-default-shortcuts")
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear(perform: stopRecording)
    }

    @ViewBuilder
    private func row(for action: KeyBindingAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(action.title) {
                HStack(spacing: 6) {
                    if bindings.isCustomized(action) {
                        Button {
                            stopRecording()
                            if let rejection = bindings.reset(action) {
                                feedback = (action, "Cannot restore \(action.defaultShortcut.displayString). \(rejection.description)")
                            } else {
                                feedback = nil
                            }
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                        }
                        .buttonStyle(.borderless)
                        .buttonAffordance("Restore the default, \(action.defaultShortcut.displayString)")
                        .accessibilityLabel("Restore default shortcut for \(action.title)")
                    }
                    Button {
                        if recording == action {
                            stopRecording()
                        } else {
                            startRecording(action)
                        }
                    } label: {
                        Text(label(for: action))
                            .font(.body.monospaced())
                            .frame(minWidth: 110)
                            .foregroundStyle(recording == action ? Color.accentColor : .primary)
                    }
                    .buttonAffordance(
                        recording == action
                            ? "Press the new shortcut, Delete to remove it or Esc to cancel"
                            : "Change the shortcut for \(action.title)"
                    )
                    .accessibilityLabel("\(action.title) shortcut, \(label(for: action))")
                    .accessibilityIdentifier("shortcut-\(action.rawValue)")
                }
            }
            if let feedback, feedback.action == action {
                Text(feedback.text)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("shortcut-feedback-\(action.rawValue)")
            }
        }
    }

    private func label(for action: KeyBindingAction) -> String {
        if recording == action { return "Press shortcut…" }
        return bindings.shortcut(for: action)?.displayString ?? "None"
    }

    private func startRecording(_ action: KeyBindingAction) {
        stopRecording()
        recording = action
        feedback = nil
        // A local monitor sees the key press before any menu or toolbar shortcut does, so the
        // keys being recorded never also trigger the command they are currently bound to.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                handle(event)
            }
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    private func handle(_ event: NSEvent) {
        guard let action = recording else { return }
        let bareKey = event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
        switch event.keyCode {
        case 53 where bareKey:  // Esc cancels
            stopRecording()
            return
        case 51 where bareKey, 117 where bareKey:  // Delete removes the shortcut
            bindings.set(nil, for: action)
            feedback = nil
            stopRecording()
            return
        default:
            break
        }
        guard let shortcut = KeyShortcut.from(event: event) else { return }
        if let rejection = bindings.set(shortcut, for: action) {
            feedback = (action, "\(shortcut.displayString) was not saved. \(rejection.description)")
        } else {
            feedback = nil
        }
        stopRecording()
    }
}
