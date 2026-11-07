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

    public enum ExecuteError: Error, Equatable, CustomStringConvertible {
        case notConnected
        case alreadyConnected
        /// The server or network closed the connection. Reconnecting is the only way forward.
        case connectionLost

        public var description: String {
            switch self {
            case .notConnected: "Not connected"
            case .alreadyConnected: "Already connected"
            case .connectionLost: "The connection to the server was lost."
            }
        }
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
        let pgConfig = try Self.connectionConfiguration(
            for: config,
            host: effectiveHost,
            port: effectivePort
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

    /// False once the server or network has closed the held connection.
    public var isConnectionAlive: Bool {
        guard let held else { return false }
        return !held.connection.isClosed
    }

    /// Returns once the held connection closes, for whatever reason. Returns at once when
    /// nothing is held. Lets the app notice a dropped connection before the next query.
    public func waitUntilClosed() async {
        guard let closeFuture = held?.connection.closeFuture else { return }
        try? await closeFuture.get()
    }

    /// Where each column of a query's result comes from, without returning any rows.
    ///
    /// Only PostgresNIO's async row sequence exposes the RowDescription table OID and
    /// attribute number, and it does not expose the command tag `execute` needs, so this is a
    /// separate call. `sql` is wrapped as `SELECT * FROM (sql) LIMIT 0`: PostgreSQL resolves
    /// column origins through the subquery, and LIMIT 0 stops the executor before any row is
    /// produced. Statements that cannot be a subquery (anything but a query) fail here.
    public func describeResultColumns(of sql: String) async throws -> [ResultColumnSource] {
        guard let current = held else { throw ExecuteError.notConnected }
        guard !current.connection.isClosed else { throw ExecuteError.connectionLost }
        let body = ResultEditing.trimmedStatement(sql)
        let probe = PostgresQuery(unsafeSQL: "SELECT * FROM (\n\(body)\n) AS lithepg_edit_probe LIMIT 0")
        let connection = current.connection
        let logger = self.logger
        let outcome = connection.eventLoop.makePromise(of: [ResultColumnSource].self)
        Task {
            do {
                let rows = try await connection.query(probe, logger: logger)
                let sources = rows.columns.map {
                    ResultColumnSource(
                        name: $0.name,
                        tableOID: UInt32(bitPattern: $0.tableOID),
                        attributeNumber: Int($0.columnAttributeNumber),
                        typeOID: $0.dataType.rawValue
                    )
                }
                for try await _ in rows {}  // drain the (empty) stream so the connection is free
                outcome.succeed(sources)
            } catch {
                outcome.fail(error)
            }
        }
        // Same guard as execute: a drop mid-call would otherwise leave this pending forever.
        connection.closeFuture.whenComplete { _ in
            outcome.fail(ExecuteError.connectionLost)
        }
        return try await outcome.futureResult.get()
    }

    public func execute(_ query: PostgresQuery) async throws -> QueryResult {
        guard let current = held else { throw ExecuteError.notConnected }
        // PostgresNIO (through 1.33.2) never completes a query sent on a channel the server
        // already closed, so asking would hang the caller forever. Check first.
        guard !current.connection.isClosed else { throw ExecuteError.connectionLost }
        let start = ContinuousClock.now
        let cap = 10_000
        let accumulator = QueryAccumulator(cap: cap)

        let queryFuture = current.connection.query(
            query,
            logger: logger
        ) { row in
            accumulator.append(row)
        }
        // Close the remaining window: a drop between the check above and the write leaves the
        // query pending forever, so the close itself fails it. A promise ignores every
        // completion after the first, so whichever side lands second is a no-op.
        let outcome = current.connection.eventLoop.makePromise(of: PostgresQueryMetadata.self)
        queryFuture.cascade(to: outcome)
        current.connection.closeFuture.whenComplete { _ in
            outcome.fail(ExecuteError.connectionLost)
        }
        let metadata = try await outcome.futureResult.get()
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
        let pgConfig = try Self.connectionConfiguration(
            for: config,
            host: effectiveHost,
            port: effectivePort
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
        case .text, .varchar, .bpchar, .name, .unknown, .json:
            if let value = decodeText(cell) { return .text(value) }
        case .jsonb:
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
            if let value = formatNumeric(cell) { return .text(value) }
        default:
            if let value = try? cell.decode(String.self) { return .text(value) }
        }

        return .text("<\(cell.bytes?.readableBytes ?? 0) bytes>")
    }

    /// Formats a numeric the way PostgreSQL prints it, keeping the column's scale.
    ///
    /// Decoding to `Decimal` dropped trailing zeros (`9480.00` showed as `9480`), and
    /// PostgresNIO's own formatter never pads the fraction out to the scale and does not
    /// handle NaN or Infinity. The binary layout is ndigits, weight, sign and display scale
    /// (each 16 bits), then `ndigits` base-10000 digits, the first worth 10000^weight.
    static func formatNumeric(_ cell: PostgresCell) -> String? {
        guard var buffer = cell.bytes else { return nil }
        if cell.format == .text {
            return buffer.readString(length: buffer.readableBytes)
        }
        guard let count = buffer.readInteger(as: Int16.self),
            let weight = buffer.readInteger(as: Int16.self),
            let sign = buffer.readInteger(as: UInt16.self),
            let scale = buffer.readInteger(as: UInt16.self),
            count >= 0
        else { return nil }
        switch sign {
        case 0xC000: return "NaN"
        case 0xD000: return "Infinity"
        case 0xF000: return "-Infinity"
        case 0x0000, 0x4000: break
        default: return nil
        }
        var digits: [Int] = []
        digits.reserveCapacity(Int(count))
        for _ in 0..<count {
            guard let digit = buffer.readInteger(as: Int16.self), (0..<10_000).contains(digit) else {
                return nil
            }
            digits.append(Int(digit))
        }
        func digit(at index: Int) -> Int {
            digits.indices.contains(index) ? digits[index] : 0
        }
        func padded(_ value: Int) -> String {
            let text = String(value)
            return String(repeating: "0", count: 4 - text.count) + text
        }

        var integer = ""
        if weight < 0 {
            integer = "0"
        } else {
            for index in 0...Int(weight) {
                integer += index == 0 ? String(digit(at: index)) : padded(digit(at: index))
            }
        }
        var fraction = ""
        var index = Int(weight) + 1
        while fraction.count < Int(scale) {
            fraction += padded(digit(at: index))
            index += 1
        }
        fraction = String(fraction.prefix(Int(scale)))

        let isZero = digits.allSatisfy { $0 == 0 }
        let negative = sign == 0x4000 && !isZero
        return (negative ? "-" : "") + integer + (fraction.isEmpty ? "" : "." + fraction)
    }

    /// Text bytes as UTF-8, or as Latin-1 when they are not valid UTF-8. A SQL_ASCII database
    /// performs no conversion, so it can hand back legacy single-byte text even though the
    /// session asked for UTF-8. Latin-1 maps every byte, so this never invents `�`.
    private static func decodeText(_ cell: PostgresCell) -> String? {
        guard let bytes = cell.bytes, cell.format == .binary || cell.format == .text else {
            return nil
        }
        let view = bytes.readableBytesView
        if let utf8 = String(bytes: view, encoding: .utf8) { return utf8 }
        return String(bytes: view, encoding: .isoLatin1)
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

    /// Builds the PostgresNIO configuration shared by every connection path.
    ///
    /// Always asks for UTF-8. Without it the server sends text in the database's own encoding,
    /// so a LATIN1 or WIN1252 database shows accents as replacement characters, and text sent
    /// from LithePG is stored with the wrong bytes.
    static func connectionConfiguration(
        for config: ConnectionConfig,
        host: String,
        port: Int
    ) throws -> PostgresConnection.Configuration {
        var pgConfig = PostgresConnection.Configuration(
            host: host,
            port: port,
            username: config.username,
            password: config.password,
            database: config.database,
            tls: try makeTLS(for: config)
        )
        pgConfig.options.additionalStartupParameters.append(("client_encoding", "UTF8"))
        return pgConfig
    }

    // Internal and static rather than private so the mode mapping is directly testable.
    // It reads only its argument, so it needs no actor isolation.
    static func makeTLS(for config: ConnectionConfig) throws -> PostgresConnection.Configuration.TLS {
        switch config.tlsMode {
        case .disable:
            return .disable
        case .prefer:
            // PostgresNIO's `.prefer` already implements libpq's fallback: attempt TLS, and
            // drop to an insecure connection if the server refuses. No retry logic of our own.
            return .prefer(try makeSSLContext(verifying: false, pinnedRootCertificatePath: nil))
        case .require:
            return .require(try makeSSLContext(verifying: false, pinnedRootCertificatePath: nil))
        case .verifyFull:
            return .require(
                try makeSSLContext(
                    verifying: true,
                    pinnedRootCertificatePath: config.pinnedRootCertificatePath
                )
            )
        }
    }

    private static func makeSSLContext(
        verifying: Bool,
        pinnedRootCertificatePath: String?
    ) throws -> NIOSSLContext {
        var tls = TLSConfiguration.makeClientConfiguration()
        if verifying {
            if let path = pinnedRootCertificatePath {
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
        } else {
            // prefer and require encrypt without authenticating the server, so they cannot
            // detect an active machine in the middle. Only ever reached by an explicit choice.
            tls.certificateVerification = .none
        }
        return try NIOSSLContext(configuration: tls)
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
