import Foundation
import Testing
@testable import LithePGAppUI

@Suite("SQLSyntaxHighlighter")
struct SQLSyntaxHighlighterTests {
    @Test("finds whole-word SQL keywords case-insensitively")
    func findsWholeWordKeywords() {
        let sql = "SELECT selection FROM users WHERE note = 'from' ORDER BY created_at DESC LIMIT 10"
        let tokens = highlightedTokens(in: sql)

        #expect(tokens == ["SELECT", "FROM", "WHERE", "ORDER", "BY", "DESC", "LIMIT"])
    }

    @Test("ignores keywords in comments and quoted identifiers")
    func ignoresCommentsAndQuotedIdentifiers() {
        let sql = """
        -- SELECT ignored
        SELECT "from" FROM users /* WHERE ignored */ WHERE note = 'ORDER ignored'
        """
        let tokens = highlightedTokens(in: sql)

        #expect(tokens == ["SELECT", "FROM", "WHERE"])
    }

    private func highlightedTokens(in sql: String) -> [String] {
        SQLSyntaxHighlighter.keywordRanges(in: sql).compactMap { range -> String? in
            guard let stringRange = Range(range, in: sql) else { return nil }
            return String(sql[stringRange])
        }
    }
}
