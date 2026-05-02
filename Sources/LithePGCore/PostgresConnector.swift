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
    private var held: (connection: PostgresConnection, tunnel: SSHTunnel?)?

    public enum ExecuteError: Error, Equatable {
        case notConnected
        case alreadyConnected
    }

    public init() {
        self.eventLoopGroup = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.logger = Logger(label: "lithepg.postgres")
    }

    /// Releases the event-loop group. Must be called before the connector is dropped.
    /// Async shutdown avoids the deinit/ELG-thread deadlock that `syncShutdownGracefully` would hit.
    public func shutdown() async throws {
        guard !isShutdown else { return }
        await close()
        isShutdown = true
        try await eventLoopGroup.shutdownGracefully()
    }

    public func open(config: ConnectionConfig) async throws {
        guard held == nil else { throw ExecuteError.alreadyConnected }
        let (effectiveHost, effectivePort, tunnel) = try await resolveTransport(config: config)
        let pgConfig = PostgresConnection.Configuration(
            host: effectiveHost,
            port: effectivePort,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: try makeTLS(for: config)
        )

        do {
            let connection = try await PostgresConnection.connect(
                on: eventLoopGroup.next(),
                configuration: pgConfig,
                id: 1,
                logger: logger
            )
            held = (connection, tunnel)
        } catch {
            await tunnel?.close()
            throw error
        }
    }

    public func close() async {
        guard let current = held else { return }
        held = nil
        try? await current.connection.close()
        await current.tunnel?.close()
    }

    public func execute(_ sql: String) async throws -> QueryResult {
        guard let current = held else { throw ExecuteError.notConnected }
        let start = ContinuousClock.now
        let cap = 10_000
        var columns: [QueryResult.Column] = []
        var rows: [QueryResult.Row] = []
        var seenRows = 0

        let metadata = try await current.connection.query(
            PostgresQuery(unsafeSQL: sql),
            logger: logger
        ) { row in
            if columns.isEmpty {
                columns = row.map { cell in
                    QueryResult.Column(name: cell.columnName, typeName: String(describing: cell.dataType))
                }
            }

            if rows.count < cap {
                let cells = row.map(Self.renderCell(_:))
                rows.append(QueryResult.Row(id: rows.count, cells: cells))
            }
            seenRows += 1
        }.get()

        let status: QueryResult.Status
        if !rows.isEmpty || !columns.isEmpty {
            status = .rows
        } else if metadata.command == "SELECT" {
            status = .empty
        } else {
            status = .command(
                tag: metadata.command,
                affected: metadata.rows ?? 0
            )
        }

        return QueryResult(
            columns: columns,
            rows: rows,
            rowCount: rows.count,
            elapsed: ContinuousClock.now - start,
            status: status,
            truncated: seenRows > cap
        )
    }

    /// Opens a connection, runs `SELECT 1`, returns the integer, closes the connection.
    /// Resolves the effective host/port (honoring any SSH tunnel) before connecting.
    public func runSelect1(config: ConnectionConfig) async throws -> Int {
        let (effectiveHost, effectivePort, tunnel) = try await resolveTransport(config: config)

        // TLS-through-SSH-tunnel is rejected at the CLI boundary (Args.parse) because
        // the tunnel terminates at 127.0.0.1 and SNI for the original hostname would
        // mismatch. Library callers that set both will get a TLS handshake failure
        // here — preferable to the earlier silent downgrade, which hid the conflict.
        let pgConfig = PostgresConnection.Configuration(
            host: effectiveHost,
            port: effectivePort,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: try makeTLS(for: config)
        )

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

    static func renderCell(_ cell: PostgresCell) -> QueryResult.Cell {
        guard cell.bytes != nil else { return .null }

        switch cell.dataType {
        case .text, .varchar, .bpchar, .name, .unknown, .json, .jsonb:
            if let value = try? cell.decode(String.self) { return .text(value) }
        case .int2:
            if let value = try? cell.decode(Int16.self) { return .text(String(value)) }
        case .int4:
            if let value = try? cell.decode(Int32.self) { return .text(String(value)) }
            if let value = try? cell.decode(Int.self) { return .text(String(value)) }
        case .int8:
            if let value = try? cell.decode(Int64.self) { return .text(String(value)) }
        case .bool:
            if let value = try? cell.decode(Bool.self) { return .text(value ? "true" : "false") }
        case .float4:
            if let value = try? cell.decode(Float.self) { return .text(String(value)) }
        case .float8:
            if let value = try? cell.decode(Double.self) { return .text(String(value)) }
        default:
            if let value = try? cell.decode(String.self) { return .text(value) }
        }

        return .text("<\(cell.bytes?.readableBytes ?? 0) bytes>")
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
            if let path = config.pinnedRootCertificatePath {
                // Preflight: surface a clear error early rather than an opaque NIOSSL IOError later.
                guard !path.isEmpty, FileManager.default.isReadableFile(atPath: path) else {
                    throw PostgresConnectorError.pinnedRootCertificateUnreadable(path: path)
                }
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
    case pinnedRootCertificateUnreadable(path: String)
}
