import Foundation

public enum SchemaIntrospector {
    public static let excludedSystemSchemas: Set<String> = [
        "information_schema",
        "pg_catalog",
        "pg_toast",
    ]

    public static let excludedSystemSchemaPrefixes: [String] = [
        "pg_temp_",
        "pg_toast_temp_",
    ]

    public static func loadSchema(using connector: PostgresConnector) async throws -> DatabaseSchema {
        let result = try await connector.execute(introspectionSQL)
        return try map(result: result)
    }

    static func map(result: QueryResult) throws -> DatabaseSchema {
        let rows = try result.rows.map(Self.row(from:))
        let filteredRows = rows.filter { !isSystemSchema($0.schema) }
        let groupedBySchema = Dictionary(grouping: filteredRows, by: \.schema)

        let schemas = groupedBySchema.map { schemaName, schemaRows in
            let groupedByRelation = Dictionary(grouping: schemaRows) { row in
                RelationKey(schema: row.schema, name: row.relation, kind: row.kind)
            }
            let relations = groupedByRelation.map { key, relationRows in
                DatabaseSchema.Relation(
                    schema: key.schema,
                    name: key.name,
                    kind: key.kind,
                    columns: columns(from: relationRows)
                )
            }
            return DatabaseSchema.Schema(name: schemaName, relations: relations)
        }

        return DatabaseSchema(schemas: schemas, foreignKeys: foreignKeys(from: filteredRows))
    }

    private static func columns(from rows: [IntrospectionRow]) -> [DatabaseSchema.Column] {
        let groupedByColumn = Dictionary(grouping: rows.compactMap(\.column)) { column in
            ColumnKey(name: column.name, ordinalPosition: column.ordinalPosition)
        }

        return groupedByColumn.values.compactMap { columns in
            guard let first = columns.first else { return nil }
            return DatabaseSchema.Column(
                name: first.name,
                typeName: first.typeName,
                isNullable: first.isNullable,
                defaultValue: first.defaultValue,
                ordinalPosition: first.ordinalPosition,
                isPrimaryKey: columns.contains { $0.isPrimaryKey }
            )
        }
    }

    private static func foreignKeys(from rows: [IntrospectionRow]) -> [DatabaseSchema.ForeignKey] {
        let parts = rows.compactMap(\.foreignKeyPart)
        let grouped = Dictionary(grouping: parts) { part in
            ForeignKeyKey(
                name: part.name,
                childSchema: part.childSchema,
                childRelation: part.childRelation,
                parentSchema: part.parentSchema,
                parentRelation: part.parentRelation
            )
        }

        return grouped.map { key, parts in
            let sortedParts = parts.sorted { lhs, rhs in
                if lhs.position != rhs.position { return lhs.position < rhs.position }
                return lhs.childColumn.localizedStandardCompare(rhs.childColumn) == .orderedAscending
            }
            return DatabaseSchema.ForeignKey(
                name: key.name,
                childSchema: key.childSchema,
                childRelation: key.childRelation,
                childColumns: sortedParts.map(\.childColumn),
                parentSchema: key.parentSchema,
                parentRelation: key.parentRelation,
                parentColumns: sortedParts.map(\.parentColumn)
            )
        }
    }

    private static let introspectionSQL = """
        WITH primary_keys AS (
            SELECT
                ns.nspname AS table_schema,
                cls.relname AS table_name,
                att.attname AS column_name
            FROM pg_constraint con
            JOIN pg_class cls ON cls.oid = con.conrelid
            JOIN pg_namespace ns ON ns.oid = cls.relnamespace
            JOIN unnest(con.conkey) AS key_attnum(attnum) ON true
            JOIN pg_attribute att ON att.attrelid = cls.oid AND att.attnum = key_attnum.attnum
            WHERE con.contype = 'p'
        ),
        foreign_keys AS (
            SELECT
                child_ns.nspname AS child_schema,
                child_cls.relname AS child_table,
                con.conname AS constraint_name,
                child_att.attname AS child_column,
                key_pair.position AS key_position,
                parent_ns.nspname AS parent_schema,
                parent_cls.relname AS parent_table,
                parent_att.attname AS parent_column
            FROM pg_constraint con
            JOIN pg_class child_cls ON child_cls.oid = con.conrelid
            JOIN pg_namespace child_ns ON child_ns.oid = child_cls.relnamespace
            JOIN pg_class parent_cls ON parent_cls.oid = con.confrelid
            JOIN pg_namespace parent_ns ON parent_ns.oid = parent_cls.relnamespace
            JOIN unnest(con.conkey, con.confkey) WITH ORDINALITY AS key_pair(child_attnum, parent_attnum, position) ON true
            JOIN pg_attribute child_att ON child_att.attrelid = child_cls.oid AND child_att.attnum = key_pair.child_attnum
            JOIN pg_attribute parent_att ON parent_att.attrelid = parent_cls.oid AND parent_att.attnum = key_pair.parent_attnum
            WHERE con.contype = 'f'
        )
        SELECT
            t.table_schema,
            t.table_name,
            t.table_type,
            c.column_name,
            c.data_type,
            c.is_nullable,
            c.column_default,
            c.ordinal_position,
            CASE WHEN pk.column_name IS NULL THEN 'NO' ELSE 'YES' END AS is_primary_key,
            fk.constraint_name AS foreign_key_name,
            fk.key_position AS foreign_key_position,
            fk.parent_schema AS foreign_table_schema,
            fk.parent_table AS foreign_table_name,
            fk.parent_column AS foreign_column_name
        FROM information_schema.tables t
        LEFT JOIN information_schema.columns c
          USING (table_catalog, table_schema, table_name)
        LEFT JOIN primary_keys pk
          ON pk.table_schema = t.table_schema
         AND pk.table_name = t.table_name
         AND pk.column_name = c.column_name
        LEFT JOIN foreign_keys fk
          ON fk.child_schema = t.table_schema
         AND fk.child_table = t.table_name
         AND fk.child_column = c.column_name
        WHERE t.table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
          AND t.table_schema NOT LIKE 'pg_toast_temp_%'
          AND t.table_schema NOT LIKE 'pg_temp_%'
        ORDER BY t.table_schema, t.table_type, t.table_name, c.ordinal_position, c.column_name, fk.constraint_name, fk.key_position
        """

