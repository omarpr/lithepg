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
        try await execute(PostgresQuery(unsafeSQL: sql))
    }

    /// Executes a pre-built Postgres query so internal features can use PostgresNIO's
    /// parameterized query APIs instead of interpolating values into raw SQL strings.
    public func executeBound(_ query: PostgresQuery) async throws -> QueryResult {
        try await execute(query)
    }

    public func execute(_ query: PostgresQuery) async throws -> QueryResult {
        guard let current = held else { throw ExecuteError.notConnected }
        let start = ContinuousClock.now
        let cap = 10_000
        let accumulator = QueryAccumulator(cap: cap)

        let metadata = try await current.connection.query(
            query,
            logger: logger
        ) { row in
            accumulator.append(row)
        }.get()
        let snapshot = accumulator.snapshot()

        let status: QueryResult.Status
        if !snapshot.rows.isEmpty || !snapshot.columns.isEmpty {
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
            columns: snapshot.columns,
            rows: snapshot.rows,
            rowCount: snapshot.rows.count,
            elapsed: ContinuousClock.now - start,
            status: status,
            truncated: snapshot.seenRows > cap
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

    /// Postgres-style display for timestamps: `2026-07-11 14:03:22.123Z`.
    /// `ISO8601FormatStyle` is Sendable, unlike `DateFormatter`, so it can be
    /// shared safely across the actor's callers.
    private static let timestampStyle = Date.ISO8601FormatStyle(
        dateSeparator: .dash,
        dateTimeSeparator: .space,
        timeSeparator: .colon,
        includingFractionalSeconds: true
    )
    private static let dateOnlyStyle = Date.ISO8601FormatStyle().year().month().day()

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
        case .timestamptz:
            if let value = try? cell.decode(Date.self) {
                return .text(value.formatted(Self.timestampStyle))
            }
        case .timestamp:
            // Naive timestamps carry no zone; drop the misleading Z suffix.
            if let value = try? cell.decode(Date.self) {
                let text = value.formatted(Self.timestampStyle)
                return .text(text.hasSuffix("Z") ? String(text.dropLast()) : text)
            }
        case .date:
            if let value = try? cell.decode(Date.self) {
                return .text(value.formatted(Self.dateOnlyStyle))
            }
        case .uuid:
            if let value = try? cell.decode(UUID.self) {
                return .text(value.uuidString.lowercased())
            }
        case .numeric:
            if let value = try? cell.decode(Decimal.self) { return .text("\(value)") }
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


private final class QueryAccumulator: @unchecked Sendable {
    private let cap: Int
    private let lock = NSLock()
    private var columns: [QueryResult.Column] = []
    private var rows: [QueryResult.Row] = []
    private var seenRows = 0

    init(cap: Int) {
        self.cap = cap
    }

    func append(_ row: PostgresRow) {
        lock.lock()
        defer { lock.unlock() }
        if columns.isEmpty {
            columns = row.map { cell in
                QueryResult.Column(name: cell.columnName, typeName: String(describing: cell.dataType))
            }
        }
        if rows.count < cap {
            let cells = row.map(PostgresConnector.renderCell(_:))
            rows.append(QueryResult.Row(id: rows.count, cells: cells))
        }
        seenRows += 1
    }

    func snapshot() -> (columns: [QueryResult.Column], rows: [QueryResult.Row], seenRows: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (columns, rows, seenRows)
    }
}

public enum PostgresConnectorError: Error, Equatable {
    case emptyResult
    case pinnedRootCertificateUnreadable(path: String)
}
