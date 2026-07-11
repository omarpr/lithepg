import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LithePGCore

struct ResultsTable: View {
    let result: QueryResult?
    @State private var copiedAtLeastOnce = false
    @State private var page = 1
    @State private var selectedCell: ResultsTablePresentation.CellAddress?
    @State private var editingCell: ResultsTablePresentation.CellAddress?
    @State private var editedCellText = ""

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
            selectedCell = nil
            editingCell = nil
        }
        // Cmd-C copies the selected cell; falls back to the menu copy actions.
        .copyable(selectedCellCopyItems)
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
                    let visibleRows = Array(ResultsTablePresentation.rows(for: result, page: page).enumerated())
                    let fillerRows = ResultsTablePresentation.fillerRowCount(
                        viewportHeight: proxy.size.height,
                        visibleRowCount: visibleRows.count
                    )
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

                            ForEach(visibleRows, id: \.element.id) { pageRowIndex, row in
                                let rowIndex = ResultsTablePresentation.absoluteRowNumber(pageRowIndex: pageRowIndex, page: page) - 1
                                HStack(spacing: 0) {
                                    indexCell(String(rowIndex + 1), isHeader: false)
                                        .accessibilityIdentifier("result-row-index-\(rowIndex)")
                                    ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cellValue in
                                        dataCell(
                                            ResultsTablePresentation.render(cellValue),
                                            isNull: cellValue == .null,
                                            width: columnWidths[columnIndex],
                                            address: .init(row: rowIndex, column: columnIndex),
                                            in: result
                                        )
                                        .accessibilityIdentifier("result-cell-\(rowIndex)-\(columnIndex)")
                                    }
                                }
                                .frame(width: tableBodyWidth, alignment: .leading)
                            }

                            ForEach(0..<fillerRows, id: \.self) { fillerRow in
                                HStack(spacing: 0) {
                                    indexCell("", isHeader: false)
                                    ForEach(Array(columnWidths.enumerated()), id: \.offset) { columnIndex, width in
                                        fillerCell(width: width)
                                            .accessibilityIdentifier("result-filler-cell-\(fillerRow)-\(columnIndex)")
                                    }
                                }
                                .frame(width: tableBodyWidth, alignment: .leading)
                                .accessibilityHidden(true)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(maxHeight: .infinity)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

            Menu {
                Button("Copy (TSV)") { copy(result) }
                Divider()
                Button("Copy as CSV") { copyAs(result, format: .csv) }
                Button("Copy as JSON") { copyAs(result, format: .json) }
                Button("Copy as Markdown") { copyAs(result, format: .markdown) }
                Button("Copy as SQL inserts") { copyAs(result, format: .sqlInsert) }
                    .disabled(!ResultsTablePresentation.canExport(result))
            } label: {
                Image(systemName: copiedAtLeastOnce ? "checkmark" : "doc.on.doc")
            } primaryAction: {
                copy(result)
            }
            .menuIndicator(.hidden)
            .help("Copy results. Click to copy TSV or pick CSV, JSON or Markdown")
            .disabled(result == nil)

            Menu {
                Button("CSV (.csv)") { export(result, as: .csv) }
                Button("TSV (.tsv)") { export(result, as: .tsv) }
                Button("JSON (.json)") { export(result, as: .json) }
                Button("Markdown (.md)") { export(result, as: .markdown) }
                Button("SQL inserts (.sql)") { export(result, as: .sqlInsert) }
            } label: {
                Image(systemName: "arrow.down.to.line")
            }
            .menuIndicator(.hidden)
            .help("Export results to CSV, TSV, JSON, Markdown or SQL inserts")
            .disabled(!ResultsTablePresentation.canExport(result))
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
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .accessibilityIdentifier("result-header-\(columnIndex)")
                .accessibilityLabel(ResultsTablePresentation.headerAccessibilityLabel(for: column))
            Text(ResultsTablePresentation.headerType(for: column))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .frame(width: width, height: ResultsTablePresentation.headerRowHeight, alignment: .leading)
        .background(.quaternary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func dataCell(
        _ value: String,
        isNull: Bool,
        width: CGFloat,
        address: ResultsTablePresentation.CellAddress,
        in result: QueryResult
    ) -> some View {
        let isSelected = selectedCell == address
        return Text(value)
            .font(.callout.monospaced())
            .foregroundStyle(isNull ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(width: width, height: ResultsTablePresentation.bodyRowHeight, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                selectedCell = address
                beginEditing(address, in: result)
            }
            .onTapGesture { selectedCell = address }
            .contextMenu {
                Button("Copy cell") { copyCell(address, in: result) }
                Button("Copy row") { copyRow(address.row, in: result) }
                Button("View and edit…") {
                    selectedCell = address
                    beginEditing(address, in: result)
                }
            }
            .popover(
                isPresented: Binding(
                    get: { editingCell == address },
                    set: { if !$0 { editingCell = nil } }
                ),
                arrowEdge: .bottom
            ) {
                cellEditor(address, in: result)
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isNull ? "NULL" : value)
            .accessibilityHint("Click to select, double-click to view and edit")
    }

    /// Editable detail for one cell. Edits stay local to this popover: a query
    /// result cannot safely be written back to the database (its source table
    /// and key are unknown), so the affordance is copy-what-you-changed.
    private func cellEditor(
        _ address: ResultsTablePresentation.CellAddress,
        in result: QueryResult
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ResultsTablePresentation.headerName(for: result.columns[address.column]))
                    .font(.headline)
                if ResultsTablePresentation.cellIsNull(for: result, at: address) == true {
                    Text("NULL")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Row \(address.row + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $editedCellText)
                .font(.callout.monospaced())
                .frame(width: 340, height: 120)
                .accessibilityIdentifier("cell-editor")
            HStack {
                Text("Edits are local. Copy the value to use it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset") {
                    editedCellText = ResultsTablePresentation.cellText(for: result, at: address) ?? ""
                }
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(editedCellText, forType: .string)
                    copiedAtLeastOnce = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private var selectedCellCopyItems: [String] {
        guard let result, let selectedCell,
            let text = ResultsTablePresentation.cellText(for: result, at: selectedCell)
        else { return [] }
        return [text]
    }

    private func beginEditing(
        _ address: ResultsTablePresentation.CellAddress, in result: QueryResult
    ) {
        editedCellText = ResultsTablePresentation.cellText(for: result, at: address) ?? ""
        editingCell = address
    }

    private func copyCell(
        _ address: ResultsTablePresentation.CellAddress, in result: QueryResult
    ) {
        guard let text = ResultsTablePresentation.cellText(for: result, at: address) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedAtLeastOnce = true
    }

    private func copyRow(_ rowIndex: Int, in result: QueryResult) {
        guard let text = ResultsTablePresentation.rowText(for: result, rowIndex: rowIndex) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedAtLeastOnce = true
    }

    private func indexCell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, isHeader ? 7 : 6)
            .frame(
                width: ResultsTablePresentation.indexColumnWidth,
                height: isHeader ? ResultsTablePresentation.headerRowHeight : ResultsTablePresentation.bodyRowHeight,
                alignment: .trailing
            )
            .background(isHeader ? Color.secondary.opacity(0.12) : Color.clear)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(isHeader ? 0.35 : 0.2))
                    .frame(height: 1)
            }
    }

    private func fillerCell(width: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: width, height: ResultsTablePresentation.bodyRowHeight)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 1)
            }
    }

    private func copy(_ result: QueryResult?) {
        guard let result else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ResultsTablePresentation.copyText(for: result), forType: .string)
        copiedAtLeastOnce = true
    }

    private func copyAs(_ result: QueryResult?, format: ResultExporter.Format) {
        guard let result, ResultsTablePresentation.canExport(result) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            ResultsTablePresentation.clipboardContent(for: result, as: format),
            forType: .string
        )
        copiedAtLeastOnce = true
    }

    private func export(_ result: QueryResult?, as format: ResultExporter.Format) {
        guard let result, ResultsTablePresentation.canExport(result) else { return }
        let content = ResultsTablePresentation.exportContent(for: result, as: format)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = ResultsTablePresentation.defaultExportFileName(for: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [Self.contentType(for: format)]

        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    private static func contentType(for format: ResultExporter.Format) -> UTType {
        switch format {
        case .csv: .commaSeparatedText
        case .tsv: .tabSeparatedText
        case .json: .json
        case .markdown, .sqlInsert: UTType(filenameExtension: format.fileExtension) ?? .plainText
        }
    }
}

enum ResultsTablePresentation {
    static let pageSize = 100
    static let indexColumnWidth: CGFloat = 44
    static let minimumColumnWidth: CGFloat = 126
    static let tablePadding: CGFloat = 10
    static let headerRowHeight: CGFloat = 29
    static let bodyRowHeight: CGFloat = 27

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

    static func fillerRowCount(viewportHeight: CGFloat, visibleRowCount: Int) -> Int {
        let occupiedHeight = (tablePadding * 2) + headerRowHeight + (CGFloat(max(visibleRowCount, 0)) * bodyRowHeight)
        let remainingHeight = viewportHeight - occupiedHeight
        guard remainingHeight > 0 else { return 0 }
        return Int(ceil(remainingHeight / bodyRowHeight))
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

    /// Identifies one cell on the current page by absolute row and column index.
    struct CellAddress: Equatable, Hashable {
        let row: Int
        let column: Int
    }

    /// The raw text of a cell for copying: NULL copies as an empty string.
    /// Returns nil when the address is out of bounds.
    static func cellText(for result: QueryResult, at address: CellAddress) -> String? {
        guard result.rows.indices.contains(address.row) else { return nil }
        let cells = result.rows[address.row].cells
        guard cells.indices.contains(address.column) else { return nil }
        switch cells[address.column] {
        case .null: return ""
        case .text(let value): return value
        }
    }

    /// Whether the addressed cell is SQL NULL. Nil when out of bounds.
    static func cellIsNull(for result: QueryResult, at address: CellAddress) -> Bool? {
        guard result.rows.indices.contains(address.row) else { return nil }
        let cells = result.rows[address.row].cells
        guard cells.indices.contains(address.column) else { return nil }
        return cells[address.column] == .null
    }

    /// One row as tab-separated text, matching the grid copy conventions.
    static func rowText(for result: QueryResult, rowIndex: Int) -> String? {
        guard result.rows.indices.contains(rowIndex) else { return nil }
        return result.rows[rowIndex].cells
            .map { escapeCopyField(render($0)) }
            .joined(separator: "\t")
    }

    static func render(_ cell: QueryResult.Cell) -> String {
        switch cell {
        case .null: "NULL"
        case .text(let value): value
        }
    }

    static func canExport(_ result: QueryResult?) -> Bool {
        guard let result else { return false }
        guard case .rows = result.status else { return false }
        return !result.columns.isEmpty
    }

    static func defaultExportFileName(for format: ResultExporter.Format) -> String {
        "lithepg-results.\(format.fileExtension)"
    }

    static func exportContent(for result: QueryResult, as format: ResultExporter.Format) -> String {
        ResultExporter.export(result, as: format)
    }

    static func clipboardContent(for result: QueryResult, as format: ResultExporter.Format) -> String {
        ResultExporter.export(result, as: format)
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
