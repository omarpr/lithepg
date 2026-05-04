import AppKit
import SwiftUI
import LithePGCore

struct ResultsTable: View {
    let result: QueryResult?
    @State private var copiedAtLeastOnce = false
    @State private var page = 1

    var body: some View {
        VStack(spacing: 0) {
            actionBar(for: result)
            Divider()
            Group {
                if let result {
                    content(for: result, page: normalizedPage(for: result))
                } else {
                    noResultState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: result) { _, _ in
            page = 1
            copiedAtLeastOnce = false
        }
    }

    @ViewBuilder
    private func content(for result: QueryResult, page: Int) -> some View {
        switch result.status {
        case .command:
            statusState(
                systemImage: "checkmark.circle",
                title: ResultsTablePresentation.commandTitle(for: result),
                detail: ResultsTablePresentation.commandDetail(for: result),
                tint: .green
            )
        case .empty:
            statusState(
                systemImage: "tablecells.badge.ellipsis",
                title: ResultsTablePresentation.emptyTitle(for: result),
                detail: ResultsTablePresentation.emptyDetail(for: result),
                tint: .secondary
            )
        case .rows:
            VStack(spacing: 0) {
                GeometryReader { proxy in
                    let columnWidths = ResultsTablePresentation.columnWidths(
                        availableWidth: proxy.size.width,
                        columnCount: result.columns.count
                    )
                    let tableBodyWidth = ResultsTablePresentation.tableBodyWidth(for: columnWidths)
                    ScrollView([.horizontal, .vertical]) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                indexCell("#", isHeader: true)
                                    .accessibilityIdentifier("result-index-header")
                                ForEach(Array(result.columns.enumerated()), id: \.offset) { columnIndex, column in
                                    headerCell(column, columnIndex: columnIndex, width: columnWidths[columnIndex])
                                }
                            }
                            .frame(width: tableBodyWidth, alignment: .leading)

                            ForEach(Array(ResultsTablePresentation.rows(for: result, page: page).enumerated()), id: \.element.id) { pageRowIndex, row in
                                let rowIndex = ResultsTablePresentation.absoluteRowNumber(pageRowIndex: pageRowIndex, page: page) - 1
                                HStack(spacing: 0) {
                                    indexCell(String(rowIndex + 1), isHeader: false)
                                        .accessibilityIdentifier("result-row-index-\(rowIndex)")
                                    ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cellValue in
                                        dataCell(ResultsTablePresentation.render(cellValue), isNull: cellValue == .null, width: columnWidths[columnIndex])
                                            .accessibilityIdentifier("result-cell-\(rowIndex)-\(columnIndex)")
                                    }
                                }
                                .frame(width: tableBodyWidth, alignment: .leading)
                            }
                        }
                        .padding(ResultsTablePresentation.tablePadding)
                        .frame(
                            minWidth: proxy.size.width,
                            minHeight: proxy.size.height,
                            alignment: .topLeading
                        )
                        .background(.background)
                    }
                }
                Divider()
                paginationBar(for: result, page: page)
                if let status = ResultsTablePresentation.truncationStatus(for: result) {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(status)
                            .lineLimit(1)
                        Spacer()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.bar)
                }
            }
        }
    }

    private var noResultState: some View {
        VStack(spacing: 8) {
            Text("Ready when you are.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Run a query to render rows here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusState(systemImage: String, title: String, detail: String, tint: Color) -> some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionBar(for result: QueryResult?) -> some View {
        HStack(spacing: 10) {
            if let result {
                let page = normalizedPage(for: result)
                Text(ResultsTablePresentation.primaryCount(for: result))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 28, alignment: .trailing)
                Text(ResultsTablePresentation.secondaryStatus(for: result, page: page))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(ResultsTablePresentation.commandStatus(for: result))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(result.truncated ? .orange : .secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            } else {
                Spacer()
            }

            Spacer()

            Label("Table", systemImage: "tablecells")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {} label: {
                Image(systemName: "line.3.horizontal.decrease")
            }
            .help("Filter results")
            .disabled(true)

            Button {
                copy(result)
            } label: {
                Image(systemName: copiedAtLeastOnce ? "checkmark" : "doc.on.doc")
            }
            .help("Copy results")
            .disabled(result == nil)

            Button {} label: {
                Image(systemName: "arrow.down.to.line")
            }
            .help("Export results lands in a later polish pass")
            .disabled(true)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func paginationBar(for result: QueryResult, page: Int) -> some View {
        HStack(spacing: 10) {
            Text(ResultsTablePresentation.pageStatus(for: result, page: page))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                self.page = max(1, page - 1)
            } label: {
                Label("Previous Page", systemImage: "chevron.left")
            }
            .labelStyle(.iconOnly)
            .help("Previous page")
            .disabled(!ResultsTablePresentation.canGoPrevious(page: page))

            Button {
                self.page = min(ResultsTablePresentation.pageCount(for: result), page + 1)
            } label: {
                Label("Next Page", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .help("Next page")
            .disabled(!ResultsTablePresentation.canGoNext(result, page: page))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
    }

    private func normalizedPage(for result: QueryResult) -> Int {
        min(max(page, 1), ResultsTablePresentation.pageCount(for: result))
    }

    private func headerCell(_ column: QueryResult.Column, columnIndex: Int, width: CGFloat) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(ResultsTablePresentation.headerName(for: column))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityIdentifier("result-header-\(columnIndex)")
                .accessibilityLabel(ResultsTablePresentation.headerAccessibilityLabel(for: column))
            Text(ResultsTablePresentation.headerType(for: column))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: width, alignment: .leading)
        .background(.quaternary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func dataCell(_ value: String, isNull: Bool, width: CGFloat) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(isNull ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width, alignment: .leading)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
    }

    private func indexCell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, isHeader ? 7 : 6)
            .frame(width: ResultsTablePresentation.indexColumnWidth, alignment: .trailing)
            .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(isHeader ? 0.35 : 0.2))
                    .frame(height: 1)
            }
    }

    private func copy(_ result: QueryResult?) {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ResultsTablePresentation.copyText(for: result), forType: .string)
        copiedAtLeastOnce = true
    }
}

