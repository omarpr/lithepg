import SwiftUI

struct ErrorBanner: View {
    let message: String?
    var reconnect: (() -> Void)? = nil

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(message)
                    .textSelection(.enabled)
                Spacer()
                if let reconnect {
                    Button("Reconnect", action: reconnect)
                        .buttonStyle(.bordered)
                }
            }
            .font(.callout)
            .foregroundStyle(.red)
            .padding(10)
            .background(Color.red.opacity(0.08))
        }
    }
}
