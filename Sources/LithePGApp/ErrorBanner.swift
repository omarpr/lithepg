import SwiftUI

struct ErrorBanner: View {
    let message: String?
    var reconnect: (() -> Void)? = nil

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .accessibilityHidden(true)
                Text(message)
                    .textSelection(.enabled)
                    .accessibilityLabel("Error: \(message)")
                Spacer()
                if let reconnect {
                    Button("Reconnect", action: reconnect)
                        .buttonStyle(.bordered)
                        .buttonAffordance("Reconnect to the previous database")
                }
            }
            .font(.callout)
            .foregroundStyle(.red)
            .padding(10)
            .background(Color.red.opacity(0.08))
            .accessibilityIdentifier("error-banner")
        }
    }
}
