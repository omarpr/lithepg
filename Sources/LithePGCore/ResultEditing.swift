import Foundation
import PostgresNIO

/// Where one result column comes from, as PostgreSQL's RowDescription reports it.
public struct ResultColumnSource: Sendable, Equatable {
    public let name: String
    /// Zero when the column is not a plain reference to a table column (an expression, a
    /// literal, an aggregate).
    public let tableOID: UInt32
    public let attributeNumber: Int
    public let typeOID: UInt32

    public init(name: String, tableOID: UInt32, attributeNumber: Int, typeOID: UInt32) {
        self.name = name
        self.tableOID = tableOID
        self.attributeNumber = attributeNumber
        self.typeOID = typeOID
    }
}

/// A table column as the catalog describes it.
public struct TableColumnInfo: Sendable, Equatable {
    public let attributeNumber: Int
    public let name: String
    /// `format_type` output, safe to use as a cast target.
    public let typeName: String
    public let typeOID: UInt32
    public let isGenerated: Bool
    public let isIdentityAlways: Bool
    public let isPrimaryKey: Bool

    public init(
        attributeNumber: Int, name: String, typeName: String, typeOID: UInt32,
        isGenerated: Bool = false, isIdentityAlways: Bool = false, isPrimaryKey: Bool = false
    ) {
        self.attributeNumber = attributeNumber
        self.name = name
        self.typeName = typeName
        self.typeOID = typeOID
        self.isGenerated = isGenerated
        self.isIdentityAlways = isIdentityAlways
        self.isPrimaryKey = isPrimaryKey
    }
}

public struct TableInfo: Sendable, Equatable {
    public let oid: UInt32
    public let schema: String
    public let name: String
    /// pg_class.relkind: "r" table, "p" partitioned table, "v" view, "m" materialized view...
    public let kind: String
    public let columns: [TableColumnInfo]

    public init(oid: UInt32, schema: String, name: String, kind: String, columns: [TableColumnInfo]) {
        self.oid = oid
        self.schema = schema
        self.name = name
        self.kind = kind
        self.columns = columns
    }
}

/// Everything needed to update one column of one row, identified by its primary key.
public struct ResultEditTarget: Sendable, Equatable {
    public struct KeyPart: Sendable, Equatable {
        public let name: String
        public let typeName: String
        /// Where the key value sits in each result row.
        public let resultColumn: Int
    }

    public let schema: String
    public let table: String
    public let column: String
    public let columnType: String
    public let resultColumn: Int
    public let key: [KeyPart]
    /// When the displayed value round-trips exactly, the UPDATE also requires the stored value
    /// to still equal it, so a row someone changed since it was loaded is never overwritten.
    public let checksOriginalValue: Bool

    public var qualifiedTable: String {
        "\(ResultEditing.quoted(schema)).\(ResultEditing.quoted(table))"
    }
}

public enum ResultEditability: Sendable, Equatable {
    case editable(ResultEditTarget)
    case readOnly(reason: String)
}

public enum ResultEditError: Error, Equatable, CustomStringConvertible {
    case missingKeyValue
    case rowChanged
    case notEditable(String)

    public var description: String {
        switch self {
        case .missingKeyValue:
            "This row has no primary key value, so it cannot be matched to a stored row."
        case .rowChanged:
            "Nothing was updated. The row was changed or deleted since these results were loaded. Run the query again to see its current value."
        case .notEditable(let reason):
            reason
        }
    }
}

/// Inline editing of query results, written back with one primary-key UPDATE per cell.
///
/// A cell is editable only when its column is a plain column of an ordinary table that has a
/// primary key, and every primary key column is in the same result. The UPDATE matches the
/// whole primary key, so it can change at most one row, and it returns the stored value so
/// the grid shows what the database now holds.
public enum ResultEditing {
    /// Types whose displayed text converts back to exactly the stored value. Only these can
    /// identify a row or guard against overwriting a concurrent change.
    static let exactTypeOIDs: Set<UInt32> = [
        16,  // bool
        19,  // name
        20, 21, 23,  // int8, int2, int4
        25, 1042, 1043,  // text, bpchar, varchar
        1082,  // date
        1700,  // numeric
        2950,  // uuid
        3802,  // jsonb
    ]

