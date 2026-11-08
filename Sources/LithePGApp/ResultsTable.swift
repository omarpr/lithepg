import AppKit
import SwiftUI
import UniformTypeIdentifiers
import LithePGCore

/// What the grid needs to write a cell back to the database. Nil makes the grid read-only.
struct ResultEditingActions {
    var editability: (_ column: Int) async -> ResultEditability
    var preview: (_ row: Int, _ column: Int, _ newValue: String?) -> Result<String, ResultEditError>
    /// Returns nil on success, otherwise a message to show in the editor.
    var save: (_ row: Int, _ column: Int, _ newValue: String?) async -> String?
    var isProduction: Bool
}

struct ResultsTable: View {
    let result: QueryResult?
    var editing: ResultEditingActions?
    @State private var copiedAtLeastOnce = false
    @State private var page = 1
    @State private var selectedCell: ResultsTablePresentation.CellAddress?
    @State private var editingSession: ResultsTablePresentation.CellEditorSession?
    @State private var columnWidthOverrides: [Int: CGFloat] = [:]
    @State private var columnResizeStart: ColumnResizeStart?
    @State private var filterText = ""
    @State private var showingFilter = false
    @FocusState private var filterFocused: Bool
    /// Bumped on every copy so only the latest one turns the copy icon back.
    @State private var copyFeedbackGeneration = 0

    private struct ColumnResizeStart {
        let columnIndex: Int
        let width: CGFloat
    }

