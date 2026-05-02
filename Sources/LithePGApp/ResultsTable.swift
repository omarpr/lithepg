import SwiftUI
import LithePGCore

struct ResultsTable: View {
    let result: QueryResult?

    var body: some View {
        Group {
            if let result {
                content(for: result)
            } else {
                ContentUnavailableView(
                    "No Results Yet",
                    systemImage: "tablecells",
                    description: Text("Connect and run SQL to render rows here.")
                )
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func content(for result: QueryResult) -> some View {
        switch result.status {
        case .command(let tag, let affected):
            Text("\(tag) — \(affected) rows affected")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            Text("Query completed with no rows.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rows:
            ScrollView([.horizontal, .vertical]) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(result.columns, id: \.name) { column in
                            cell(column.name, isHeader: true)
                        }
                    }
                    ForEach(result.rows) { row in
                        GridRow {
                            ForEach(Array(row.cells.enumerated()), id: \.offset) { _, cellValue in
                                cell(render(cellValue), isHeader: false)
                            }
                        }
                    }
                }
            }
            if result.truncated {
                Text("Showing 10,000 of ≥10,000 rows. Pagination lands in v0.2b.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func cell(_ value: String, isHeader: Bool) -> some View {
        Text(value)
            .font(isHeader ? .caption.bold() : .caption.monospaced())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(minWidth: 120, alignment: .leading)
            .background(isHeader ? Color.secondary.opacity(0.15) : Color.clear)
            .border(Color.secondary.opacity(0.18))
    }

    private func render(_ cell: QueryResult.Cell) -> String {
        switch cell {
        case .null: "NULL"
        case .text(let value): value
        }
    }
}
