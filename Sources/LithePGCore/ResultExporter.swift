import Foundation

/// Serializes a `QueryResult` into common text export formats.
///
/// Export is a local, on-device operation: it only reformats rows that the user
/// already fetched and never contacts the network, logs credentials, or auto-runs
/// SQL. Output mirrors what the results grid shows, so NULL and text cells stay
/// distinguishable in JSON while remaining human-readable in CSV.
public enum ResultExporter {
    /// Supported export formats.
    public enum Format: CaseIterable, Sendable {
        case csv
        case json

        /// Lowercase file extension (no dot) used when writing export files.
        public var fileExtension: String {
            switch self {
            case .csv: "csv"
            case .json: "json"
            }
        }
    }

    /// Serialize `result` into the requested `format`.
    public static func export(_ result: QueryResult, as format: Format) -> String {
        switch format {
        case .csv: csv(for: result)
        case .json: json(for: result)
        }
    }

    // MARK: - CSV (RFC 4180)

    /// RFC 4180 CSV: header row of column names, then one record per row, fields
    /// separated by commas and records by CRLF. Fields containing a comma, double
    /// quote, CR, or LF are wrapped in double quotes with embedded quotes doubled.
    /// NULL cells render as empty fields. A result with no columns yields "".
    public static func csv(for result: QueryResult) -> String {
        guard !result.columns.isEmpty else { return "" }
        var lines: [String] = []
        lines.append(result.columns.map { escapeCSVField($0.name) }.joined(separator: ","))
        for row in result.rows {
            lines.append(row.cells.map { escapeCSVField(csvValue($0)) }.joined(separator: ","))
        }
        return lines.joined(separator: "\r\n")
    }

    private static func csvValue(_ cell: QueryResult.Cell) -> String {
        switch cell {
        case .null: ""
        case .text(let value): value
        }
    }

    private static func escapeCSVField(_ value: String) -> String {
        let needsQuoting = value.contains(",")
            || value.contains("\"")
            || value.contains("\n")
            || value.contains("\r")
        guard needsQuoting else { return value }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    // MARK: - JSON

    /// A compact JSON array of objects, one per row, keyed by column name in
    /// column order. NULL cells encode as JSON `null`; text cells as JSON strings.
    /// A result with no rows yields "[]".
    public static func json(for result: QueryResult) -> String {
        var objects: [String] = []
        objects.reserveCapacity(result.rows.count)
        for row in result.rows {
            var pairs: [String] = []
            pairs.reserveCapacity(result.columns.count)
            for (index, column) in result.columns.enumerated() {
                let key = encodeJSONString(column.name)
                let value: String
                if index < row.cells.count {
                    value = encodeJSONValue(row.cells[index])
                } else {
                    value = "null"
                }
                pairs.append("\(key):\(value)")
            }
            objects.append("{\(pairs.joined(separator: ","))}")
        }
        return "[\(objects.joined(separator: ","))]"
    }

    private static func encodeJSONValue(_ cell: QueryResult.Cell) -> String {
        switch cell {
        case .null: "null"
        case .text(let value): encodeJSONString(value)
        }
    }

    private static func encodeJSONString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        result += "\""
        return result
    }
}
