import Foundation

public enum ErrorRedaction {
    /// Stringifies the error via `String(describing:)`, then scrubs `password` substrings.
    public static func redactCredentials(in error: Error) -> String {
        redactCredentials(in: String(describing: error))
    }

    /// Scrubs `password` occurrences of the form `password: "x"`, `password=x`, `Password = x`, etc.
    public static func redactCredentials(in raw: String) -> String {
        let passwordPattern = #"(password\s*[:=]\s*)("[^"]*"|[^",\s)]+)"#
        let postgresURLPattern = #"((?:postgres|postgresql)://[^:\s/@]+:)([^@\s]+)(@)"#
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        var output = raw
        if let regex = try? NSRegularExpression(pattern: passwordPattern, options: .caseInsensitive) {
            output = regex.stringByReplacingMatches(in: output, range: range, withTemplate: "$1[redacted]")
        }
        let outputRange = NSRange(output.startIndex..<output.endIndex, in: output)
        if let regex = try? NSRegularExpression(pattern: postgresURLPattern, options: .caseInsensitive) {
            output = regex.stringByReplacingMatches(in: output, range: outputRange, withTemplate: "$1[redacted]$3")
        }
        return output
    }
}
