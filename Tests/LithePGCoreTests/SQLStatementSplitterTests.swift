import Foundation
import Testing
@testable import LithePGCore

@Suite("SQL statement splitter")
struct SQLStatementSplitterTests {
    private func texts(_ sql: String) -> [String] {
        SQLStatementSplitter.statements(in: sql).map(\.text)
    }

    private func statement(_ sql: String, caretBefore marker: String) -> String? {
        let caret = (sql as NSString).range(of: marker).location
        let cleaned = sql.replacingOccurrences(of: marker, with: "")
        return SQLStatementSplitter.statement(at: caret, in: cleaned)?.text
    }

    @Test("splits on semicolons and keeps each terminator")
    func splitsOnSemicolons() {
        #expect(texts("SELECT 1;\nSELECT 2;") == ["SELECT 1;", "SELECT 2;"])
        #expect(texts("SELECT 1; SELECT 2") == ["SELECT 1;", "SELECT 2"])
        #expect(texts("  SELECT 1  ") == ["SELECT 1"])
    }

    @Test("ignores semicolons inside strings, identifiers and comments")
    func ignoresQuotedSemicolons() {
        #expect(texts("SELECT 'a;b', \"c;d\";\nSELECT 2;") == ["SELECT 'a;b', \"c;d\";", "SELECT 2;"])
        #expect(texts("SELECT 'it''s; fine'; SELECT 2") == ["SELECT 'it''s; fine';", "SELECT 2"])
        #expect(texts("SELECT E'a\\'; b'; SELECT 2") == ["SELECT E'a\\'; b';", "SELECT 2"])
        #expect(texts("SELECT 1 -- note; here\n, 2; SELECT 3") == ["SELECT 1 -- note; here\n, 2;", "SELECT 3"])
        #expect(texts("SELECT /* a; /* nested; */ b; */ 1; SELECT 2") == ["SELECT /* a; /* nested; */ b; */ 1;", "SELECT 2"])
    }

    @Test("ignores semicolons inside dollar-quoted bodies")
    func ignoresDollarQuotedSemicolons() {
        let function = """
        CREATE FUNCTION f() RETURNS int AS $body$
        BEGIN RETURN 1; END;
        $body$ LANGUAGE plpgsql;
        SELECT f();
        """
        let parts = texts(function)
        #expect(parts.count == 2)
        #expect(parts[1] == "SELECT f();")
        #expect(texts("SELECT $$a;b$$; SELECT $1") == ["SELECT $$a;b$$;", "SELECT $1"])
    }

    @Test("drops segments that hold only whitespace or comments")
    func dropsEmptySegments() {
        #expect(texts(";;\n-- only a comment\n") == [])
        #expect(texts("SELECT 1;\n-- trailing note\n") == ["SELECT 1;"])
    }

    @Test("picks the statement under the caret")
    func picksStatementUnderCaret() {
        let sql = "SELECT 1;\nSELECT 2;\n\nSELECT 3;"
        #expect(statement("SELECT 1;\n|SELECT 2;\n\nSELECT 3;", caretBefore: "|") == "SELECT 2;")
        #expect(statement("SEL|ECT 1;\nSELECT 2;", caretBefore: "|") == "SELECT 1;")
        // Right after a terminator, and on the blank lines that follow, still means that statement.
        #expect(statement("SELECT 1;|\nSELECT 2;", caretBefore: "|") == "SELECT 1;")
        #expect(statement("SELECT 1;\nSELECT 2;\n|\nSELECT 3;", caretBefore: "|") == "SELECT 2;")
        #expect(SQLStatementSplitter.statement(at: (sql as NSString).length, in: sql)?.text == "SELECT 3;")
        #expect(statement("|\n\nSELECT 1;", caretBefore: "|") == "SELECT 1;")
        #expect(SQLStatementSplitter.statement(at: 0, in: "   ") == nil)
    }

    @Test("offsets are UTF-16 so they line up with the text view")
    func offsetsAreUTF16() {
        let sql = "SELECT 'José 🐘';\nSELECT 2;"
        let second = SQLStatementSplitter.statements(in: sql)[1]
        #expect((sql as NSString).substring(with: NSRange(second.range)) == "SELECT 2;")
        #expect(statement("SELECT 'José 🐘';\n|SELECT 2;", caretBefore: "|") == "SELECT 2;")
    }
}