    private static func row(from row: QueryResult.Row) throws -> IntrospectionRow {
        guard row.cells.count >= 8 else { throw SchemaIntrospectionError.malformedRow }
        let kind: DatabaseSchema.Relation.Kind = switch try text(row.cells[2]) {
        case "VIEW": .view
        default: .table
        }
        let column: IntrospectionColumn?
        if case .null = row.cells[3] {
            column = nil
        } else {
            guard let ordinal = Int(try text(row.cells[7])) else {
                throw SchemaIntrospectionError.malformedRow
            }
            column = IntrospectionColumn(
                name: try text(row.cells[3]),
                typeName: try text(row.cells[4]),
                isNullable: try text(row.cells[5]) == "YES",
                defaultValue: optionalText(row.cells[6]),
                ordinalPosition: ordinal,
                isPrimaryKey: boolText(row.cells[safe: 8])
            )
        }

        let foreignKeyPart: ForeignKeyPart?
        if let fkName = optionalText(row.cells[safe: 9]),
           let fkPosition = optionalInt(row.cells[safe: 10]),
           let parentSchema = optionalText(row.cells[safe: 11]),
           let parentRelation = optionalText(row.cells[safe: 12]),
           let parentColumn = optionalText(row.cells[safe: 13]),
           let childColumn = column?.name
        {
            foreignKeyPart = ForeignKeyPart(
                name: fkName,
                position: fkPosition,
                childSchema: try text(row.cells[0]),
                childRelation: try text(row.cells[1]),
                childColumn: childColumn,
                parentSchema: parentSchema,
                parentRelation: parentRelation,
                parentColumn: parentColumn
            )
        } else {
            foreignKeyPart = nil
        }

        return IntrospectionRow(
            schema: try text(row.cells[0]),
            relation: try text(row.cells[1]),
            kind: kind,
            column: column,
            foreignKeyPart: foreignKeyPart
        )
    }

    private static func isSystemSchema(_ schema: String) -> Bool {
        excludedSystemSchemas.contains(schema)
            || excludedSystemSchemaPrefixes.contains { schema.hasPrefix($0) }
    }

    private static func text(_ cell: QueryResult.Cell) throws -> String {
        guard case .text(let value) = cell else { throw SchemaIntrospectionError.malformedRow }
        return value
    }

    private static func optionalText(_ cell: QueryResult.Cell?) -> String? {
        guard let cell, case .text(let value) = cell else { return nil }
        return value
    }

    private static func optionalInt(_ cell: QueryResult.Cell?) -> Int? {
        guard let value = optionalText(cell) else { return nil }
        return Int(value)
    }

    private static func boolText(_ cell: QueryResult.Cell?) -> Bool {
        guard let value = optionalText(cell)?.lowercased() else { return false }
        return value == "yes" || value == "true" || value == "t" || value == "1"
    }

    private struct IntrospectionRow {
        let schema: String
        let relation: String
        let kind: DatabaseSchema.Relation.Kind
        let column: IntrospectionColumn?
        let foreignKeyPart: ForeignKeyPart?
    }

    private struct IntrospectionColumn {
        let name: String
        let typeName: String
        let isNullable: Bool
        let defaultValue: String?
        let ordinalPosition: Int
        let isPrimaryKey: Bool
    }

    private struct ForeignKeyPart {
        let name: String
        let position: Int
        let childSchema: String
        let childRelation: String
        let childColumn: String
        let parentSchema: String
        let parentRelation: String
        let parentColumn: String
    }

    private struct RelationKey: Hashable {
        let schema: String
        let name: String
        let kind: DatabaseSchema.Relation.Kind
    }

    private struct ColumnKey: Hashable {
        let name: String
        let ordinalPosition: Int
    }

    private struct ForeignKeyKey: Hashable {
        let name: String
        let childSchema: String
        let childRelation: String
        let parentSchema: String
        let parentRelation: String
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

public enum SchemaIntrospectionError: Error, Equatable {
    case malformedRow
}
