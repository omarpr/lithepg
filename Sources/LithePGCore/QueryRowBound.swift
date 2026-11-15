import Foundation
import PostgresNIO

/// Lets the server stop after the rows the app will keep.
///
/// The connector keeps at most `PostgresConnector.rowCap` rows, but PostgreSQL sends every row
/// a query produces, so `SELECT * FROM a_big_table` used to stream the whole table over the
/// network only to drop all but the first rows. A plain read-only query is wrapped as
/// `SELECT * FROM (query) LIMIT n` instead, which also lets the planner pick a fast-start plan.
/// The outer query keeps the inner column names, types, table origins and row order.
///
/// Anything that could behave differently inside a subquery runs exactly as written: several
/// statements, statements that are not queries, data-modifying `WITH` (PostgreSQL only allows
/// it at the top level), `SELECT INTO` and locking clauses.
public enum QueryRowBound {
    /// Words that mean the statement writes, creates a table or locks rows. A query that only
    /// mentions one of them (as an unquoted identifier, say) also runs unbounded, which is safe.
    static let unboundedWords: Set<String> = [
        "insert", "update", "delete", "merge", "into", "share", "nowait", "locked",
    ]

    public struct Bounded: Equatable, Sendable {
        /// The SQL to send.
        public let sql: String
        /// Add to a server error position in `sql` to get the position in the text the user ran.
        public let positionShift: Int
    }

    static let prefix = "SELECT * FROM (\n"

    /// The SQL to send so the server returns at most `limit` rows, or nil to run `sql` as is.
    public static func bounded(_ sql: String, limit: Int) -> Bounded? {
        guard limit > 0 else { return nil }
        let statements = SQLStatementSplitter.statements(in: sql)
        guard statements.count == 1, let statement = statements.first,
            ResultEditing.isQueryStatement(statement.text)
        else { return nil }
        let words = SQLLexer.tokens(Array(statement.text.utf16)).compactMap { token -> String? in
            if case .word(let word) = token { return word.lowercased() }
            return nil
        }
        guard !words.contains(where: unboundedWords.contains) else { return nil }
        let body = ResultEditing.trimmedStatement(statement.text)
        guard !body.isEmpty else { return nil }
        // PostgreSQL counts positions in characters. The body starts after the whitespace the
        // splitter trimmed, and after the prefix in the sent SQL.
        let leading = String(utf16CodeUnits: Array(sql.utf16.prefix(statement.range.lowerBound)),
                             count: statement.range.lowerBound).count
        // Newlines keep a trailing `--` comment in the body from swallowing the closing paren.
        return Bounded(
            sql: "\(prefix)\(body)\n) AS lithepg_result LIMIT \(limit)",
            positionShift: leading - prefix.count
        )
    }

    /// The user's position for a server error position in bounded SQL, or nil when the
    /// position falls in the wrapper rather than the user's text.
    public static func userPosition(_ serverPosition: String, shift: Int, in sql: String) -> String? {
        guard let position = Int(serverPosition.trimmingCharacters(in: .whitespaces)) else { return nil }
        let adjusted = position + shift
        guard adjusted >= 1, adjusted <= sql.count + 1 else { return nil }
        return String(adjusted)
    }
}

/// A server error from a query sent with `QueryRowBound`. It carries the original error and
/// the shift that maps the reported position back onto the SQL the user ran.
public struct BoundedQueryError: Error, @unchecked Sendable {
    public let underlying: PSQLError
    public let positionShift: Int
    public let sql: String
}
