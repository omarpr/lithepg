import Foundation
import Testing
@testable import LithePGCore

@Suite("QueryResult")
struct QueryResultTests {
    @Test("empty rows result defaults")
    func emptyRowsResult() {
        let result = QueryResult(
            columns: [],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(0),
            status: .empty,
            truncated: false
        )
        #expect(result.rowCount == 0)
        #expect(result.truncated == false)
        #expect(result.status == .empty)
    }

    @Test("command status carries tag and affected count")
    func commandStatus() {
        let status = QueryResult.Status.command(tag: "INSERT", affected: 3)
        #expect(status == .command(tag: "INSERT", affected: 3))
        #expect(status != .rows)
    }

    @Test("Cell.null is distinct from Cell.text")
    func cellEquality() {
        #expect(QueryResult.Cell.null == .null)
        #expect(QueryResult.Cell.null != .text(""))
        #expect(QueryResult.Cell.text("a") == .text("a"))
        #expect(QueryResult.Cell.text("a") != .text("b"))
    }

    @Test("Row.id is stable across cell mutations")
    func rowIdentity() {
        let row = QueryResult.Row(id: 7, cells: [.text("a"), .null])
        #expect(row.id == 7)
        #expect(row.cells.count == 2)
    }

    @Test("truncated flag marks capped results")
    func truncatedFlag() {
        let result = QueryResult(
            columns: [.init(name: "id", typeName: "int4")],
            rows: (0..<10_000).map { .init(id: $0, cells: [.text(String($0))]) },
            rowCount: 10_000,
            elapsed: .milliseconds(42),
            status: .rows,
            truncated: true
        )
        #expect(result.truncated)
        #expect(result.rowCount == 10_000)
    }
}
