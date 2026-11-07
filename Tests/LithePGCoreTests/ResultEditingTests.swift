import Foundation
import PostgresNIO
import Testing

@testable import LithePGCore

@Suite("Result editing")
struct ResultEditingTests {
    private static let customers = TableInfo(
        oid: 100, schema: "public", name: "customers", kind: "r",
        columns: [
            .init(attributeNumber: 1, name: "id", typeName: "integer", typeOID: 23, isPrimaryKey: true),
            .init(attributeNumber: 2, name: "name", typeName: "text", typeOID: 25),
            .init(attributeNumber: 3, name: "created_at", typeName: "timestamp with time zone", typeOID: 1184),
            .init(attributeNumber: 4, name: "slug", typeName: "text", typeOID: 25, isGenerated: true),
        ])

    private func source(_ name: String, table: UInt32 = 100, attnum: Int, type: UInt32 = 25) -> ResultColumnSource {
        ResultColumnSource(name: name, tableOID: table, attributeNumber: attnum, typeOID: type)
    }

    private func target(_ editability: ResultEditability) -> ResultEditTarget? {
        if case .editable(let target) = editability { return target }
        return nil
    }

    private func reason(_ editability: ResultEditability) -> String? {
        if case .readOnly(let reason) = editability { return reason }
        return nil
    }

    @Test("plain table columns with the primary key in the result are editable")
    func editableColumns() {
        let result = ResultEditing.editability(
            sources: [source("id", attnum: 1, type: 23), source("name", attnum: 2), source("created_at", attnum: 3)],
            tables: [100: Self.customers])
        let name = target(result[1])
        #expect(name?.column == "name")
        #expect(name?.key == [.init(name: "id", typeName: "integer", resultColumn: 0)])
        #expect(name?.checksOriginalValue == true)
        // Timestamps are displayed rounded, so they are editable but not compared.
        #expect(target(result[2])?.checksOriginalValue == false)
    }