enum ResultsTablePresentation {
    static let pageSize = 100
    static let indexColumnWidth: CGFloat = 44
    static let minimumColumnWidth: CGFloat = 126
    static let tablePadding: CGFloat = 10

    static func columnWidths(availableWidth: CGFloat, columnCount: Int) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        let usableWidth = max(0, availableWidth - indexColumnWidth - (tablePadding * 2))
        let minimumContentWidth = minimumColumnWidth * CGFloat(columnCount)
        guard usableWidth > minimumContentWidth else {
            return Array(repeating: minimumColumnWidth, count: columnCount)
        }

        let baseWidth = floor(usableWidth / CGFloat(columnCount))
        let remainder = usableWidth - (baseWidth * CGFloat(columnCount))
        return (0..<columnCount).map { columnIndex in
            columnIndex == columnCount - 1 ? baseWidth + remainder : baseWidth
        }
    }

    static func tableBodyWidth(for columnWidths: [CGFloat]) -> CGFloat {
        indexColumnWidth + columnWidths.reduce(0, +)
    }

    static func tableTotalWidth(availableWidth: CGFloat, columnCount: Int) -> CGFloat {
        tableBodyWidth(for: columnWidths(availableWidth: availableWidth, columnCount: columnCount)) + (tablePadding * 2)
    }

    static func primaryCount(for result: QueryResult) -> String {
        switch result.status {
        case .rows, .empty:
            formattedCount(result.rowCount)
        case .command(_, let affected):
            formattedCount(affected)
        }
    }

    static func secondaryStatus(for result: QueryResult, page: Int = 1) -> String {
        switch result.status {
        case .rows:
            "\(visibleRangeStatus(for: result, page: page)) · \(elapsed(result.elapsed))"
        case .command:
            "affected · \(elapsed(result.elapsed))"
        case .empty:
            "no rows · \(elapsed(result.elapsed))"
        }
    }

    static func commandStatus(for result: QueryResult) -> String {
        result.truncated ? "Truncated" : "Complete"
    }

    static func truncationStatus(for result: QueryResult) -> String? {
        guard result.truncated else { return nil }
        return "Result capped at 10,000 rows. Refine the query or add SQL LIMIT/OFFSET for server-side paging."
    }

    static func pageCount(for result: QueryResult) -> Int {
        guard result.status == .rows else { return 1 }
        return max(1, Int(ceil(Double(result.rows.count) / Double(pageSize))))
    }

    static func rows(for result: QueryResult, page: Int) -> ArraySlice<QueryResult.Row> {
        guard result.status == .rows, !result.rows.isEmpty else { return [] }
        let normalizedPage = min(max(page, 1), pageCount(for: result))
        let start = (normalizedPage - 1) * pageSize
        let end = min(start + pageSize, result.rows.count)
        return result.rows[start..<end]
    }

    static func absoluteRowNumber(pageRowIndex: Int, page: Int) -> Int {
        ((max(page, 1) - 1) * pageSize) + pageRowIndex + 1
    }

    static func canGoPrevious(page: Int) -> Bool {
        page > 1
    }

    static func canGoNext(_ result: QueryResult, page: Int) -> Bool {
        page < pageCount(for: result)
    }

    static func pageStatus(for result: QueryResult, page: Int) -> String {
        guard result.status == .rows, !result.rows.isEmpty else { return "Page 1 of 1" }
        let normalizedPage = min(max(page, 1), pageCount(for: result))
        let start = ((normalizedPage - 1) * pageSize) + 1
        let end = min(normalizedPage * pageSize, result.rows.count)
        return "Rows \(formattedCount(start))–\(formattedCount(end)) of \(formattedCount(result.rows.count)) · Page \(formattedCount(normalizedPage)) of \(formattedCount(pageCount(for: result)))"
    }

    static func visibleRangeStatus(for result: QueryResult, page: Int) -> String {
        guard result.status == .rows, !result.rows.isEmpty else { return "no rows" }
        let normalizedPage = min(max(page, 1), pageCount(for: result))
        let start = ((normalizedPage - 1) * pageSize) + 1
        let end = min(normalizedPage * pageSize, result.rows.count)
        if result.rows.count <= pageSize {
            return "\(pluralized(result.rowCount, singular: "row"))"
        }
        return "rows \(formattedCount(start))–\(formattedCount(end)) of \(formattedCount(result.rows.count))"
    }

    static func headerName(for column: QueryResult.Column) -> String {
        column.name
    }

    static func headerType(for column: QueryResult.Column) -> String {
        column.typeName.uppercased()
    }

    static func headerAccessibilityLabel(for column: QueryResult.Column) -> String {
        column.name
    }

    static func emptyTitle(for result: QueryResult) -> String {
        "Query completed"
    }

    static func emptyDetail(for result: QueryResult) -> String {
        "No rows were returned · \(elapsed(result.elapsed))"
    }

    static func commandTitle(for result: QueryResult) -> String {
        if case .command(let tag, _) = result.status {
            "\(tag) completed"
        } else {
            "Command completed"
        }
    }

    static func commandDetail(for result: QueryResult) -> String {
        if case .command(_, let affected) = result.status {
            "\(pluralized(affected, singular: "row")) affected · \(elapsed(result.elapsed))"
        } else {
            "Command completed · \(elapsed(result.elapsed))"
        }
    }

    static func render(_ cell: QueryResult.Cell) -> String {
        switch cell {
        case .null: "NULL"
        case .text(let value): value
        }
    }

    static func copyText(for result: QueryResult) -> String {
        switch result.status {
        case .rows:
            let header = result.columns.map { escapeCopyField($0.name) }.joined(separator: "\t")
            let rows = result.rows.map { row in
                row.cells.map { escapeCopyField(render($0)) }.joined(separator: "\t")
            }
            return ([header] + rows).joined(separator: "\n")
        case .empty:
            return emptyDetail(for: result)
        case .command:
            return commandDetail(for: result)
        }
    }

    private static func escapeCopyField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }

    private static func elapsed(_ duration: Duration) -> String {
        let components = duration.components
        let milliseconds = components.seconds * 1_000 + components.attoseconds / 1_000_000_000_000_000
        if milliseconds < 1_000 {
            return "\(milliseconds) ms"
        }
        let seconds = Double(milliseconds) / 1_000
        return String(format: "%.1f s", seconds)
    }

    private static func pluralized(_ count: Int, singular: String) -> String {
        "\(formattedCount(count)) \(singular)\(count == 1 ? "" : "s")"
    }

    private static func formattedCount(_ count: Int) -> String {
        count.formatted(.number)
    }
}
