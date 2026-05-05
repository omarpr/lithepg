import AppKit
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
    @State private var launchStartedAt = Date()

    private var startupConfig: StartupConnectionConfig? {
        StartupConnectionConfig(environment: ProcessInfo.processInfo.environment)
    }

    var body: some View {
        WorkspaceView(state: state)
            .frame(minWidth: 900, minHeight: 620)
            .background(WindowStartupSizer())
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
                writeStartupMetricsIfRequested(startupConfig, startedAt: launchStartedAt, state: state)
            }
            .onDisappear {
                Task { await state.disconnect() }
            }
    }
}

struct WindowStartupSizer: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window, !context.coordinator.didResize else { return }
            context.coordinator.didResize = true
            let visibleFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
            guard let visibleFrame else { return }
            window.setFrame(visibleFrame, display: true, animate: false)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var didResize = false
    }
}

struct StartupConnectionConfig: Equatable {
    let url: String
    let query: String?
    let tls: Bool
    let tlsCAPath: String?
    let sshTarget: String?
    let metricsPath: String?

    init?(environment: [String: String]) {
        guard let url = (environment["LITHEPG_STARTUP_URL"] ?? environment["LITHEPG_UI_SMOKE_URL"])?.nilIfBlank else {
            return nil
        }
        self.url = url
        query = (environment["LITHEPG_STARTUP_QUERY"] ?? environment["LITHEPG_UI_SMOKE_QUERY"])?.nilIfBlank
        tls = Self.truthy(environment["LITHEPG_STARTUP_TLS"] ?? environment["LITHEPG_UI_SMOKE_TLS"])
        tlsCAPath = (environment["LITHEPG_STARTUP_TLS_CA_PATH"] ?? environment["LITHEPG_UI_SMOKE_TLS_CA_PATH"])?.nilIfBlank
        sshTarget = (environment["LITHEPG_STARTUP_SSH_TARGET"] ?? environment["LITHEPG_UI_SMOKE_SSH_TARGET"])?.nilIfBlank
        metricsPath = (environment["LITHEPG_STARTUP_METRICS_PATH"] ?? environment["LITHEPG_UI_SMOKE_METRICS_PATH"])?.nilIfBlank
    }

    private static func truthy(_ raw: String?) -> Bool {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y", "on": true
        default: false
        }
    }
}


private struct StartupMetrics: Codable, Equatable {
    let elapsedMs: Double
    let connected: Bool
    let queryRequested: Bool
    let resultRows: Int?
    let error: String?
}

@MainActor
private func writeStartupMetricsIfRequested(
    _ config: StartupConnectionConfig,
    startedAt: Date,
    state: AppState
) {
    guard let metricsPath = config.metricsPath else { return }
    let metrics = StartupMetrics(
        elapsedMs: Date().timeIntervalSince(startedAt) * 1_000,
        connected: state.isConnected,
        queryRequested: config.query != nil,
        resultRows: state.lastResult?.rowCount,
        error: state.lastError
    )
    do {
        let url = URL(fileURLWithPath: metricsPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(metrics).write(to: url)
    } catch {
        FileHandle.standardError.write(Data("failed to write startup metrics: \(error)\n".utf8))
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
