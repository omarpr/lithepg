import Foundation
import PostgresNIO

public enum ErrorRedaction {
    /// Extracts a minimal, actionable PostgreSQL diagnostic when available, then scrubs credentials.
    public static func redactCredentials(in error: Error) -> String {
        let raw: String
        if let postgresError = error as? PSQLError {
            raw = postgresMessage(postgresError)
        } else {
            raw = String(describing: error)
        }
        return redactCredentials(in: raw)
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

    static func postgresServerMessage(
        message: String?,
        sqlState: String?,
        position: String?
    ) -> String {
        var parts = [message?.nilIfBlank ?? "PostgreSQL rejected the request."]
        if let sqlState = sqlState?.nilIfBlank {
            parts.append("SQLSTATE \(sqlState)")
        }
        if let position = position?.nilIfBlank {
            parts.append("Position \(position)")
        }
        return parts.joined(separator: " · ")
    }

    /// PSQLError intentionally hides its server fields from `description`. Only expose the
    /// primary message, SQLSTATE and cursor position; detail/context fields can contain row data.
    private static func postgresMessage(_ error: PSQLError) -> String {
        if let serverInfo = error.serverInfo {
            return postgresServerMessage(
                message: serverInfo[.message],
                sqlState: serverInfo[.sqlState],
                position: serverInfo[.position]
            )
        }

        return "PostgreSQL error (\(error.code))."
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
