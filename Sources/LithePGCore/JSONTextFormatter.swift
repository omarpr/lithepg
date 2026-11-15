import Foundation

/// Re-indents or compacts JSON text for the cell editor without re-encoding any value.
///
/// Only whitespace between tokens changes. Strings, numbers and key order are copied exactly,
/// so a jsonb `numeric` such as `12345678901234567890.5` or an escaped `"é"` survives,
/// which a round trip through `JSONSerialization` would not guarantee.
public enum JSONTextFormatter {
    /// True when `text` is a JSON object or array, the shapes worth formatting.
    public static func isFormattable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first, first == "{" || first == "[" else { return false }
        return (try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))) != nil
    }

    /// The value indented two spaces per level, or nil when it is not a JSON object or array.
    public static func prettyPrinted(_ text: String) -> String? {
        guard isFormattable(text) else { return nil }
        return reformat(text, pretty: true)
    }

    /// The value with no whitespace between tokens, or nil when it is not a JSON object or array.
    public static func compacted(_ text: String) -> String? {
        guard isFormattable(text) else { return nil }
        return reformat(text, pretty: false)
    }

    private static func reformat(_ text: String, pretty: Bool) -> String {
        let characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        var output = ""
        var depth = 0
        var index = 0

        func newline() {
            guard pretty else { return }
            output += "\n" + String(repeating: "  ", count: depth)
        }
        func nextSignificant(after position: Int) -> Character? {
            var cursor = position + 1
            while cursor < characters.count, characters[cursor].isWhitespace { cursor += 1 }
            return cursor < characters.count ? characters[cursor] : nil
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\"":
                // Copy the string verbatim, escapes included.
                output.append(character)
                index += 1
                while index < characters.count {
                    let inner = characters[index]
                    output.append(inner)
                    index += 1
                    if inner == "\\", index < characters.count {
                        output.append(characters[index])
                        index += 1
                    } else if inner == "\"" {
                        break
                    }
                }
                continue
            case "{", "[":
                output.append(character)
                let closing: Character = character == "{" ? "}" : "]"
                if nextSignificant(after: index) == closing {
                    // Keep empty containers on one line: {} and [].
                    while characters[index] != closing { index += 1 }
                    output.append(closing)
                } else {
                    depth += 1
                    newline()
                }
            case "}", "]":
                depth -= 1
                newline()
                output.append(character)
            case ",":
                output.append(",")
                newline()
            case ":":
                output += pretty ? ": " : ":"
            default:
                if !character.isWhitespace { output.append(character) }
            }
            index += 1
        }
        return output
    }
}
