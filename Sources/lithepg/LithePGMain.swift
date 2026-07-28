import Foundation
import LithePGAppUI
import LithePGCore

@main
struct LithePGMain {
    static func main() async {
        let args: Args
        do {
            args = try Args.parse(CommandLine.arguments)
        } catch Args.ParseError.help(let message) {
            print(message)
            exit(0)
        } catch Args.ParseError.usage(let message) {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(ErrorRedaction.redactCredentials(in: error))\n".utf8))
            exit(1)
        }

        guard let base = args.base else {
            LithePGApp.main()
            return
        }

        let config = ConnectionConfig(
            host: base.host,
            port: base.port,
            database: base.database,
            username: base.username,
            password: base.password,
            tlsMode: args.tlsMode ?? base.tlsMode,
            pinnedRootCertificatePath: args.tlsCA,
            sshConfig: args.ssh
        )

        let connector = PostgresConnector()
        do {
            // Without a deadline a server that accepts TCP and then stalls hangs the smoke
            // utility indefinitely, which is exactly when it is being used to diagnose things.
            let value = try await withDeadline(
                args.timeout,
                onExpiry: { try? await connector.shutdown() }
            ) {
                try await connector.runSelect1(config: config)
            }
            try await connector.shutdown()
            print("SELECT 1 → \(value)")
        } catch let expired as DeadlineExceededError {
            FileHandle.standardError.write(
                Data("error: no response within \(expired.seconds)s; the server accepted the connection but never completed the PostgreSQL handshake\n".utf8)
            )
            exit(1)
        } catch {
            try? await connector.shutdown()
            FileHandle.standardError.write(Data("error: \(ErrorRedaction.redactCredentials(in: error))\n".utf8))
            if ProcessInfo.processInfo.environment["LITHEPG_DEBUG_ERROR"] == "1" {
                FileHandle.standardError.write(
                    Data("debug: \(ErrorRedaction.redactCredentials(in: String(reflecting: error)))\n".utf8)
                )
            }
            exit(1)
        }
    }

}

private struct Args {
    let base: ConnectionConfig?
    let tlsMode: ConnectionConfig.TLSMode?
    let tlsCA: String?
    let ssh: ConnectionConfig.SSHConfig?
    let timeout: Duration

    enum ParseError: Error {
        case usage(String)
        case help(String)
    }

    static func parse(_ argv: [String]) throws -> Args {
        var url: String?
        var tlsMode: ConnectionConfig.TLSMode?
        var tlsCA: String?
        var timeoutSeconds = 15
        var sshRaw: String?

        var i = 1
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--url":
                guard i + 1 < argv.count else { throw ParseError.usage("--url needs a value") }
                url = argv[i + 1]
                i += 2
            case "--tls-mode":
                guard i + 1 < argv.count else { throw ParseError.usage("--tls-mode needs a value") }
                switch argv[i + 1] {
                case "disable": tlsMode = .disable
                case "prefer": tlsMode = .prefer
                case "require": tlsMode = .require
                case "verify-full": tlsMode = .verifyFull
                default:
                    throw ParseError.usage(
                        "--tls-mode must be disable, prefer, require, or verify-full"
                    )
                }
                i += 2
            case "--timeout":
                guard i + 1 < argv.count else { throw ParseError.usage("--timeout needs a value") }
                guard let parsed = Int(argv[i + 1]), parsed > 0 else {
                    throw ParseError.usage("--timeout must be a positive whole number of seconds")
                }
                timeoutSeconds = parsed
                i += 2
            case "--tls-ca":
                guard i + 1 < argv.count else { throw ParseError.usage("--tls-ca needs a value") }
                let value = argv[i + 1]
                guard !value.isEmpty else { throw ParseError.usage("--tls-ca value is empty") }
                tlsCA = value
                i += 2
            case "--ssh":
                guard i + 1 < argv.count else { throw ParseError.usage("--ssh needs a value") }
                sshRaw = argv[i + 1]
                i += 2
            case "--help", "-h":
                throw ParseError.help(
                    """
                    usage: lithepg --url <postgres://...> [--tls-mode <disable|prefer|require|verify-full>] \
                    [--tls-ca <path>] [--ssh user@host[:port]] [--timeout <seconds>]

                    Without --tls-mode the mode comes from the URL sslmode, or defaults to \
                    verify-full for remote hosts and disable for loopback.
                    """
                )
            default:
                throw ParseError.usage("unknown argument: \(arg)")
            }
        }

        guard let url else {
            return Args(base: nil, tlsMode: tlsMode, tlsCA: tlsCA, ssh: nil, timeout: .seconds(timeoutSeconds))
        }
        if tlsCA != nil && tlsMode != .verifyFull {
            // Outside verify-full nothing verifies certificates, so a pinned root would be
            // accepted and then silently ignored.
            throw ParseError.usage("--tls-ca requires --tls-mode verify-full")
        }
        if tlsMode == .verifyFull && sshRaw != nil {
            throw ParseError.usage("--tls-mode verify-full and --ssh together are not supported")
        }

        let base = try ConnectionConfig(url: url)
        let ssh = try sshRaw.map(Self.parseSSH)

        return Args(base: base, tlsMode: tlsMode, tlsCA: tlsCA, ssh: ssh, timeout: .seconds(timeoutSeconds))
    }

    private static func parseSSH(_ raw: String) throws -> ConnectionConfig.SSHConfig {
        let parts = raw.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[0].isEmpty else {
            throw ParseError.usage("--ssh format: user@host[:port]")
        }
        let hostPort = parts[1].split(separator: ":").map(String.init)
        let host: String
        let port: Int
        switch hostPort.count {
        case 1:
            host = hostPort[0]
            port = 22
        case 2:
            guard let p = Int(hostPort[1]) else {
                throw ParseError.usage("--ssh port is not an integer: \(hostPort[1])")
            }
            host = hostPort[0]
            port = p
        default:
            throw ParseError.usage("--ssh format: user@host[:port]")
        }
        guard !host.isEmpty else { throw ParseError.usage("--ssh host is empty") }
        guard (1...65535).contains(port) else {
            throw ParseError.usage("--ssh port out of range: \(port)")
        }
        return .init(host: host, port: port, user: parts[0])
    }
}
