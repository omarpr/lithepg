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
                Self.row(schema: "public", relation: "orders", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", defaultValue: "nextval('orders_id_seq'::regclass)", ordinal: 1, primaryKey: true),
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
        #expect(publicRelations.first?.columns.first?.isPrimaryKey == true)
        #expect(publicRelations.first?.columns.first?.defaultValue == "nextval('orders_id_seq'::regclass)")
    }

    @Test("maps foreign keys from extended introspection rows")
    func mapsForeignKeys() throws {
        let result = QueryResult(
            columns: [],
            rows: [
                Self.row(schema: "public", relation: "customers", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", ordinal: 1, primaryKey: true),
                Self.row(schema: "public", relation: "orders", type: "BASE TABLE", column: "id", dataType: "integer", nullable: "NO", ordinal: 1, primaryKey: true),
                Self.row(
                    schema: "public",
                    relation: "orders",
                    type: "BASE TABLE",
                    column: "customer_id",
                    dataType: "integer",
                    nullable: "NO",
                    ordinal: 2,
                    foreignKey: .init(
                        name: "orders_customer_id_fkey",
                        position: 1,
                        parentSchema: "public",
                        parentRelation: "customers",
                        parentColumn: "id"
                    )
                ),
            ],
            rowCount: 3,
            elapsed: .zero,
            status: .rows,
            truncated: false
        )

        let metadata = try SchemaIntrospector.map(result: result)

        let orders = try #require(metadata.schemas.first?.relations.first { $0.name == "orders" })
        #expect(orders.columns.first { $0.name == "id" }?.isPrimaryKey == true)
        #expect(metadata.foreignKeys.count == 1)
        #expect(metadata.foreignKeys.first?.name == "orders_customer_id_fkey")
        #expect(metadata.foreignKeys.first?.childColumns == ["customer_id"])
        #expect(metadata.foreignKeys.first?.parentRelation == "customers")
        #expect(metadata.foreignKeys.first?.parentColumns == ["id"])
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

        _ = try await connector.execute("DROP TABLE IF EXISTS lithepg_schema_fk_child")
        _ = try await connector.execute("DROP TABLE IF EXISTS lithepg_schema_fk_parent")
        _ = try await connector.execute("DROP TABLE IF EXISTS lithepg_schema_smoke")
        _ = try await connector.execute("""
            CREATE TABLE lithepg_schema_smoke (
                id serial PRIMARY KEY,
                note text,
                created_at timestamptz DEFAULT now()
            )
            """)
        _ = try await connector.execute("""
            CREATE TABLE lithepg_schema_fk_parent (
                id serial PRIMARY KEY,
                label text NOT NULL
            )
            """)
        _ = try await connector.execute("""
            CREATE TABLE lithepg_schema_fk_child (
                id serial PRIMARY KEY,
                parent_id integer NOT NULL REFERENCES lithepg_schema_fk_parent(id)
            )
            """)
        defer {
            Task {
                _ = try? await connector.execute("DROP TABLE IF EXISTS lithepg_schema_fk_child")
                _ = try? await connector.execute("DROP TABLE IF EXISTS lithepg_schema_fk_parent")
                _ = try? await connector.execute("DROP TABLE IF EXISTS lithepg_schema_smoke")
            }
        }

        let metadata = try await SchemaIntrospector.loadSchema(using: connector)
        let publicSchema = try #require(metadata.schemas.first { $0.name == "public" })
        let smoke = try #require(publicSchema.relations.first { $0.name == "lithepg_schema_smoke" })
        let fkChild = try #require(publicSchema.relations.first { $0.name == "lithepg_schema_fk_child" })
        let fk = try #require(metadata.foreignKeys.first { $0.childRelation == "lithepg_schema_fk_child" })

        #expect(metadata.schemas.contains { $0.name == "pg_catalog" } == false)
        #expect(smoke.kind == .table)
        #expect(smoke.columns.map { $0.name } == ["id", "note", "created_at"])
        #expect(smoke.columns.first?.isNullable == false)
        #expect(smoke.columns.first?.isPrimaryKey == true)
        #expect(fkChild.columns.first { $0.name == "id" }?.isPrimaryKey == true)
        #expect(fk.childColumns == ["parent_id"])
        #expect(fk.parentRelation == "lithepg_schema_fk_parent")
        #expect(fk.parentColumns == ["id"])
    }

    private struct ForeignKeyFixture {
        let name: String
        let position: Int
        let parentSchema: String
        let parentRelation: String
        let parentColumn: String
    }

    private static func row(
        schema: String,
        relation: String,
        type: String,
        column: String,
        dataType: String,
        nullable: String,
        defaultValue: String? = nil,
        ordinal: Int,
        primaryKey: Bool = false,
        foreignKey: ForeignKeyFixture? = nil
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
            .text(primaryKey ? "YES" : "NO"),
            foreignKey.map { .text($0.name) } ?? .null,
            foreignKey.map { .text(String($0.position)) } ?? .null,
            foreignKey.map { .text($0.parentSchema) } ?? .null,
            foreignKey.map { .text($0.parentRelation) } ?? .null,
            foreignKey.map { .text($0.parentColumn) } ?? .null,
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