    var body: some View {
        // The grid, counts, copy and export all work on the rows the filter leaves; cell
        // lookups (selection, copy cell, editing) use the full result by original row number.
        let renderedResult = result.map { ResultsTablePresentation.filtered($0, matching: filterText) }
        VStack(spacing: 0) {
            actionBar(for: renderedResult)
            Divider()
            Group {
                if let result = renderedResult {
                    content(for: result, page: normalizedPage(for: result))
                } else {
                    noResultState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: result) { old, new in
            // A saved cell changes the result in place; keep the page, widths and selection.
            guard !ResultsTablePresentation.isCellEdit(from: old, to: new) else { return }
            page = 1
            copiedAtLeastOnce = false
            filterText = ""
            showingFilter = false
            selectedCell = nil
            editingSession = nil
            columnWidthOverrides.removeAll()
            columnResizeStart = nil
        }
        // Cmd-C copies the selected cell; falls back to the menu copy actions.
        .copyable(selectedCellCopyItems)
        // One sheet for the whole grid. A popover per cell created presentation
        // machinery for every visible cell and made clicking noticeably slow.
        .sheet(item: $editingSession) { session in
            ResultCellEditorSheet(
                session: session,
                editing: editing,
                onClose: { editingSession = nil },
                onCopy: { value in
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                    markCopied()
                }
            )
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
                        columnCount: result.columns.count,
                        overrides: columnWidthOverrides
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

                            ForEach(visibleRows, id: \.element.id) { _, row in
                                // A row's id is its position in the full result, so numbering,
                                // selection and edits stay right while a filter hides rows.
                                let rowIndex = row.id
                                HStack(spacing: 0) {
                                    indexCell(String(rowIndex + 1), isHeader: false)
                                        .accessibilityIdentifier("result-row-index-\(rowIndex)")
                                    ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cellValue in
                                        dataCell(
                                            ResultsTablePresentation.render(cellValue),
                                            isNull: cellValue == .null,
                                            width: columnWidths[columnIndex],
                                            address: .init(row: rowIndex, column: columnIndex),
                                            in: self.result ?? result
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

            if showingFilter {
                filterField(total: self.result?.rows.count ?? 0, shown: result?.rows.count ?? 0)
            }

            Button {
                toggleFilter()
            } label: {
                Label(
                    "Filter",
                    systemImage: filterText.isEmpty
                        ? "line.3.horizontal.decrease.circle"
                        : "line.3.horizontal.decrease.circle.fill"
                )
                .labelStyle(.titleAndIcon)
                .barControlStyle(enabled: self.result?.status == .rows)
            }
            .accessibilityLabel(showingFilter ? "Hide filter" : "Filter rows")
            .keyboardShortcut("f", modifiers: [.command])
            .buttonAffordance(
                showingFilter ? "Hide the filter and show every row" : "Show only rows containing some text (⌘F)"
            )
            .disabled(self.result?.status != .rows)
            .accessibilityIdentifier("filter-results-button")

            Menu {
                Button("Copy (TSV)") { copy(result) }
                Divider()
                Button("Copy as CSV") { copyAs(result, format: .csv) }
                Button("Copy as JSON") { copyAs(result, format: .json) }
                Button("Copy as Markdown") { copyAs(result, format: .markdown) }
                Button("Copy as SQL inserts") { copyAs(result, format: .sqlInsert) }
                    .disabled(!ResultsTablePresentation.canExport(result))
            } label: {
                Label(
                    copiedAtLeastOnce ? "Copied" : "Copy",
                    systemImage: copiedAtLeastOnce ? "checkmark" : "doc.on.doc"
                )
                .labelStyle(.titleAndIcon)
                .barControlStyle(enabled: result != nil)
            } primaryAction: {
                copy(result)
            }
            // The arrow hints that holding offers CSV, JSON, Markdown and SQL inserts.
            .menuIndicator(.visible)
            // Borderless menus stretch to fill an HStack; keep the controls grouped at the right.
            .fixedSize()
            .accessibilityLabel(copiedAtLeastOnce ? "Results copied" : "Copy results")
            .buttonAffordance("Copy the rows shown. Click to copy TSV or pick CSV, JSON or Markdown")
            .disabled(result == nil)

            Menu {
                Button("CSV (.csv)") { export(result, as: .csv) }
                Button("TSV (.tsv)") { export(result, as: .tsv) }
                Button("JSON (.json)") { export(result, as: .json) }
                Button("Markdown (.md)") { export(result, as: .markdown) }
                Button("SQL inserts (.sql)") { export(result, as: .sqlInsert) }
            } label: {
                Label("Export", systemImage: "arrow.down.to.line")
                    .labelStyle(.titleAndIcon)
                    .barControlStyle(enabled: ResultsTablePresentation.canExport(result))
            }
            .menuIndicator(.visible)
            .fixedSize()
            .accessibilityLabel("Export results")
            .buttonAffordance("Export the rows shown to CSV, TSV, JSON, Markdown or SQL inserts")
            .disabled(!ResultsTablePresentation.canExport(result))
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func filterField(total: Int, shown: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter rows", text: $filterText)
                .textFieldStyle(.plain)
                .frame(width: 180)
                .focused($filterFocused)
                .onSubmit { filterFocused = false }
                .onExitCommand { toggleFilter() }
                .onChange(of: filterText) { _, _ in page = 1 }
                .accessibilityIdentifier("filter-results-field")
            if !filterText.isEmpty {
                Text("\(shown) of \(total)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityIdentifier("filter-results-count")
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonAffordance("Clear the filter")
                .accessibilityLabel("Clear filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        // Never squeeze the field into wrapping; the status text on the left gives way instead.
        .fixedSize()
    }

    private func toggleFilter() {
        if showingFilter {
            showingFilter = false
            filterText = ""
            filterFocused = false
        } else {
            showingFilter = true
            filterFocused = true
        }
    }

    /// Shows the copied checkmark briefly, then the copy icon again.
    private func markCopied() {
        copiedAtLeastOnce = true
        copyFeedbackGeneration += 1
        let generation = copyFeedbackGeneration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if copyFeedbackGeneration == generation { copiedAtLeastOnce = false }
        }
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
            .buttonAffordance("Previous page")
            .disabled(!ResultsTablePresentation.canGoPrevious(page: page))

            Button {
                self.page = min(ResultsTablePresentation.pageCount(for: result), page + 1)
            } label: {
                Label("Next Page", systemImage: "chevron.right")
            }
            .labelStyle(.iconOnly)
            .buttonAffordance("Next page")
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
                .font(.body.weight(.semibold))
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
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(
                    columnResizeStart?.columnIndex == columnIndex
                        ? Color.accentColor.opacity(0.75)
                        : Color.secondary.opacity(0.22)
                )
                .frame(width: 1)
                .padding(.vertical, 3)
                .frame(width: 9)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    if isHovering {
                        NSCursor.resizeLeftRight.set()
                    } else if columnResizeStart == nil {
                        NSCursor.arrow.set()
                    }
                }
                .highPriorityGesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if columnResizeStart?.columnIndex != columnIndex {
                                columnResizeStart = .init(columnIndex: columnIndex, width: width)
                            }
                            guard let start = columnResizeStart,
                                  start.columnIndex == columnIndex
                            else { return }
                            columnWidthOverrides[columnIndex] =
                                ResultsTablePresentation.resizedColumnWidth(
                                    startingWidth: start.width,
                                    translation: value.translation.width
                                )
                        }
                        .onEnded { _ in
                            columnResizeStart = nil
                            NSCursor.arrow.set()
                        }
                )
                .help("Drag to resize " + ResultsTablePresentation.headerName(for: column))
                .accessibilityLabel(
                    "Resize " + ResultsTablePresentation.headerName(for: column) + " column"
                )
                .accessibilityAdjustableAction { direction in
                    let delta: CGFloat = direction == .increment ? 20 : -20
                    columnWidthOverrides[columnIndex] =
                        ResultsTablePresentation.resizedColumnWidth(
                            startingWidth: width,
                            translation: delta
                        )
                }
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
            .font(.body.monospaced())
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
            // The single tap runs simultaneously with the double-tap recognizer,
            // so selection is instant instead of waiting out the double-click
            // interval; the double tap then also opens the editor.
            .gesture(
                TapGesture(count: 2).onEnded {
                    selectedCell = address
                    beginEditing(address, in: result)
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded { selectedCell = address }
            )
            .controlAffordance("Select this cell; double-click to view and edit")
            .contextMenu {
                Button("Copy cell") { copyCell(address, in: result) }
                Button("Copy row") { copyRow(address.row, in: result) }
                Button("View and edit…") {
                    selectedCell = address
                    beginEditing(address, in: result)
                }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isNull ? "NULL" : value)
            .accessibilityHint("Click to select, double-click to view and edit")
            // Double-click is a pointer gesture; VoiceOver needs a named action to reach the editor.
            .accessibilityAction(named: "View and edit") {
                selectedCell = address
                beginEditing(address, in: result)
            }
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
        editingSession = ResultsTablePresentation.cellEditorSession(for: result, at: address)
    }

    private func copyCell(
        _ address: ResultsTablePresentation.CellAddress, in result: QueryResult
    ) {
        guard let text = ResultsTablePresentation.cellText(for: result, at: address) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        markCopied()
    }

    private func copyRow(_ rowIndex: Int, in result: QueryResult) {
        guard let text = ResultsTablePresentation.rowText(for: result, rowIndex: rowIndex) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        markCopied()
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
        markCopied()
    }

    private func copyAs(_ result: QueryResult?, format: ResultExporter.Format) {
        guard let result, ResultsTablePresentation.canExport(result) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
            ResultsTablePresentation.clipboardContent(for: result, as: format),
            forType: .string
        )
        markCopied()
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

/// Views a cell and, when its column traces back to a table with a primary key, writes a new
/// value to the database. Saving always shows the exact UPDATE first and runs only after an
/// explicit confirmation. Read-only cells say why they cannot be edited.
struct ResultCellEditorSheet: View {
    let session: ResultsTablePresentation.CellEditorSession
    let editing: ResultEditingActions?
    let onClose: () -> Void
    let onCopy: (String) -> Void

    private enum Phase: Equatable {
        case checking
        case readOnly(String)
        case editing(table: String)
        case confirming(table: String, sql: String)
        case saving(table: String, sql: String)
    }

    @State private var text: String
    @State private var setNull: Bool
    @State private var phase: Phase = .checking
    @State private var errorMessage: String?
    @FocusState private var editorFocused: Bool

    init(
        session: ResultsTablePresentation.CellEditorSession,
        editing: ResultEditingActions?,
        onClose: @escaping () -> Void,
        onCopy: @escaping (String) -> Void
    ) {
        self.session = session
        self.editing = editing
        self.onClose = onClose
        self.onCopy = onCopy
        _text = State(initialValue: session.initialText)
        _setNull = State(initialValue: session.wasNull)
    }

    private var newValue: String? { setNull ? nil : text }
    private var hasChanges: Bool { setNull != session.wasNull || (!setNull && text != session.initialText) }
    private var isEditable: Bool {
        if case .editing = phase { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch phase {
            case .confirming(let table, let sql), .saving(let table, let sql):
                confirmation(table: table, sql: sql)
            default:
                valueEditor
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("cell-edit-error")
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 520)
        .task { await checkEditability() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(session.columnName)
                .font(.headline)
            if session.wasNull {
                Text("NULL")
                    .font(.caption.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Row \(session.rowNumber)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .buttonAffordance("Close without saving")
            .accessibilityLabel("Close cell editor")
            .accessibilityIdentifier("close-cell-editor")
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        if case .readOnly(let reason) = phase {
            // Shown first and in full, so a cell that cannot be saved never looks like a
            // broken editor.
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Read-only")
                        .font(.callout.weight(.semibold))
                    Text(reason)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("cell-read-only-reason")
        }
        TextEditor(text: $text)
            .font(.callout.monospaced())
            .frame(height: 140)
            .focused($editorFocused)
            .disabled(!isEditable || setNull)
            .opacity(setNull ? 0.45 : 1)
            .accessibilityIdentifier("cell-editor")

        switch phase {
        case .checking:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Checking whether this column can be edited…")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .readOnly:
            EmptyView()
        case .editing(let table):
            HStack {
                Toggle("Set to NULL", isOn: $setNull)
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("cell-set-null")
                Spacer()
                Text("Saves to \(table). You review the SQL before it runs.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        default:
            EmptyView()
        }
    }

    private func confirmation(table: String, sql: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Update this row in \(table)?")
                .font(.title3.weight(.semibold))
            if editing?.isProduction == true {
                Label(
                    "This is a production connection. The change is written immediately.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout.bold())
                .foregroundStyle(.red)
                .accessibilityIdentifier("cell-edit-production-warning")
            }
            ScrollView {
                Text(sql)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(height: 150)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier("cell-edit-sql-preview")
            Text("Only the row with this primary key changes. If the row was changed since you loaded it, nothing is written.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack {
            switch phase {
            case .confirming(let table, _), .saving(let table, _):
                Button("Back") {
                    errorMessage = nil
                    phase = .editing(table: table)
                }
                .disabled(isSaving)
                Spacer()
                if isSaving {
                    ProgressView().controlSize(.small)
                }
                Button("Cancel", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                Button(editing?.isProduction == true ? "Update Production Row" : "Update Row") {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving)
                .buttonAffordance("Run the UPDATE shown above")
                .accessibilityIdentifier("confirm-cell-edit")
            default:
                Button("Reset") {
                    text = session.initialText
                    setNull = session.wasNull
                    errorMessage = nil
                }
                .buttonAffordance("Restore the original cell value")
                .disabled(!hasChanges)
                Button("Copy") { onCopy(text) }
                    .buttonAffordance("Copy this cell value")
                Spacer()
                Button(isEditable ? "Cancel" : "Close", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .buttonAffordance("Close without saving")
                if isEditable {
                    Button("Save…") { reviewChange() }
                        .keyboardShortcut(.defaultAction)
                        .buttonAffordance("Review the SQL that saves this value")
                        .disabled(!hasChanges)
                        .accessibilityIdentifier("save-cell-edit")
                }
            }
        }
    }

    private var isSaving: Bool {
        if case .saving = phase { return true }
        return false
    }

    private func checkEditability() async {
        guard let editing else {
            phase = .readOnly("Connect to a database to edit results.")
            return
        }
        switch await editing.editability(session.address.column) {
        case .readOnly(let reason):
            phase = .readOnly(reason)
        case .editable(let target):
            phase = .editing(table: target.table)
            editorFocused = true
        }
    }

    private func reviewChange() {
        guard let editing, case .editing(let table) = phase else { return }
        switch editing.preview(session.address.row, session.address.column, newValue) {
        case .success(let sql):
            errorMessage = nil
            phase = .confirming(table: table, sql: sql)
        case .failure(let error):
            errorMessage = error.description
        }
    }

    private func save() async {
        guard let editing, case .confirming(let table, let sql) = phase else { return }
        phase = .saving(table: table, sql: sql)
        if let message = await editing.save(session.address.row, session.address.column, newValue) {
            errorMessage = message
            phase = .editing(table: table)
        } else {
            onClose()
        }
    }
}

enum ResultsTablePresentation {
    static let pageSize = 100
    static let indexColumnWidth: CGFloat = 44
    static let minimumColumnWidth: CGFloat = 126
    static let minimumResizableColumnWidth: CGFloat = 72
    /// The grid sits flush against the pane edges, like a native table view.
    static let tablePadding: CGFloat = 0
    static let headerRowHeight: CGFloat = 32
    static let bodyRowHeight: CGFloat = 30

    static func columnWidths(
        availableWidth: CGFloat,
        columnCount: Int,
        overrides: [Int: CGFloat] = [:]
    ) -> [CGFloat] {
        guard columnCount > 0 else { return [] }
        let usableWidth = max(0, availableWidth - indexColumnWidth - (tablePadding * 2))
        let minimumContentWidth = minimumColumnWidth * CGFloat(columnCount)
        let defaultWidths: [CGFloat]
        guard usableWidth > minimumContentWidth else {
            defaultWidths = Array(repeating: minimumColumnWidth, count: columnCount)
            return applying(overrides: overrides, to: defaultWidths)
        }

        let baseWidth = floor(usableWidth / CGFloat(columnCount))
        let remainder = usableWidth - (baseWidth * CGFloat(columnCount))
        defaultWidths = (0..<columnCount).map { columnIndex in
            columnIndex == columnCount - 1 ? baseWidth + remainder : baseWidth
        }
        return applying(overrides: overrides, to: defaultWidths)
    }

    static func resizedColumnWidth(startingWidth: CGFloat, translation: CGFloat) -> CGFloat {
        max(minimumResizableColumnWidth, startingWidth + translation)
    }

    private static func applying(
        overrides: [Int: CGFloat],
        to defaultWidths: [CGFloat]
    ) -> [CGFloat] {
        defaultWidths.enumerated().map { columnIndex, defaultWidth in
            guard let override = overrides[columnIndex] else { return defaultWidth }
            return max(minimumResizableColumnWidth, override)
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
    struct CellAddress: Equatable, Hashable, Identifiable {
        let row: Int
        let column: Int

        var id: String { "\(row):\(column)" }
    }

    struct CellEditorSession: Equatable, Identifiable {
        let address: CellAddress
        let columnName: String
        let rowNumber: Int
        let initialText: String
        let wasNull: Bool

        var id: CellAddress { address }
    }

    static func cellEditorSession(
        for result: QueryResult,
        at address: CellAddress
    ) -> CellEditorSession? {
        guard result.columns.indices.contains(address.column),
            let initialText = cellText(for: result, at: address),
            let wasNull = cellIsNull(for: result, at: address)
        else { return nil }

        return CellEditorSession(
            address: address,
            columnName: result.columns[address.column].name,
            rowNumber: address.row + 1,
            initialText: initialText,
            wasNull: wasNull
        )
    }

    /// Returns a new result with one local text edit applied. QueryResult is a
    /// value type, so the source result remains unchanged and no SQL is issued.
    /// The rows with a cell containing `query`, ignoring case and accents ("jose" finds
    /// "José"). Rows keep their ids, which are their positions in the full result.
    static func filtered(_ result: QueryResult, matching query: String) -> QueryResult {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty, result.status == .rows else { return result }
        let rows = result.rows.filter { row in
            row.cells.contains { cell in
                guard case .text(let value) = cell else { return false }
                return value.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        return QueryResult(
            columns: result.columns, rows: rows, rowCount: rows.count,
            elapsed: result.elapsed, status: result.status, truncated: result.truncated)
    }

    /// True when `new` is `old` with cell values changed in place, as after saving an edit,
    /// rather than the result of another run.
    static func isCellEdit(from old: QueryResult?, to new: QueryResult?) -> Bool {
        guard let old, let new else { return false }
        return old.columns == new.columns && old.rowCount == new.rowCount
            && old.elapsed == new.elapsed && old.status == new.status && old.rows.count == new.rows.count
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

private extension View {
    /// Buttons and menus in the results bar otherwise render in different grays. One style:
    /// full contrast when usable, clearly dimmed when not.
    func barControlStyle(enabled: Bool) -> some View {
        foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
    }
}
