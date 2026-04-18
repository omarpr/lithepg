import Testing
import Foundation
@testable import lithepg

@Suite("SSHTunnel (integration)")
struct SSHTunnelTests {
    /// Format: "user@host:port" (e.g., "omar@bastion.example.com:22")
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

    private func parseTarget(_ s: String) throws -> (user: String, host: String, port: Int) {
        let parts = s.split(separator: "@")
        guard parts.count == 2 else { throw TestError.badTarget }
        let hostPort = parts[1].split(separator: ":")
        let host = String(hostPort[0])
        let port = hostPort.count == 2 ? Int(hostPort[1]) ?? 22 : 22
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
