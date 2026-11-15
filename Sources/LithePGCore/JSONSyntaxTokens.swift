import Foundation

/// Classifies JSON text into colorable tokens for the cell editor.
///
/// It is lenient on purpose: half-typed JSON still gets colored as far as it makes sense, an
/// unterminated string runs to the end and unknown characters are skipped. Ranges are UTF-16,
/// matching `NSTextView`.
public enum JSONSyntaxTokens {
    public enum Kind: Equatable, Sendable {
        case key
        case string
        case number
        case literal
        case punctuation
    }

    public struct Token: Equatable, Sendable {
        public let range: NSRange
        public let kind: Kind
    }

    /// True when the text should be colored as JSON: it starts with an object or array.
    public static func looksLikeJSON(_ text: String) -> Bool {
        guard let first = text.first(where: { !$0.isWhitespace }) else { return false }
        return first == "{" || first == "["
    }

    public static func tokens(in text: String) -> [Token] {
        let units = Array(text.utf16)
        var tokens: [Token] = []
        var index = 0

        func isWhitespace(_ unit: UInt16) -> Bool { unit == 0x20 || unit == 0x09 || unit == 0x0A || unit == 0x0D }
        func isWordUnit(_ unit: UInt16) -> Bool {
            (0x30...0x39).contains(unit) || (0x41...0x5A).contains(unit) || (0x61...0x7A).contains(unit)
                || unit == 0x2B || unit == 0x2D || unit == 0x2E
        }

        while index < units.count {
            let unit = units[index]
            switch unit {
            case 0x22:  // "
                let start = index
                index += 1
                while index < units.count {
                    if units[index] == 0x5C { index += 2; continue }  // backslash escape
                    if units[index] == 0x22 { index += 1; break }
                    index += 1
                }
                index = min(index, units.count)
                // A string followed by `:` is an object key.
                var lookahead = index
                while lookahead < units.count, isWhitespace(units[lookahead]) { lookahead += 1 }
                let isKey = lookahead < units.count && units[lookahead] == 0x3A
                tokens.append(Token(range: NSRange(location: start, length: index - start), kind: isKey ? .key : .string))
            case 0x7B, 0x7D, 0x5B, 0x5D, 0x3A, 0x2C:  // { } [ ] : ,
                tokens.append(Token(range: NSRange(location: index, length: 1), kind: .punctuation))
                index += 1
            default:
                guard isWordUnit(unit) else {
                    index += 1
                    continue
                }
                let start = index
                while index < units.count, isWordUnit(units[index]) { index += 1 }
                let word = String(utf16CodeUnits: Array(units[start..<index]), count: index - start)
                let range = NSRange(location: start, length: index - start)
                if ["true", "false", "null"].contains(word) {
                    tokens.append(Token(range: range, kind: .literal))
                } else if word.first.map({ $0 == "-" || $0.isNumber }) == true {
                    tokens.append(Token(range: range, kind: .number))
                }
            }
        }
        return tokens
    }
}
