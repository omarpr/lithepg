import Testing
import Foundation
@testable import LithePGCore

@Suite("SSHTunnel (integration)")
struct SSHTunnelTests {
    /// Format: "user@host:port" (e.g., "developer@bastion.example.com:22")
    static var sshTarget: String? {
        ProcessInfo.processInfo.environment["SSH_TEST_TARGET"]
    }

    @Test(
        "opens a tunnel to an echo port, then closes cleanly",
        .enabled(if: sshTarget != nil)
    )
    func openAndClose() async throws {
        let (user, host, port) = try parseTarget(Self.sshTarget!)
        let tunnel = try await SSHTunnel.open(
            sshHost: host,
            sshPort: port,
            sshUser: user,
            remoteHost: "127.0.0.1",
            remotePort: 22
        )
        #expect(tunnel.localPort > 0)
        let listening = isPortOpen(port: tunnel.localPort, host: "127.0.0.1")
        #expect(listening)
        await tunnel.close()
    }

    @Test("ssh arguments require pre-trusted host keys")
    func argumentsRequireKnownHostKey() {
        let arguments = SSHTunnel.sshArguments(
            localPort: 15432,
            remoteHost: "db.internal",
            remotePort: 5432,
            sshHost: "bastion.example.com",
            sshPort: 22,
            sshUser: "omar"
        )

        #expect(arguments.contains("StrictHostKeyChecking=yes"))
        #expect(!arguments.contains("StrictHostKeyChecking=accept-new"))
    }

    /// Strict parser — a malformed SSH_TEST_TARGET should fail loudly rather than
    /// silently falling back to port 22.
    private func parseTarget(_ s: String) throws -> (user: String, host: String, port: Int) {
        let parts = s.split(separator: "@")
        guard parts.count == 2 else { throw TestError.badTarget }
        let hostPort = parts[1].split(separator: ":")
        let host = String(hostPort[0])
        let port: Int
        switch hostPort.count {
        case 1:
            port = 22
        case 2:
            guard let p = Int(hostPort[1]) else { throw TestError.badTarget }
            port = p
        default:
            throw TestError.badTarget
        }
        return (String(parts[0]), host, port)
    }

    private func isPortOpen(port: Int, host: String) -> Bool {
        let socket = socket(AF_INET, SOCK_STREAM, 0)
        defer { Darwin.close(socket) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        inet_pton(AF_INET, host, &addr.sin_addr)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    enum TestError: Error { case badTarget }
}
