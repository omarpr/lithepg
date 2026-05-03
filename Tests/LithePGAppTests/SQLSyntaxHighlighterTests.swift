import Foundation
import Testing
@testable import LithePGApp

@Suite("SQLSyntaxHighlighter")
struct SQLSyntaxHighlighterTests {
    @Test("finds whole-word SQL keywords case-insensitively")
    func findsWholeWordKeywords() {
        let sql = "SELECT selection FROM users WHERE note = 'from' ORDER BY created_at DESC LIMIT 10"
        let tokens = SQLSyntaxHighlighter.keywordRanges(in: sql).compactMap { range -> String? in
            guard let stringRange = Range(range, in: sql) else { return nil }
            return String(sql[stringRange])
        }

        #expect(tokens == ["SELECT", "FROM", "WHERE", "ORDER", "BY", "DESC", "LIMIT"])
    }
}
