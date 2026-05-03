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
            guard isSQLCode(at: match.range.location, in: sql),
                  let range = Range(match.range, in: sql) else { return nil }
            let token = sql[range].lowercased()
            return keywords.contains(token) ? match.range : nil
        }
    }

    private static func isSQLCode(at utf16Location: Int, in sql: String) -> Bool {
        enum Mode {
            case code
            case singleQuotedString
            case doubleQuotedIdentifier
            case lineComment
            case blockComment
        }

        var mode = Mode.code
        var index = sql.startIndex
        var currentLocation = 0

        while index < sql.endIndex, currentLocation < utf16Location {
            let character = sql[index]
            let next = sql.index(after: index)
            let nextCharacter = next < sql.endIndex ? sql[next] : nil

            switch mode {
            case .code:
                if character == "'" {
                    mode = .singleQuotedString
                } else if character == "\"" {
                    mode = .doubleQuotedIdentifier
                } else if character == "-", nextCharacter == "-" {
                    mode = .lineComment
                    index = next
                    currentLocation += 1
                } else if character == "/", nextCharacter == "*" {
                    mode = .blockComment
                    index = next
                    currentLocation += 1
                }
            case .singleQuotedString:
                if character == "'" {
                    if nextCharacter == "'" {
                        index = next
                        currentLocation += 1
                    } else {
                        mode = .code
                    }
                }
            case .doubleQuotedIdentifier:
                if character == "\"" {
                    if nextCharacter == "\"" {
                        index = next
                        currentLocation += 1
                    } else {
                        mode = .code
                    }
                }
            case .lineComment:
                if character == "\n" { mode = .code }
            case .blockComment:
                if character == "*", nextCharacter == "/" {
                    mode = .code
                    index = next
                    currentLocation += 1
                }
            }

            currentLocation += character.utf16.count
            index = sql.index(after: index)
        }

        return mode == .code
    }
}
