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
        #expect(ResultsTablePresentation.secondaryStatus(for: result) == "2 rows · 84 ms")
        #expect(ResultsTablePresentation.commandStatus(for: result) == "Truncated")
        #expect(ResultsTablePresentation.truncationStatus(for: result) == "Result capped at 10,000 rows. Refine the query or add SQL LIMIT/OFFSET for server-side paging.")
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

    @Test("pagination slices rows and reports visible ranges")
    func paginationPresentation() {
        let result = QueryResult(
            columns: [.init(name: "n", typeName: "int4")],
            rows: (0..<205).map { .init(id: $0, cells: [.text("\($0)")]) },
            rowCount: 205,
            elapsed: .milliseconds(10),
            status: .rows,
            truncated: false
        )

        #expect(ResultsTablePresentation.pageCount(for: result) == 3)
        #expect(ResultsTablePresentation.rows(for: result, page: 1).count == 100)
        #expect(ResultsTablePresentation.rows(for: result, page: 3).count == 5)
        #expect(ResultsTablePresentation.absoluteRowNumber(pageRowIndex: 0, page: 3) == 201)
        #expect(ResultsTablePresentation.canGoPrevious(page: 1) == false)
        #expect(ResultsTablePresentation.canGoNext(result, page: 1) == true)
        #expect(ResultsTablePresentation.canGoNext(result, page: 3) == false)
        #expect(ResultsTablePresentation.pageStatus(for: result, page: 2) == "Rows 101–200 of 205 · Page 2 of 3")
        #expect(ResultsTablePresentation.secondaryStatus(for: result, page: 2) == "rows 101–200 of 205 · 10 ms")
    }

    @Test("column widths fill available result space until they reach the minimum")
    func columnWidthsFillAvailableSpace() {
        #expect(ResultsTablePresentation.columnWidths(availableWidth: 900, columnCount: 2) == [418, 418])
        #expect(ResultsTablePresentation.tableTotalWidth(availableWidth: 901, columnCount: 3) == 901)
        #expect(ResultsTablePresentation.columnWidths(availableWidth: 260, columnCount: 4) == Array(repeating: ResultsTablePresentation.minimumColumnWidth, count: 4))
        #expect(ResultsTablePresentation.columnWidths(availableWidth: 900, columnCount: 0) == [])
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
