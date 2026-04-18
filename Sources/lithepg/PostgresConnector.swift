import Foundation
import PostgresNIO
import NIOCore
import NIOPosix
import NIOSSL
import Logging

public actor PostgresConnector {
    private let eventLoopGroup: EventLoopGroup
    private let logger: Logger
    private var isShutdown = false

    public init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "lithepg.postgres")
    }

    /// Releases the event-loop group. Must be called before the connector is dropped.
    /// Async shutdown avoids the deinit/ELG-thread deadlock that `syncShutdownGracefully` would hit.
    public func shutdown() async throws {
        guard !isShutdown else { return }
        isShutdown = true
        try await eventLoopGroup.shutdownGracefully()
    }

    /// Opens a connection, runs `SELECT 1`, returns the integer, closes the connection.
    /// Resolves the effective host/port (honoring any SSH tunnel) before connecting.
    public func runSelect1(config: ConnectionConfig) async throws -> Int {
        let (effectiveHost, effectivePort, tunnel) = try await resolveTransport(config: config)

        var pgConfig = PostgresConnection.Configuration(
            host: effectiveHost,
            port: effectivePort,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: try makeTLS(for: config)
        )
        // SSH tunnels terminate locally; they always connect to 127.0.0.1 and should not
        // attempt TLS server-name verification against the SSH hostname.
        if tunnel != nil {
            pgConfig.tls = .disable
        }

        let connection: PostgresConnection
        do {
            connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
        } catch {
            await tunnel?.close()
            throw error
        }

        do {
            // `int4` widens to `Int` safely on the 64-bit macOS targets this project supports.
            let rows = try await connection.query("SELECT 1", logger: logger)
            for try await row in rows {
                let value = try row.decode(Int.self)
                try await connection.close()
                await tunnel?.close()
                return value
            }
            try await connection.close()
            await tunnel?.close()
            throw PostgresConnectorError.emptyResult
        } catch {
            try? await connection.close()
            await tunnel?.close()
            throw error
        }
    }

    // MARK: - Helpers

    private func resolveTransport(
        config: ConnectionConfig
    ) async throws -> (host: String, port: Int, tunnel: SSHTunnel?) {
        guard let ssh = config.sshConfig else {
            return (config.host, config.port, nil)
        }
        let tunnel = try await SSHTunnel.open(
            sshHost: ssh.host,
            sshPort: ssh.port,
            sshUser: ssh.user,
            remoteHost: config.host,
            remotePort: config.port
        )
        return ("127.0.0.1", tunnel.localPort, tunnel)
    }

    private func makeTLS(for config: ConnectionConfig) throws -> PostgresConnection.Configuration.TLS {
        switch config.tlsMode {
        case .disable:
            return .disable
        case .verifyFull:
            var tls = TLSConfiguration.makeClientConfiguration()
            if let path = config.tlsRootCertificatePath {
                // REPLACE the default trust roots, not add. On Darwin, the default path
                // runs through SecTrust, which rejects self-signed/internal-CA server certs
                // even when added as an additional anchor. A file-based trustRoots takes
                // the BoringSSL verification path and accepts the pinned CA.
                tls.trustRoots = .file(path)
            }
            let sslContext = try NIOSSLContext(configuration: tls)
            return .require(sslContext)
        }
    }
}

public enum PostgresConnectorError: Error, Equatable {
    case emptyResult
}
