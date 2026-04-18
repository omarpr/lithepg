import Foundation

public actor SSHTunnel {
    public nonisolated let localPort: Int
    private let process: Process

    private init(localPort: Int, process: Process) {
        self.localPort = localPort
        self.process = process
    }

    public enum TunnelError: Error, Equatable {
        case sshBinaryNotFound
        case portAllocationFailed
        case tunnelDidNotOpen(underlying: String)
    }

    public static func open(
        sshHost: String,
        sshPort: Int,
        sshUser: String,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnel {
        let sshPath = "/usr/bin/ssh"
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            throw TunnelError.sshBinaryNotFound
        }

        let localPort = try allocateLocalPort()

        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = [
            "-N",
            "-L", "\(localPort):\(remoteHost):\(remotePort)",
            "-p", String(sshPort),
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ServerAliveInterval=30",
            "\(sshUser)@\(sshHost)",
        ]
        process.standardOutput = Pipe()
        process.standardError = stderrPipe

        try process.run()

        // Ensure the subprocess is never leaked on a non-success exit from this function
        // (including Task cancellation from `Task.sleep`).
        var handedOffToTunnel = false
        defer {
            if !handedOffToTunnel && process.isRunning {
                process.terminate()
                process.waitUntilExit()
            }
        }

        let deadline = Date().addingTimeInterval(5.0)
        while Date() < deadline {
            if isPortOpen(localPort) {
                handedOffToTunnel = true
                return SSHTunnel(localPort: localPort, process: process)
            }
            if !process.isRunning {
                throw TunnelError.tunnelDidNotOpen(underlying: drain(stderrPipe))
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }

        process.terminate()
        process.waitUntilExit()
        let trailingStderr = drain(stderrPipe)
        let detail = trailingStderr.isEmpty ? "timeout after 5s" : "timeout after 5s: \(trailingStderr)"
        throw TunnelError.tunnelDidNotOpen(underlying: detail)
    }

    public func close() async {
        if process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private static func allocateLocalPort() throws -> Int {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { throw TunnelError.portAllocationFailed }
        defer { Darwin.close(sock) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { throw TunnelError.portAllocationFailed }

        var boundAddr = sockaddr_in()
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let getResult = withUnsafeMutablePointer(to: &boundAddr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(sock, $0, &len)
            }
        }
        guard getResult == 0 else { throw TunnelError.portAllocationFailed }
        return Int(UInt16(bigEndian: boundAddr.sin_port))
    }

    private static func isPortOpen(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { Darwin.close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = UInt16(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// Reads stderr until EOF. Safe to call only after the writing process has exited
    /// (or been terminated) so the pipe's write end is closed — otherwise this would block.
    private static func drain(_ pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
