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
        case unsafeArgument(String)
    }

    public static func open(
        sshHost: String,
        sshPort: Int,
        sshUser: String,
        remoteHost: String,
        remotePort: Int
    ) async throws -> SSHTunnel {
        // `SSHConfig.parse` already refuses these, but library callers can build a config by
        // hand, and a value starting with `-` would reach ssh as an option.
        for value in [sshHost, sshUser, remoteHost]
        where !ConnectionConfig.SSHConfig.isSafeSSHValue(value) || value.isEmpty {
            throw TunnelError.unsafeArgument(value)
        }
        let sshPath = "/usr/bin/ssh"
        guard FileManager.default.isExecutableFile(atPath: sshPath) else {
            throw TunnelError.sshBinaryNotFound
        }

        let localPort = try allocateLocalPort()

        let process = Process()
        let stderrPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: sshPath)
        process.arguments = sshArguments(
            localPort: localPort,
            remoteHost: remoteHost,
            remotePort: remotePort,
            sshHost: sshHost,
            sshPort: sshPort,
            sshUser: sshUser
        )
        process.qualityOfService = .userInitiated
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

    static func sshArguments(
        localPort: Int,
        remoteHost: String,
        remotePort: Int,
        sshHost: String,
        sshPort: Int,
        sshUser: String
    ) -> [String] {
        // The forward binds 127.0.0.1 explicitly, the address `isPortOpen` probes, so ssh
        // never listens on another interface. An IPv6 remote host needs brackets in `-L`.
        let forwardHost = remoteHost.contains(":") ? "[\(remoteHost)]" : remoteHost
        return [
            "-N",
            "-L", "127.0.0.1:\(localPort):\(forwardHost):\(remotePort)",
            "-p", String(sshPort),
            "-l", sshUser,
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=yes",
            // No terminal to answer a password or passphrase prompt, so fail fast instead of
            // waiting out the open timeout. Keys from ssh-agent still work.
            "-o", "BatchMode=yes",
            "-o", "ServerAliveInterval=30",
            // Everything after `--` is the destination, so a host can never be read as an option.
            "--",
            sshHost,
        ]
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