    @Test("columns that cannot be written explain why")
    func readOnlyReasons() {
        let computed = ResultColumnSource(name: "two", tableOID: 0, attributeNumber: 0, typeOID: 23)
        let result = ResultEditing.editability(
            sources: [source("id", attnum: 1, type: 23), source("slug", attnum: 4), computed],
            tables: [100: Self.customers])
        #expect(reason(result[1])?.contains("generated") == true)
        #expect(reason(result[2])?.contains("computed") == true)

        let withoutKey = ResultEditing.editability(sources: [source("name", attnum: 2)], tables: [100: Self.customers])
        #expect(reason(withoutKey[0]) == "Add the primary key (id) of customers to the query to edit this column.")

        let view = TableInfo(oid: 100, schema: "public", name: "recent", kind: "v", columns: Self.customers.columns)
        let viewResult = ResultEditing.editability(
            sources: [source("id", attnum: 1, type: 23), source("name", attnum: 2)], tables: [100: view])
        #expect(reason(viewResult[1])?.contains("view") == true)

        let noKey = TableInfo(
            oid: 100, schema: "public", name: "logs", kind: "r",
            columns: [.init(attributeNumber: 2, name: "name", typeName: "text", typeOID: 25)])
        #expect(reason(ResultEditing.editability(sources: [source("name", attnum: 2)], tables: [100: noKey])[0])?
            .contains("no primary key") == true)
    }

    @Test("the update binds every value and the preview shows them as literals")
    func updateStatement() throws {
        let result = ResultEditing.editability(
            sources: [source("id", attnum: 1, type: 23), source("name", attnum: 2)],
            tables: [100: Self.customers])
        let name = try #require(target(result[1]))
        let row = QueryResult.Row(id: 0, cells: [.text("7"), .text("O'Brien")])
        let (query, preview) = try ResultEditing.makeUpdate(target: name, row: row, newValue: "José")

        #expect(query.sql.contains(#"UPDATE "public"."customers""#))
        #expect(query.sql.contains(#"SET "name" = $1::text"#))
        #expect(query.sql.contains(#""id" = $2::integer"#))
        #expect(query.sql.contains(#""name" IS NOT DISTINCT FROM $3::text"#))
        #expect(!query.sql.contains("José"))
        #expect(query.binds.count == 3)
        #expect(preview == """
            UPDATE "public"."customers"
            SET "name" = 'José'::text
            WHERE "id" = '7'::integer
              AND "name" IS NOT DISTINCT FROM 'O''Brien'::text;
            """)

        let toNull = try ResultEditing.makeUpdate(target: name, row: row, newValue: nil)
        #expect(toNull.preview.contains(#"SET "name" = NULL::text"#))

        let keyless = QueryResult.Row(id: 1, cells: [.null, .text("x")])
        #expect(throws: ResultEditError.missingKeyValue) {
            _ = try ResultEditing.makeUpdate(target: name, row: keyless, newValue: "y")
        }
    }

    @Test("only queries are traced back to tables")
    func queryStatements() {
        #expect(ResultEditing.isQueryStatement("SELECT 1"))
        #expect(ResultEditing.isQueryStatement("  -- note\n with x as (select 1) select * from x"))
        #expect(!ResultEditing.isQueryStatement("UPDATE t SET a = 1 RETURNING *"))
        #expect(ResultEditing.trimmedStatement(" SELECT 1 ;\n") == "SELECT 1")
    }

    @Test(
        "edits a cell end to end and refuses to overwrite a row changed since loading",
        .enabled(if: ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"] != nil))
    func liveEditRoundTrip() async throws {
        let connector = PostgresConnector()
        try await connector.open(config: try ConnectionConfig(url: ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]!))
        defer { Task { try? await connector.shutdown() } }
        _ = try await connector.execute("""
            CREATE TEMP TABLE lithepg_edit_smoke (
              id int PRIMARY KEY,
              name text,
              shout text GENERATED ALWAYS AS (upper(name)) STORED
            )
            """)
        _ = try await connector.execute("INSERT INTO lithepg_edit_smoke (id, name) VALUES (1, 'Ana'), (2, 'Luis')")

        let sql = "SELECT id, name, shout, id + 1 AS next FROM lithepg_edit_smoke ORDER BY id;"
        let loaded = try await connector.execute(sql)
        let sources = try await connector.describeResultColumns(of: sql)
        #expect(sources.map(\.name) == ["id", "name", "shout", "next"])
        let tables = try await ResultEditing.loadTables(for: sources, using: connector)
        let editability = ResultEditing.editability(sources: sources, tables: tables)
        #expect(reason(editability[2])?.contains("generated") == true)
        #expect(reason(editability[3])?.contains("computed") == true)
        let name = try #require(target(editability[1]))

        let update = try ResultEditing.makeUpdate(target: name, row: loaded.rows[0], newValue: "José Muñoz")
        let written = try await connector.executeBound(update.query)
        #expect(written.rows.count == 1)
        #expect(written.rows.first?.cells.first == .text("José Muñoz"))
        let reread = try await connector.execute("SELECT name FROM lithepg_edit_smoke WHERE id = 1")
        #expect(reread.rows.first?.cells.first == .text("José Muñoz"))

        // Someone else changes row 2 after it was loaded: the stale edit must not land.
        _ = try await connector.execute("UPDATE lithepg_edit_smoke SET name = 'Luisa' WHERE id = 2")
        let stale = try ResultEditing.makeUpdate(target: name, row: loaded.rows[1], newValue: "Lucho")
        let skipped = try await connector.executeBound(stale.query)
        #expect(skipped.rows.isEmpty)
        let kept = try await connector.execute("SELECT name FROM lithepg_edit_smoke WHERE id = 2")
        #expect(kept.rows.first?.cells.first == .text("Luisa"))

        // Statements that are not queries cannot be described.
        await #expect(throws: (any Error).self) {
            _ = try await connector.describeResultColumns(of: "DELETE FROM lithepg_edit_smoke RETURNING *")
        }
        let afterDescribe = try await connector.execute("SELECT count(*) FROM lithepg_edit_smoke")
        #expect(afterDescribe.rows.first?.cells.first == .text("2"))
    }
}
