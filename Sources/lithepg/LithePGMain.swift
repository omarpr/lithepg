import Foundation

@main
struct LithePGMain {
    static func main() async {
        do {
            let args = try Args.parse(CommandLine.arguments)
            let config = ConnectionConfig(
                host: args.base.host,
                port: args.base.port,
                database: args.base.database,
                username: args.base.username,
                password: args.base.password,
                tlsMode: args.tls ? .verifyFull : args.base.tlsMode,
                pinnedRootCertificatePath: args.tlsCA,
                sshConfig: args.ssh
            )

            let connector = PostgresConnector()
            let value = try await connector.runSelect1(config: config)
            print("SELECT 1 → \(value)")
        } catch Args.ParseError.help(let message) {
            print(message)
            exit(0)
        } catch Args.ParseError.usage(let message) {
            FileHandle.standardError.write(Data("\(message)\n".utf8))
            exit(2)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}

private struct Args {
    let base: ConnectionConfig
    let tls: Bool
    let tlsCA: String?
    let ssh: ConnectionConfig.SSHConfig?

    enum ParseError: Error {
        case usage(String)
        case help(String)
    }

    static func parse(_ argv: [String]) throws -> Args {
        var url: String?
        var tls = false
        var tlsCA: String?
        var sshRaw: String?

        var i = 1
        while i < argv.count {
            let arg = argv[i]
            switch arg {
            case "--url":
                guard i + 1 < argv.count else { throw ParseError.usage("--url needs a value") }
                url = argv[i + 1]
                i += 2
            case "--tls":
                tls = true
                i += 1
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
                    "usage: lithepg --url <postgres://...> [--tls] [--tls-ca <path>] [--ssh user@host[:port]]"
                )
            default:
                throw ParseError.usage("unknown argument: \(arg)")
            }
        }

        guard let url else { throw ParseError.usage("--url is required") }
        if tlsCA != nil && !tls {
            throw ParseError.usage("--tls-ca requires --tls")
        }

        let base = try ConnectionConfig(url: url)
        let ssh = try sshRaw.map(Self.parseSSH)

        return Args(base: base, tls: tls, tlsCA: tlsCA, ssh: ssh)
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
        return .init(host: host, port: port, user: parts[0])
    }
}
