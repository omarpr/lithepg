import Foundation
import Testing
@testable import LithePGAppUI
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

    @Test("filler rows keep sparse result sets visually full height")
    func fillerRowsFillSparseViewport() {
        let viewport: CGFloat = 320
        // Derive from the layout constants so size polish does not break the test.
        func expected(_ visible: Int) -> Int {
            let occupied = (ResultsTablePresentation.tablePadding * 2)
                + ResultsTablePresentation.headerRowHeight
                + (CGFloat(visible) * ResultsTablePresentation.bodyRowHeight)
            return max(0, Int(ceil((viewport - occupied) / ResultsTablePresentation.bodyRowHeight)))
        }
        #expect(ResultsTablePresentation.fillerRowCount(viewportHeight: viewport, visibleRowCount: 0) == expected(0))
        #expect(ResultsTablePresentation.fillerRowCount(viewportHeight: viewport, visibleRowCount: 2) == expected(2))
        #expect(ResultsTablePresentation.fillerRowCount(viewportHeight: viewport, visibleRowCount: 100) == 0)
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

    @Test("export is only enabled for row results that have columns")
    func canExport() {
        let rows = QueryResult(
            columns: [.init(name: "id", typeName: "integer")],
            rows: [.init(id: 0, cells: [.text("1")])],
            rowCount: 1,
            elapsed: .milliseconds(3),
            status: .rows,
            truncated: false
        )
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
            rowCount: 1,
            elapsed: .milliseconds(4),
            status: .command(tag: "DELETE", affected: 1),
            truncated: false
        )
        let columnlessRows = QueryResult(
            columns: [],
            rows: [],
            rowCount: 0,
            elapsed: .milliseconds(1),
            status: .rows,
            truncated: false
        )

        #expect(ResultsTablePresentation.canExport(rows) == true)
        #expect(ResultsTablePresentation.canExport(empty) == false)
        #expect(ResultsTablePresentation.canExport(command) == false)
        #expect(ResultsTablePresentation.canExport(columnlessRows) == false)
        #expect(ResultsTablePresentation.canExport(nil) == false)
    }

    @Test("export default file names carry the format extension")
    func exportFileNames() {
        #expect(ResultsTablePresentation.defaultExportFileName(for: .csv) == "lithepg-results.csv")
        #expect(ResultsTablePresentation.defaultExportFileName(for: .json) == "lithepg-results.json")
        #expect(ResultsTablePresentation.defaultExportFileName(for: .markdown) == "lithepg-results.md")
    }

    @Test("export content reuses the on-device ResultExporter serializers")
    func exportContent() {
        let rows = QueryResult(
            columns: [
                .init(name: "id", typeName: "integer"),
                .init(name: "note", typeName: "text"),
            ],
            rows: [
                .init(id: 0, cells: [.text("1"), .text("a,b")]),
                .init(id: 1, cells: [.text("2"), .null]),
            ],
            rowCount: 2,
            elapsed: .milliseconds(3),
            status: .rows,
            truncated: false
        )

        #expect(
            ResultsTablePresentation.exportContent(for: rows, as: .csv)
                == ResultExporter.csv(for: rows)
        )
        #expect(
            ResultsTablePresentation.exportContent(for: rows, as: .json)
                == ResultExporter.json(for: rows)
        )
        #expect(
            ResultsTablePresentation.exportContent(for: rows, as: .markdown)
                == ResultExporter.markdown(for: rows)
        )
        #expect(ResultsTablePresentation.exportContent(for: rows, as: .csv) == "id,note\r\n1,\"a,b\"\r\n2,")
        #expect(
            ResultsTablePresentation.exportContent(for: rows, as: .markdown)
                == "| id | note |\n| --- | --- |\n| 1 | a,b |\n| 2 |  |"
        )
    }

    @Test("clipboard content reuses the on-device ResultExporter serializers byte-for-byte")
    func clipboardContent() {
        let rows = QueryResult(
            columns: [
                .init(name: "id", typeName: "integer"),
                .init(name: "note", typeName: "text"),
            ],
            rows: [
                .init(id: 0, cells: [.text("1"), .text("a,b")]),
                .init(id: 1, cells: [.text("2"), .null]),
            ],
            rowCount: 2,
            elapsed: .milliseconds(3),
            status: .rows,
            truncated: false
        )

        #expect(
            ResultsTablePresentation.clipboardContent(for: rows, as: .csv)
                == ResultExporter.csv(for: rows)
        )
        #expect(
            ResultsTablePresentation.clipboardContent(for: rows, as: .json)
                == ResultExporter.json(for: rows)
        )
        #expect(
            ResultsTablePresentation.clipboardContent(for: rows, as: .markdown)
                == ResultExporter.markdown(for: rows)
        )
        // Clipboard copy-as and file export produce identical bytes for the same format.
        #expect(
            ResultsTablePresentation.clipboardContent(for: rows, as: .markdown)
                == ResultsTablePresentation.exportContent(for: rows, as: .markdown)
        )
    }
}

@Suite("ResultsTablePresentation cell selection")
struct ResultsTableCellSelectionTests {
  private var result: QueryResult {
    QueryResult(
      columns: [.init(name: "id", typeName: "int4"), .init(name: "note", typeName: "text")],
      rows: [
        .init(id: 0, cells: [.text("1"), .text("hello\tworld")]),
        .init(id: 1, cells: [.text("2"), .null]),
      ],
      rowCount: 2,
      elapsed: .milliseconds(1),
      status: .rows,
      truncated: false
    )
  }

  @Test("cell text returns raw values and empty string for NULL")
  func cellText() {
    #expect(
      ResultsTablePresentation.cellText(for: result, at: .init(row: 0, column: 1)) == "hello\tworld")
    #expect(ResultsTablePresentation.cellText(for: result, at: .init(row: 1, column: 1)) == "")
    #expect(ResultsTablePresentation.cellText(for: result, at: .init(row: 5, column: 0)) == nil)
    #expect(ResultsTablePresentation.cellText(for: result, at: .init(row: 0, column: 9)) == nil)
  }

  @Test("cell NULL state is reported per address")
  func cellNullState() {
    #expect(ResultsTablePresentation.cellIsNull(for: result, at: .init(row: 1, column: 1)) == true)
    #expect(ResultsTablePresentation.cellIsNull(for: result, at: .init(row: 0, column: 0)) == false)
    #expect(ResultsTablePresentation.cellIsNull(for: result, at: .init(row: 9, column: 0)) == nil)
  }

  @Test("row text copies tab-separated values with flattened tabs")
  func rowText() {
    #expect(ResultsTablePresentation.rowText(for: result, rowIndex: 0) == "1\thello world")
    // NULL renders as the literal NULL in row copies, matching the grid's
    // existing whole-result TSV copy semantics.
    #expect(ResultsTablePresentation.rowText(for: result, rowIndex: 1) == "2\tNULL")
    #expect(ResultsTablePresentation.rowText(for: result, rowIndex: 7) == nil)
  }
}
