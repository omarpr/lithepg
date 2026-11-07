import Foundation
import Testing

@testable import LithePGAppUI

@Suite("Current statement highlight")
struct CurrentStatementHighlighterTests {
    @Test("marks the caret's statement only when there are several")
    func highlightsOnlyWithSeveralStatements() {
        #expect(CurrentStatementHighlighter.highlightRange(in: "SELECT 1;", caret: 3) == nil)

        let sql = "SELECT 1;\nSELECT 2;"
        let range = CurrentStatementHighlighter.highlightRange(in: sql, caret: 12)
        #expect(range.map { (sql as NSString).substring(with: $0) } == "SELECT 2;")
    }
}
