import AppKit
import SwiftUI
import LithePGCore

struct ResultsTable: View {
    let result: QueryResult?
    @State private var copiedAtLeastOnce = false

    var body: some View {
        VStack(spacing: 0) {
            actionBar(for: result)
            Divider()
            Group {
                if let result {
                    content(for: result)
                } else {
                    noResultState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func content(for result: QueryResult) -> some View {
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
                ScrollView([.horizontal, .vertical]) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            indexCell("#", isHeader: true)
                                .accessibilityIdentifier("result-index-header")
                            ForEach(Array(result.columns.enumerated()), id: \.offset) { columnIndex, column in
                                headerCell(column, columnIndex: columnIndex)
                            }
                        }
                        ForEach(Array(result.rows.enumerated()), id: \.element.id) { rowIndex, row in
                            GridRow {
                                indexCell(String(rowIndex + 1), isHeader: false)
                                    .accessibilityIdentifier("result-row-index-\(rowIndex)")
                                ForEach(Array(row.cells.enumerated()), id: \.offset) { columnIndex, cellValue in
                                    dataCell(ResultsTablePresentation.render(cellValue), isNull: cellValue == .null)
                                        .accessibilityIdentifier("result-cell-\(rowIndex)-\(columnIndex)")
                                }
                            }
                        }
                    }
                    .padding(.top, 8)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
                }
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
                Text(ResultsTablePresentation.primaryCount(for: result))
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .frame(minWidth: 28, alignment: .trailing)
                Text(ResultsTablePresentation.secondaryStatus(for: result))
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

    private func headerCell(_ column: QueryResult.Column, columnIndex: Int) -> some View {
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
        .frame(minWidth: 126, alignment: .leading)
        .background(.quaternary)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(height: 1)
        }
    }

    private func dataCell(_ value: String, isNull: Bool) -> some View {
        Text(value)
            .font(.caption.monospaced())
            .foregroundStyle(isNull ? .tertiary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 126, maxWidth: 240, alignment: .leading)
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
            .frame(width: 44, alignment: .trailing)
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
    static func primaryCount(for result: QueryResult) -> String {
        switch result.status {
        case .rows, .empty:
            formattedCount(result.rowCount)
        case .command(_, let affected):
            formattedCount(affected)
        }
    }

    static func secondaryStatus(for result: QueryResult) -> String {
        switch result.status {
        case .rows:
            "\(result.rowCount == 1 ? "row" : "rows") · \(elapsed(result.elapsed))"
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
        return "Result capped at 10,000 rows. Refine the query or add LIMIT/OFFSET paging."
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