    /// Only queries can have their result columns traced back to tables.
    public static func isQueryStatement(_ sql: String) -> Bool {
        let tokens = SQLLexer.tokens(Array(sql.utf16))
        guard case .word(let first) = tokens.first else { return false }
        return ["select", "with", "table", "values"].contains(first.lowercased())
    }

    /// The statement without surrounding whitespace or a trailing semicolon, ready to nest.
    public static func trimmedStatement(_ sql: String) -> String {
        var body = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        while body.hasSuffix(";") {
            body.removeLast()
            body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return body
    }

    /// Decides, per result column, whether it can be edited and why not.
    public static func editability(
        sources: [ResultColumnSource],
        tables: [UInt32: TableInfo]
    ) -> [ResultEditability] {
        sources.enumerated().map { index, source in
            guard source.tableOID != 0, source.attributeNumber > 0, let table = tables[source.tableOID] else {
                return .readOnly(reason: "This column is computed by the query, so it has no stored value to update.")
            }
            guard table.kind == "r" || table.kind == "p" else {
                return .readOnly(reason: "\(table.name) is a view, not a table, so it is not edited here.")
            }
            guard let column = table.columns.first(where: { $0.attributeNumber == source.attributeNumber }) else {
                return .readOnly(reason: "This column could not be found in \(table.name).")
            }
            if column.isGenerated {
                return .readOnly(reason: "\(column.name) is a generated column, so PostgreSQL computes its value.")
            }
            if column.isIdentityAlways {
                return .readOnly(reason: "\(column.name) is an identity column that PostgreSQL always assigns.")
            }
            let keyColumns = table.columns.filter(\.isPrimaryKey)
            guard !keyColumns.isEmpty else {
                return .readOnly(reason: "\(table.name) has no primary key, so a row cannot be identified safely.")
            }
            var key: [ResultEditTarget.KeyPart] = []
            var missing: [String] = []
            for keyColumn in keyColumns {
                let position = sources.firstIndex {
                    $0.tableOID == source.tableOID && $0.attributeNumber == keyColumn.attributeNumber
                }
                guard let position else {
                    missing.append(keyColumn.name)
                    continue
                }
                guard exactTypeOIDs.contains(keyColumn.typeOID) else {
                    return .readOnly(
                        reason: "The primary key of \(table.name) uses \(keyColumn.typeName), which cannot be matched exactly from the displayed value."
                    )
                }
                key.append(.init(name: keyColumn.name, typeName: keyColumn.typeName, resultColumn: position))
            }
            guard missing.isEmpty else {
                let list = missing.joined(separator: ", ")
                return .readOnly(
                    reason: "Add the primary key (\(list)) of \(table.name) to the query to edit this column."
                )
            }
            return .editable(
                ResultEditTarget(
                    schema: table.schema,
                    table: table.name,
                    column: column.name,
                    columnType: column.typeName,
                    resultColumn: index,
                    key: key,
                    checksOriginalValue: exactTypeOIDs.contains(column.typeOID)
                ))
        }
    }

    /// The UPDATE for one cell, with every value bound as a parameter.
    ///
    /// `newValue` nil writes NULL. Values travel as text and are cast to the column's own type
    /// by PostgreSQL, so its input rules apply exactly as if typed into psql.
    public static func makeUpdate(
        target: ResultEditTarget,
        row: QueryResult.Row,
        newValue: String?
    ) throws -> (query: PostgresQuery, preview: String) {
        var bindings = PostgresBindings()
        var preview: [String: String] = [:]
        var parameter = 0
        func bind(_ value: String?) -> String {
            parameter += 1
            bindings.append(value)
            let placeholder = "$\(parameter)"
            preview[placeholder] = value.map(literal) ?? "NULL"
            return placeholder
        }

        let column = quoted(target.column)
        let setValue = bind(newValue)
        var conditions: [String] = []
        for part in target.key {
            guard row.cells.indices.contains(part.resultColumn),
                case .text(let keyValue) = row.cells[part.resultColumn]
            else { throw ResultEditError.missingKeyValue }
            conditions.append("\(quoted(part.name)) = \(bind(keyValue))::\(part.typeName)")
        }
        if target.checksOriginalValue, row.cells.indices.contains(target.resultColumn) {
            let original: String?
            switch row.cells[target.resultColumn] {
            case .text(let value): original = value
            case .null: original = nil
            }
            conditions.append("\(column) IS NOT DISTINCT FROM \(bind(original))::\(target.columnType)")
        }

        let sql = """
            WITH lithepg_updated AS (
              UPDATE \(target.qualifiedTable)
              SET \(column) = \(setValue)::\(target.columnType)
              WHERE \(conditions.joined(separator: "\n    AND "))
              RETURNING \(column)
            )
            SELECT * FROM lithepg_updated
            """
        // The preview substitutes literals for reading only; the bound query is what runs.
        var readable = sql
        for index in stride(from: parameter, through: 1, by: -1) {
            readable = readable.replacingOccurrences(of: "$\(index)", with: preview["$\(index)"] ?? "NULL")
        }
        readable = readable.replacingOccurrences(
            of: "WITH lithepg_updated AS (\n  UPDATE", with: "UPDATE"
        )
        if let range = readable.range(of: "\n  RETURNING") {
            readable = String(readable[..<range.lowerBound]) + ";"
        }
        readable = readable
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("  ") ? String($0.dropFirst(2)) : String($0) }
            .joined(separator: "\n")
        return (PostgresQuery(unsafeSQL: sql, binds: bindings), readable)
    }

