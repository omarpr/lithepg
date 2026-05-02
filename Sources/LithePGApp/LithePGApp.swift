import SwiftUI

@main
struct LithePGApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup("LithePG") {
            WorkspaceView(state: state)
                .frame(minWidth: 900, minHeight: 620)
        }
    }
}
