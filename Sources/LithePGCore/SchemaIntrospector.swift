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
                    columns: relationRows.compactMap { row in
                        guard let column = row.column else { return nil }
                        return DatabaseSchema.Column(
                            name: column.name,
                            typeName: column.typeName,
                            isNullable: column.isNullable,
                            defaultValue: column.defaultValue,
                            ordinalPosition: column.ordinalPosition
                        )
                    }
                )
            }
            return DatabaseSchema.Schema(name: schemaName, relations: relations)
        }

        return DatabaseSchema(schemas: schemas)
    }

    private static let introspectionSQL = """
        SELECT
            table_schema,
            table_name,
            table_type,
            column_name,
            data_type,
            is_nullable,
            column_default,
            ordinal_position
        FROM information_schema.tables
        LEFT JOIN information_schema.columns
          USING (table_catalog, table_schema, table_name)
        WHERE table_schema NOT IN ('information_schema', 'pg_catalog', 'pg_toast')
          AND table_schema NOT LIKE 'pg_toast_temp_%'
          AND table_schema NOT LIKE 'pg_temp_%'
        ORDER BY table_schema, table_type, table_name, ordinal_position, column_name
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
                ordinalPosition: ordinal
            )
        }
        return IntrospectionRow(
            schema: try text(row.cells[0]),
            relation: try text(row.cells[1]),
            kind: kind,
            column: column
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

    private static func optionalText(_ cell: QueryResult.Cell) -> String? {
        guard case .text(let value) = cell else { return nil }
        return value
    }

    private struct IntrospectionRow {
        let schema: String
        let relation: String
        let kind: DatabaseSchema.Relation.Kind
        let column: IntrospectionColumn?
    }

    private struct IntrospectionColumn {
        let name: String
        let typeName: String
        let isNullable: Bool
        let defaultValue: String?
        let ordinalPosition: Int
    }

    private struct RelationKey: Hashable {
        let schema: String
        let name: String
        let kind: DatabaseSchema.Relation.Kind
    }
}

public enum SchemaIntrospectionError: Error, Equatable {
    case malformedRow
}
