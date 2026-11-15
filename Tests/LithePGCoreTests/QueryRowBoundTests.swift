import Testing
@testable import LithePGCore

@Suite("Query row bound")
struct QueryRowBoundTests {
    @Test("wraps a plain query with an outer limit", arguments: [
        "SELECT * FROM orders", "select id from orders order by id desc;",
        "WITH recent AS (SELECT * FROM orders) SELECT * FROM recent", "TABLE orders", "VALUES (1), (2)",
        "-- note\nSELECT 1 -- trailing comment",
    ])
    func wrapsQueries(sql: String) throws {
        let bounded = try #require(QueryRowBound.bounded(sql, limit: 10_001))
        #expect(bounded.sql.hasPrefix("SELECT * FROM (\n"))
        #expect(bounded.sql.hasSuffix("\n) AS lithepg_result LIMIT 10001"))
        #expect(!bounded.sql.contains(";"))
    }

    @Test("runs anything that could change inside a subquery as written", arguments: [
        "INSERT INTO orders VALUES (1)", "UPDATE orders SET total = 0", "DELETE FROM orders",
        "WITH gone AS (DELETE FROM orders RETURNING *) SELECT * FROM gone",
        "SELECT * INTO archive FROM orders", "SELECT * FROM orders FOR UPDATE",
        "SELECT * FROM orders FOR SHARE SKIP LOCKED", "SELECT 1; SELECT 2", "EXPLAIN SELECT 1",
        "SHOW search_path", "", "   ", "-- only a comment",
    ])
    func leavesOthersAlone(sql: String) {
        #expect(QueryRowBound.bounded(sql, limit: 10_001) == nil)
    }

    @Test("a word only inside a string or quoted identifier does not block bounding")
    func ignoresQuotedWords() {
        #expect(QueryRowBound.bounded(#"SELECT 'delete me', "update" FROM orders"#, limit: 5) != nil)
    }

    @Test("maps a server error position back onto the user's text")
    func mapsPositions() throws {
        let sql = "\n  SELEC 1"
        let bounded = try #require(QueryRowBound.bounded("\n  SELECT bad syntax here", limit: 5))
        // The body starts at character 4 of the user's text and at 17 of the sent SQL.
        #expect(QueryRowBound.userPosition("17", shift: bounded.positionShift, in: sql) == "4")
        // Positions inside the wrapper are dropped rather than reported wrongly.
        #expect(QueryRowBound.userPosition("2", shift: bounded.positionShift, in: sql) == nil)
        #expect(QueryRowBound.userPosition("not a number", shift: 0, in: sql) == nil)
    }
}
