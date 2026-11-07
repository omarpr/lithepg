import Foundation
import Testing

@testable import LithePGCore

@Suite("SQL completion")
struct SQLCompletionTests {
    private let index = SQLCompletionIndex(schema: DatabaseSchema(schemas: [
        .init(name: "public", relations: [
            .init(schema: "public", name: "clientes", kind: .table, columns: [
                .init(name: "id", typeName: "integer", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                .init(name: "nombre", typeName: "text", isNullable: true, ordinalPosition: 2),
                .init(name: "ciudad", typeName: "varchar", isNullable: true, ordinalPosition: 3),
            ]),
            .init(schema: "public", name: "pedidos", kind: .table, columns: [
                .init(name: "id", typeName: "integer", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                .init(name: "cliente_id", typeName: "integer", isNullable: true, ordinalPosition: 2),
                .init(name: "descripción", typeName: "text", isNullable: true, ordinalPosition: 3),
                .init(name: "Total", typeName: "numeric", isNullable: true, ordinalPosition: 4),
                .init(name: "order", typeName: "integer", isNullable: true, ordinalPosition: 5),
            ]),
        ]),
        .init(name: "ventas", relations: [
            .init(schema: "ventas", name: "facturas", kind: .view, columns: [
                .init(name: "numero", typeName: "text", isNullable: false, ordinalPosition: 1),
            ]),
        ]),
    ]))

    /// Completes at the `|` marker.
    private func complete(_ marked: String) -> SQLCompletionResult? {
        let caret = (marked as NSString).range(of: "|").location
        return index.complete(in: marked.replacingOccurrences(of: "|", with: ""), at: caret)
    }

    private func texts(_ marked: String) -> [String] {
        complete(marked)?.completions.map(\.insertText) ?? []
    }

    @Test("completes keywords in the case being typed")
    func keywordsFollowTypedCase() {
        #expect(texts("SELE|").first == "SELECT")
        #expect(texts("sele|").first == "select")
        #expect(complete("SELE|")?.replacementRange == NSRange(location: 0, length: 4))
        #expect(texts("SELECT * FROM clientes WH|").contains("WHERE"))
    }

    @Test("after FROM and JOIN, tables come first and other schemas are qualified")
    func tablesAfterFrom() {
        #expect(texts("SELECT * FROM cl|") == ["clientes"])
        #expect(texts("SELECT * FROM clientes c JOIN pe|").first == "pedidos")
        #expect(texts("SELECT * FROM fa|").first == "ventas.facturas")
        #expect(texts("SELECT * FROM ve|").first == "ventas.facturas")
        #expect(texts("SELECT * FROM ventas.|") == ["facturas"])
    }

    @Test("columns come from the tables the statement references")
    func columnsFromReferencedTables() {
        let names = texts("SELECT nom| FROM clientes")
        #expect(names == ["nombre"])
        #expect(texts("SELECT * FROM clientes WHERE ci|") == ["ciudad"])
        // pedidos is not referenced, so its columns are not offered here.
        #expect(!texts("SELECT * FROM clientes WHERE cl|").contains("cliente_id"))
        #expect(texts("SELECT * FROM pedidos WHERE cl|").contains("cliente_id"))
    }

    @Test("alias and table qualifiers narrow to that table's columns")
    func qualifiedColumns() {
        let sql = "SELECT p.| FROM clientes c JOIN pedidos AS p ON p.cliente_id = c.id"
        #expect(texts(sql) == ["id", "cliente_id", "descripción", "\"Total\"", "\"order\""])
        #expect(texts("SELECT c.ci| FROM clientes c") == ["ciudad"])
        #expect(texts("SELECT clientes.no| FROM clientes") == ["nombre"])
        // A table qualifier works even before the FROM clause names it.
        #expect(texts("SELECT pedidos.cl|") == ["cliente_id"])
    }

    @Test("identifiers are quoted when PostgreSQL needs it")
    func quotesIdentifiers() {
        #expect(texts("SELECT * FROM pedidos WHERE To|").first == "\"Total\"")
        #expect(texts("SELECT * FROM pedidos ORDER BY or|").contains("\"order\""))
        #expect(texts("SELECT * FROM pedidos WHERE desc|").contains("descripción"))
    }

    @Test("columns carry their type and primary key as detail")
    func columnDetail() {
        let id = complete("SELECT i| FROM clientes")?.completions.first { $0.insertText == "id" }
        #expect(id?.kind == .column)
        #expect(id?.detail == "integer · primary key")
    }

    @Test("stays quiet inside strings, quoted identifiers, comments and numbers")
    func quietOutsideCode() {
        #expect(complete("SELECT 'SELE|'") == nil)
        #expect(complete("SELECT \"cli|\"") == nil)
        #expect(complete("-- SELE|") == nil)
        #expect(complete("/* SELE| */") == nil)
        #expect(complete("SELECT 1.5|") == nil)
        #expect(complete("SELECT 'done' AS x, nom| FROM clientes") != nil)
    }

    @Test("a finished word with nothing longer to offer closes the list")
    func finishedWord() {
        #expect(complete("SELECT * FROM clientes|") == nil)
    }

    @Test("only the statement under the caret supplies tables")
    func scopedToStatement() {
        let sql = "SELECT * FROM pedidos;\nSELECT cl| FROM clientes;"
        #expect(!texts(sql).contains("cliente_id"))
    }

    @Test("table references parse schemas, aliases and FROM lists")
    func parsesTableReferences() {
        let tokens = SQLLexer.tokens(Array("FROM public.clientes AS c, pedidos p JOIN ventas.facturas WHERE x".utf16))
        let references = SQLCompletionIndex.tableReferences(in: tokens)
        #expect(references == [
            .init(schema: "public", name: "clientes", alias: "c"),
            .init(schema: nil, name: "pedidos", alias: "p"),
            .init(schema: "ventas", name: "facturas", alias: nil),
        ])
    }
}
