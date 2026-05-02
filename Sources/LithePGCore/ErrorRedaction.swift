import Foundation

public enum ErrorRedaction {
    /// Stringifies the error via `String(describing:)`, then scrubs `password` substrings.
    public static func redactCredentials(in error: Error) -> String {
        redactCredentials(in: String(describing: error))
    }

    /// Scrubs `password` occurrences of the form `password: "x"`, `password=x`, `Password = x`, etc.
    public static func redactCredentials(in raw: String) -> String {
        let pattern = #"(password\s*[:=]\s*)("[^"]*"|[^",\s)]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return raw
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        return regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "$1[redacted]")
    }
}
