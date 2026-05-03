import AppKit

struct SQLSyntaxHighlighter {
    static let keywords: Set<String> = [
        "and", "as", "by", "create", "delete", "desc", "drop", "from", "group",
        "having", "insert", "into", "join", "left", "limit", "not", "null", "offset",
        "on", "or", "order", "right", "select", "set", "table", "update", "values", "view", "where"
    ]

    @MainActor
    static func apply(to textView: NSTextView) {
        let fullRange = NSRange(location: 0, length: textView.string.utf16.count)
        let selectedRanges = textView.selectedRanges
        let baseFont = textView.font ?? .monospacedSystemFont(ofSize: 14, weight: .regular)

        textView.textStorage?.beginEditing()
        textView.textStorage?.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: fullRange)

        for range in keywordRanges(in: textView.string) {
            textView.textStorage?.addAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .semibold),
                .foregroundColor: NSColor.systemBlue,
            ], range: range)
        }
        textView.textStorage?.endEditing()
        textView.selectedRanges = selectedRanges
    }

    static func keywordRanges(in sql: String) -> [NSRange] {
        let pattern = #"\b[A-Za-z_][A-Za-z0-9_]*\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let fullRange = NSRange(sql.startIndex..<sql.endIndex, in: sql)
        return regex.matches(in: sql, range: fullRange).compactMap { match in
            guard !isInsideSingleQuotedString(match.range.location, in: sql),
                  let range = Range(match.range, in: sql) else { return nil }
            let token = sql[range].lowercased()
            return keywords.contains(token) ? match.range : nil
        }
    }

    private static func isInsideSingleQuotedString(_ utf16Location: Int, in sql: String) -> Bool {
        var inString = false
        var index = sql.startIndex
        var currentLocation = 0

        while index < sql.endIndex, currentLocation < utf16Location {
            if sql[index] == "'" {
                let next = sql.index(after: index)
                if inString, next < sql.endIndex, sql[next] == "'" {
                    index = sql.index(after: next)
                    currentLocation += 2
                    continue
                }
                inString.toggle()
            }
            currentLocation += sql[index].utf16.count
            index = sql.index(after: index)
        }

        return inString
    }
}
