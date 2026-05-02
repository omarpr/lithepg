import SwiftUI

struct ConnectSheet: View {
    @Bindable var state: AppState
    @State private var url: String = ProcessInfo.processInfo.environment["POSTGRES_URL"] ?? ""
    @State private var tls = ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] != nil
    @State private var tlsCAPath: String = ProcessInfo.processInfo.environment["POSTGRES_TLS_CA"] ?? ""
    @State private var useSSH = ProcessInfo.processInfo.environment["POSTGRES_SSH"] != nil
    @State private var sshTarget: String = ProcessInfo.processInfo.environment["POSTGRES_SSH"] ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "cylinder.split.1x2")
                    .font(.title)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text("Connect to Postgres")
                        .font(.title2.bold())
                    Text("Connection info stays in memory for v0.2a.")
                        .foregroundStyle(.secondary)
                }
            }

            TextField("postgres://user:password@host:5432/database", text: $url)
                .textFieldStyle(.roundedBorder)

            Toggle("TLS verify-full", isOn: $tls)
            if tls {
                TextField("CA certificate path", text: $tlsCAPath)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle("SSH tunnel", isOn: $useSSH)
                .disabled(tls)
            if useSSH && !tls {
                TextField("user@host[:port]", text: $sshTarget)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = state.lastError {
                ErrorBanner(message: error)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Spacer()
                Button {
                    Task {
                        await state.connect(
                            url: url,
                            tls: tls,
                            tlsCAPath: tls ? tlsCAPath : nil,
                            sshTarget: useSSH && !tls ? sshTarget : nil
                        )
                    }
                } label: {
                    if state.connectionState == .connecting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Connect")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.connectionState == .connecting)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
