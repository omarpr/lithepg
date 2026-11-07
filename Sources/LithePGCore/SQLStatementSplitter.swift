import Foundation

/// Splits editor text into top-level SQL statements, so the app can run the one under the
/// caret instead of sending everything (PostgreSQL rejects several statements in one
/// extended-protocol query).
///
/// Semicolons only end a statement in code: never inside single-quoted strings (including
/// `E''` escape strings), double-quoted identifiers, `--` line comments, nested `/* */` block
/// comments or `$tag$` dollar-quoted bodies such as function definitions.
///
/// All offsets are UTF-16, matching `NSString` and `NSTextView` selection ranges.
public enum SQLStatementSplitter {
    public struct Statement: Equatable, Sendable {
        /// UTF-16 range of the statement, trimmed of surrounding whitespace, including its `;`.
        public let range: Range<Int>
        public let text: String
    }

    public static func statements(in sql: String) -> [Statement] {
        let units = Array(sql.utf16)
        var statements: [Statement] = []
        var segmentStart = 0
        var codeStart: Int?  // first code (non-comment, non-space) unit in the segment
        var index = 0

        func closeSegment(endingAt end: Int) {
            defer {
                segmentStart = end
                codeStart = nil
            }
            guard codeStart != nil else { return }
            var lower = segmentStart
            var upper = end
            while lower < upper, isWhitespace(units[lower]) { lower += 1 }
            while upper > lower, isWhitespace(units[upper - 1]) { upper -= 1 }
            guard lower < upper else { return }
            let text = String(utf16CodeUnits: Array(units[lower..<upper]), count: upper - lower)
            statements.append(Statement(range: lower..<upper, text: text))
        }

        func markCode(_ position: Int) {
            if codeStart == nil { codeStart = position }
        }

        while index < units.count {
            let unit = units[index]
            let next = index + 1 < units.count ? units[index + 1] : nil

            switch unit {
            case ascii("-") where next == ascii("-"):
                index = skipLineComment(units, from: index)
            case ascii("/") where next == ascii("*"):
                index = skipBlockComment(units, from: index)
            case ascii("'"):
                markCode(index)
                let escapes = index > 0
                    && (units[index - 1] == ascii("E") || units[index - 1] == ascii("e"))
                    && (index < 2 || !isIdentifierUnit(units[index - 2]))
                index = skipQuoted(units, from: index, quote: ascii("'"), backslashEscapes: escapes)
            case ascii("\""):
                markCode(index)
                index = skipQuoted(units, from: index, quote: ascii("\""), backslashEscapes: false)
            case ascii("$"):
                markCode(index)
                if let tagEnd = dollarTagEnd(units, from: index) {
                    index = skipDollarQuoted(units, openingFrom: index, tagEnd: tagEnd)
                } else {
                    index += 1
                }
            case ascii(";"):
                // A lone terminator is not a statement, so it does not mark code.
                closeSegment(endingAt: index + 1)
                index += 1
            default:
                if !isWhitespace(unit) { markCode(index) }
                index += 1
            }
        }
        closeSegment(endingAt: units.count)
        return statements
    }

    /// The statement the caret belongs to: the last one starting at or before the caret, so a
    /// caret just past a `;` or on the blank lines after it still means that statement. A caret
    /// before the first statement means the first. Nil when the text holds no statement.
    public static func statement(at utf16Offset: Int, in sql: String) -> Statement? {
        let all = statements(in: sql)
        return all.last { $0.range.lowerBound <= utf16Offset } ?? all.first
    }

    // MARK: - Scanning

    private static func skipLineComment(_ units: [UInt16], from start: Int) -> Int {
        var index = start + 2
        while index < units.count, units[index] != ascii("\n") { index += 1 }
        return index
    }

    /// PostgreSQL block comments nest.
    private static func skipBlockComment(_ units: [UInt16], from start: Int) -> Int {
        var depth = 1
        var index = start + 2
        while index < units.count, depth > 0 {
            let next = index + 1 < units.count ? units[index + 1] : nil
            if units[index] == ascii("/"), next == ascii("*") {
                depth += 1
                index += 2
            } else if units[index] == ascii("*"), next == ascii("/") {
                depth -= 1
                index += 2
            } else {
                index += 1
            }
        }
        return index
    }

    /// Returns the index just past the closing quote, or the end for an unterminated literal.
    /// A doubled quote is an escaped quote; `E''` strings also escape with a backslash.
    private static func skipQuoted(
        _ units: [UInt16], from start: Int, quote: UInt16, backslashEscapes: Bool
    ) -> Int {
        var index = start + 1
        while index < units.count {
            let unit = units[index]
            if backslashEscapes, unit == ascii("\\") {
                index += 2
                continue
            }
            if unit == quote {
                if index + 1 < units.count, units[index + 1] == quote {
                    index += 2
                    continue
                }
                return index + 1
            }
            index += 1
        }
        return units.count
    }

    /// For a `$` that opens a dollar quote (`$$` or `$tag$`), returns the index of the tag's
    /// closing `$`. Nil for positional parameters like `$1` and for `$` inside identifiers.
    private static func dollarTagEnd(_ units: [UInt16], from start: Int) -> Int? {
        if start > 0, isIdentifierUnit(units[start - 1]) { return nil }
        var index = start + 1
        guard index < units.count else { return nil }
        if units[index] == ascii("$") { return index }
        guard isIdentifierStart(units[index]) else { return nil }
        while index < units.count, isTagUnit(units[index]) { index += 1 }
        guard index < units.count, units[index] == ascii("$") else { return nil }
        return index
    }

    private static func skipDollarQuoted(_ units: [UInt16], openingFrom start: Int, tagEnd: Int) -> Int {
        let tag = Array(units[start...tagEnd])
        var index = tagEnd + 1
        while index + tag.count <= units.count {
            if units[index] == ascii("$"), Array(units[index..<(index + tag.count)]) == tag {
                return index + tag.count
            }
            index += 1
        }
        return units.count
    }

    // MARK: - Character classes

    private static func ascii(_ character: Character) -> UInt16 {
        UInt16(character.asciiValue!)
    }

    private static func isWhitespace(_ unit: UInt16) -> Bool {
        unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D || unit == 0x0C
    }

    private static func isIdentifierStart(_ unit: UInt16) -> Bool {
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A) || unit == 0x5F || unit >= 0x80
    }

    /// Dollar-quote tags follow identifier rules but cannot contain `$`.
    private static func isTagUnit(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39)
    }

    private static func isIdentifierUnit(_ unit: UInt16) -> Bool {
        isIdentifierStart(unit) || (unit >= 0x30 && unit <= 0x39) || unit == ascii("$")
    }
}
