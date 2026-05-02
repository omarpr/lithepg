import SwiftUI

@main
struct LithePGApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(state: state)
        }
    }
}

struct RootView: View {
    @Bindable var state: AppState
    @State private var didStartSmoke = false

    private var smokeURL: String? {
        ProcessInfo.processInfo.environment["LITHEPG_UI_SMOKE_URL"]?.nilIfBlank
    }

    var body: some View {
        WorkspaceView(state: state)
            .frame(minWidth: 900, minHeight: 620)
            .navigationTitle(state.windowTitle)
            .sheet(isPresented: Binding(
                get: { smokeURL == nil && state.connectionState == .disconnected },
                set: { _ in }
            )) {
                ConnectSheet(state: state)
                    .interactiveDismissDisabled(true)
            }
            .task {
                guard !didStartSmoke, let smokeURL else { return }
                didStartSmoke = true
                await state.runUISmoke(url: smokeURL)
            }
            .onDisappear {
                Task { await state.disconnect() }
            }
    }
}

private extension AppState {
    func runUISmoke(url: String) async {
        editorText = ProcessInfo.processInfo.environment["LITHEPG_UI_SMOKE_QUERY"]?.nilIfBlank
            ?? "SELECT 42 AS lithepg_ui_smoke"
        await connect(url: url)
        guard isConnected else { return }
        await runCurrentQuery()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
