import Foundation
import Testing
@testable import LithePGCore

@Suite("SchemaIntrospector")
struct SchemaIntrospectorTests {
    static var plainURL: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]
    }

    @Test("maps introspection rows into schema metadata")
    func mapsRowsIntoMetadata() throws {
        let result = QueryResult(
            columns: [],
            rows: [
                Self.row(schema: "public", relation: "orders", type: "BASE TABLE", column: "customer_id", dataType: "integer", nullable: "YES", ordinal: 2),
                Self.row(schema: "public", relation: "orders", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", defaultValue: "nextval('orders_id_seq'::regclass)", ordinal: 1),
                Self.row(schema: "public", relation: "active_orders", type: "VIEW", column: "id", dataType: "integer", nullable: "YES", ordinal: 1),
                Self.row(schema: "analytics", relation: "rollups", type: "BASE TABLE", column: "bucket", dataType: "text", nullable: "NO", ordinal: 1),
            ],
            rowCount: 4,
            elapsed: .zero,
            status: .rows,
            truncated: false
        )

        let metadata = try SchemaIntrospector.map(result: result)

        #expect(metadata.schemas.map { $0.name } == ["analytics", "public"])
        let publicRelations = metadata.schemas.first { $0.name == "public" }?.relations ?? []
        #expect(publicRelations.map { $0.name } == ["orders", "active_orders"])
        #expect(publicRelations.map { $0.kind } == [.table, .view])
        #expect(publicRelations.first?.columns.map { $0.name } == ["id", "customer_id"])
        #expect(publicRelations.first?.columns.first?.isNullable == false)
        #expect(publicRelations.first?.columns.first?.defaultValue == "nextval('orders_id_seq'::regclass)")
    }

    @Test("filters system schemas")
    func filtersSystemSchemas() throws {
        let result = QueryResult(
            columns: [],
            rows: [
                Self.row(schema: "pg_catalog", relation: "pg_class", type: "BASE TABLE", column: "oid", dataType: "oid", nullable: "NO", ordinal: 1),
                Self.row(schema: "information_schema", relation: "tables", type: "VIEW", column: "table_name", dataType: "name", nullable: "YES", ordinal: 1),
                Self.row(schema: "pg_temp_5", relation: "temp_table", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", ordinal: 1),
                Self.row(schema: "pg_toast_temp_5", relation: "toast_table", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", ordinal: 1),
                Self.row(schema: "public", relation: "visible", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", ordinal: 1),
            ],
            rowCount: 5,
            elapsed: .zero,
            status: .rows,
            truncated: false
        )

        let metadata = try SchemaIntrospector.map(result: result)

        #expect(metadata.schemas.map { $0.name } == ["public"])
        #expect(metadata.schemas.first?.relations.map { $0.name } == ["visible"])
    }

    @Test("maps zero-column relations")
    func mapsZeroColumnRelations() throws {
        let result = QueryResult(
            columns: [],
            rows: [
                Self.zeroColumnRow(schema: "public", relation: "empty_table", type: "BASE TABLE")
            ],
            rowCount: 1,
            elapsed: .zero,
            status: .rows,
            truncated: false
        )

        let metadata = try SchemaIntrospector.map(result: result)

        let relation = try #require(metadata.schemas.first?.relations.first)
        #expect(relation.name == "empty_table")
        #expect(relation.columns.isEmpty)
    }

    @Test("throws on malformed rows")
    func malformedRowsThrow() {
        let result = QueryResult(
            columns: [],
            rows: [.init(id: 0, cells: [.text("public")])],
            rowCount: 1,
            elapsed: .zero,
            status: .rows,
            truncated: false
        )

        #expect(throws: SchemaIntrospectionError.malformedRow) {
            _ = try SchemaIntrospector.map(result: result)
        }
    }

    @Test("live introspection sees user tables and hides system schemas", .enabled(if: plainURL != nil))
    func liveIntrospection() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        try await connector.open(config: config)
        defer { Task { try? await connector.shutdown() } }

        _ = try await connector.execute("DROP TABLE IF EXISTS lithepg_schema_smoke")
        _ = try await connector.execute("""
            CREATE TABLE lithepg_schema_smoke (
                id serial PRIMARY KEY,
                note text,
                created_at timestamptz DEFAULT now()
            )
            """)
        defer { Task { _ = try? await connector.execute("DROP TABLE IF EXISTS lithepg_schema_smoke") } }

        let metadata = try await SchemaIntrospector.loadSchema(using: connector)
        let publicSchema = try #require(metadata.schemas.first { $0.name == "public" })
        let smoke = try #require(publicSchema.relations.first { $0.name == "lithepg_schema_smoke" })

        #expect(metadata.schemas.contains { $0.name == "pg_catalog" } == false)
        #expect(smoke.kind == .table)
        #expect(smoke.columns.map { $0.name } == ["id", "note", "created_at"])
        #expect(smoke.columns.first?.isNullable == false)
    }

    private static func row(
        schema: String,
        relation: String,
        type: String,
        column: String,
        dataType: String,
        nullable: String,
        defaultValue: String? = nil,
        ordinal: Int
    ) -> QueryResult.Row {
        .init(id: ordinal, cells: [
            .text(schema),
            .text(relation),
            .text(type),
            .text(column),
            .text(dataType),
            .text(nullable),
            defaultValue.map(QueryResult.Cell.text) ?? .null,
            .text(String(ordinal)),
        ])
    }

    private static func zeroColumnRow(
        schema: String,
        relation: String,
        type: String
    ) -> QueryResult.Row {
        .init(id: 0, cells: [
            .text(schema),
            .text(relation),
            .text(type),
            .null,
            .null,
            .null,
            .null,
            .null,
        ])
    }
}