    static func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    static func literal(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    // MARK: - Catalog

    /// Loads the catalog facts for every table the result columns come from.
    public static func loadTables(
        for sources: [ResultColumnSource],
        using connector: PostgresConnector
    ) async throws -> [UInt32: TableInfo] {
        var tables: [UInt32: TableInfo] = [:]
        for oid in Set(sources.map(\.tableOID)) where oid != 0 {
            var relationBinds = PostgresBindings()
            relationBinds.append(Int64(oid))
            let relation = try await connector.executeBound(
                PostgresQuery(
                    unsafeSQL: """
                        SELECT n.nspname::text, c.relname::text, c.relkind::text
                        FROM pg_catalog.pg_class c
                        JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
                        WHERE c.oid = $1::int8::oid
                        """,
                    binds: relationBinds))
            guard let row = relation.rows.first,
                case .text(let schema) = row.cells[0],
                case .text(let name) = row.cells[1],
                case .text(let kind) = row.cells[2]
            else { continue }

            var columnBinds = PostgresBindings()
            columnBinds.append(Int64(oid))
            let columns = try await connector.executeBound(
                PostgresQuery(
                    unsafeSQL: """
                        SELECT a.attnum::int4,
                               a.attname::text,
                               pg_catalog.format_type(a.atttypid, a.atttypmod),
                               a.atttypid::int8,
                               (a.attgenerated <> '')::bool,
                               (a.attidentity = 'a')::bool,
                               COALESCE(a.attnum = ANY (i.indkey), false)
                        FROM pg_catalog.pg_attribute a
                        LEFT JOIN pg_catalog.pg_index i
                          ON i.indrelid = a.attrelid AND i.indisprimary
                        WHERE a.attrelid = $1::int8::oid AND a.attnum > 0 AND NOT a.attisdropped
                        ORDER BY a.attnum
                        """,
                    binds: columnBinds))
            let info = columns.rows.compactMap { row -> TableColumnInfo? in
                let text = row.cells.map { cell -> String? in
                    if case .text(let value) = cell { return value }
                    return nil
                }
                guard text.count == 7,
                    let attnum = text[0].flatMap(Int.init),
                    let attname = text[1],
                    let typeName = text[2],
                    let typeOID = text[3].flatMap(UInt32.init)
                else { return nil }
                return TableColumnInfo(
                    attributeNumber: attnum,
                    name: attname,
                    typeName: typeName,
                    typeOID: typeOID,
                    isGenerated: text[4] == "true",
                    isIdentityAlways: text[5] == "true",
                    isPrimaryKey: text[6] == "true"
                )
            }
            tables[oid] = TableInfo(oid: oid, schema: schema, name: name, kind: kind, columns: info)
        }
        return tables
    }
}
