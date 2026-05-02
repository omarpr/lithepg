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

    var body: some View {
        WorkspaceView(state: state)
            .frame(minWidth: 900, minHeight: 620)
            .navigationTitle(state.windowTitle)
            .sheet(isPresented: Binding(
                get: { state.connectionState == .disconnected },
                set: { _ in }
            )) {
                ConnectSheet(state: state)
                    .interactiveDismissDisabled(true)
            }
            .onDisappear {
                Task { await state.disconnect() }
            }
    }
}
