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
    @State private var didRunStartup = false

    private var startupConfig: StartupConnectionConfig? {
        StartupConnectionConfig(environment: ProcessInfo.processInfo.environment)
    }

    var body: some View {
        WorkspaceView(state: state)
            .frame(minWidth: 900, minHeight: 620)
            .navigationTitle(state.windowTitle)
            .sheet(isPresented: Binding(
                get: { startupConfig == nil && state.connectionState == .disconnected },
                set: { _ in }
            )) {
                ConnectSheet(state: state)
                    .interactiveDismissDisabled(true)
            }
            .task {
                guard !didRunStartup, let startupConfig else { return }
                didRunStartup = true
                await state.runStartupConnection(startupConfig)
            }
            .onDisappear {
                Task { await state.disconnect() }
            }
    }
}

struct StartupConnectionConfig: Equatable {
    let url: String
    let query: String?
    let tls: Bool
    let tlsCAPath: String?
    let sshTarget: String?

    init?(environment: [String: String]) {
        guard let url = (environment["LITHEPG_STARTUP_URL"] ?? environment["LITHEPG_UI_SMOKE_URL"])?.nilIfBlank else {
            return nil
        }
        self.url = url
        query = (environment["LITHEPG_STARTUP_QUERY"] ?? environment["LITHEPG_UI_SMOKE_QUERY"])?.nilIfBlank
        tls = Self.truthy(environment["LITHEPG_STARTUP_TLS"] ?? environment["LITHEPG_UI_SMOKE_TLS"])
        tlsCAPath = (environment["LITHEPG_STARTUP_TLS_CA_PATH"] ?? environment["LITHEPG_UI_SMOKE_TLS_CA_PATH"])?.nilIfBlank
        sshTarget = (environment["LITHEPG_STARTUP_SSH_TARGET"] ?? environment["LITHEPG_UI_SMOKE_SSH_TARGET"])?.nilIfBlank
    }

    private static func truthy(_ raw: String?) -> Bool {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on": true
        default: false
        }
    }
}

private extension AppState {
    func runStartupConnection(_ config: StartupConnectionConfig) async {
        if let query = config.query {
            editorText = query
        }
        await connect(url: config.url, tls: config.tls, tlsCAPath: config.tlsCAPath, sshTarget: config.sshTarget)
        guard isConnected, config.query != nil else { return }
        await runCurrentQuery()
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
