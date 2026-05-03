import Foundation
import Testing
@testable import LithePGApp
import LithePGCore

@Suite("ResultsTable presentation")
struct ResultsTablePresentationTests {
    @Test("row results expose summary, command label, column labels, and truncation status")
    func rowResultPresentation() {
        let result = QueryResult(
            columns: [
                .init(name: "day", typeName: "date"),
                .init(name: "therapist_id", typeName: "uuid"),
            ],
            rows: [
                .init(id: 0, cells: [.text("2026-04-30"), .text("8c4f...a21")]),
                .init(id: 1, cells: [.text("2026-05-01"), .null]),
            ],
            rowCount: 2,
            elapsed: .milliseconds(84),
            status: .rows,
            truncated: true
        )

        #expect(ResultsTablePresentation.primaryCount(for: result) == "2")
        #expect(ResultsTablePresentation.secondaryStatus(for: result) == "rows · 84 ms")
        #expect(ResultsTablePresentation.commandStatus(for: result) == "Truncated")
        #expect(ResultsTablePresentation.truncationStatus(for: result) == "Result capped at 10,000 rows. Refine the query or add LIMIT/OFFSET paging.")
        #expect(ResultsTablePresentation.headerName(for: result.columns[0]) == "day")
        #expect(ResultsTablePresentation.headerType(for: result.columns[0]) == "DATE")
        #expect(ResultsTablePresentation.headerAccessibilityLabel(for: result.columns[0]) == "day")
    }

    @Test("empty and command results have clear status copy")
    func emptyAndCommandPresentation() {
        let empty = QueryResult(
            columns: [],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(7),
            status: .empty,
            truncated: false
        )
        let command = QueryResult(
            columns: [],
            rows: [],
            rowCount: 12,
            elapsed: .milliseconds(16),
            status: .command(tag: "UPDATE", affected: 12),
            truncated: false
        )

        #expect(ResultsTablePresentation.emptyTitle(for: empty) == "Query completed")
        #expect(ResultsTablePresentation.emptyDetail(for: empty) == "No rows were returned · 7 ms")
        #expect(ResultsTablePresentation.commandTitle(for: command) == "UPDATE completed")
        #expect(ResultsTablePresentation.commandDetail(for: command) == "12 rows affected · 16 ms")
        #expect(ResultsTablePresentation.commandStatus(for: command) == "Complete")
    }

    @Test("cell rendering keeps null and empty text distinct")
    func cellRendering() {
        #expect(ResultsTablePresentation.render(.null) == "NULL")
        #expect(ResultsTablePresentation.render(.text("")) == "")
        #expect(ResultsTablePresentation.render(.text("a long value")) == "a long value")
    }

    @Test("copy text exports tab-separated rows and status details")
    func copyText() {
        let rows = QueryResult(
            columns: [
                .init(name: "id", typeName: "integer"),
                .init(name: "note", typeName: "text"),
            ],
            rows: [
                .init(id: 0, cells: [.text("1"), .text("hello\nworld")]),
                .init(id: 1, cells: [.text("2"), .null]),
            ],
            rowCount: 2,
            elapsed: .milliseconds(3),
            status: .rows,
            truncated: false
        )
        let command = QueryResult(
            columns: [],
            rows: [],
            rowCount: 1,
            elapsed: .milliseconds(4),
            status: .command(tag: "DELETE", affected: 1),
            truncated: false
        )

        #expect(ResultsTablePresentation.copyText(for: rows) == "id\tnote\n1\thello world\n2\tNULL")
        #expect(ResultsTablePresentation.copyText(for: command) == "1 row affected · 4 ms")
    }
}
