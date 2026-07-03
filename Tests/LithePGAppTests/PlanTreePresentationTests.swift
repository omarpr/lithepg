import CoreGraphics
import Testing
@testable import LithePGAppUI
import LithePGCore

@Suite("PlanTree presentation")
struct PlanTreePresentationTests {
    // A plain `EXPLAIN (FORMAT JSON)` result: single Seq Scan, no ANALYZE fields.
    private static let plainSeqScanJSON = """
    [
      {
        "Plan": {
          "Node Type": "Seq Scan",
          "Relation Name": "users",
          "Alias": "users",
          "Startup Cost": 0.00,
          "Total Cost": 21.00,
          "Plan Rows": 1000,
          "Plan Width": 244
        }
      }
    ]
    """

    // A nested `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` result: hash join over two
    // scans, with actual-time fields and planning/execution times.
    private static let nestedAnalyzeJSON = """
    [
      {
        "Plan": {
          "Node Type": "Hash Join",
          "Startup Cost": 1.50,
          "Total Cost": 45.20,
          "Plan Rows": 200,
          "Plan Width": 40,
          "Actual Startup Time": 0.123,
          "Actual Total Time": 2.456,
          "Actual Rows": 180,
          "Actual Loops": 1,
          "Plans": [
            {
              "Node Type": "Seq Scan",
              "Relation Name": "orders",
              "Alias": "o",
              "Startup Cost": 0.00,
              "Total Cost": 30.00,
              "Plan Rows": 500,
              "Plan Width": 20,
              "Actual Startup Time": 0.010,
              "Actual Total Time": 1.000,
              "Actual Rows": 500,
              "Actual Loops": 1
            },
            {
              "Node Type": "Hash",
              "Startup Cost": 10.00,
              "Total Cost": 10.00,
              "Plan Rows": 200,
              "Plan Width": 20,
              "Plans": [
                {
                  "Node Type": "Seq Scan",
                  "Relation Name": "customers",
                  "Alias": "c",
                  "Startup Cost": 0.00,
                  "Total Cost": 10.00,
                  "Plan Rows": 200,
                  "Plan Width": 20
                }
              ]
            }
          ]
        },
        "Planning Time": 0.345,
        "Execution Time": 3.210
      }
    ]
    """

    @Test("node label combines node type and relation name")
    func nodeLabel() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        let rows = plan.displayRows

        // Root has no relation; scans carry their relation names.
        #expect(PlanTreePresentation.nodeLabel(for: rows[0]) == "Hash Join")
        #expect(PlanTreePresentation.nodeLabel(for: rows[1]) == "Seq Scan on orders")
        #expect(PlanTreePresentation.nodeLabel(for: rows[3]) == "Seq Scan on customers")
    }

    @Test("cost detail formats cost bounds and estimated rows, nil without cost")
    func costDetail() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        let rows = plan.displayRows

        #expect(PlanTreePresentation.costDetail(for: rows[0]) == "cost=1.50..45.20 · rows≈200")
        #expect(PlanTreePresentation.costDetail(for: rows[1]) == "cost=0.00..30.00 · rows≈500")

        // A node without cost bounds has no cost detail.
        let noCostJSON = """
        [ { "Plan": { "Node Type": "Result" } } ]
        """
        let noCost = try QueryPlan.parse(explainJSON: noCostJSON)
        #expect(PlanTreePresentation.costDetail(for: noCost.displayRows[0]) == nil)
    }

    @Test("cost share renders a rounded percentage, nil when unknown")
    func costShare() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        let rows = plan.displayRows

        #expect(PlanTreePresentation.costShare(for: rows[0]) == "100%")
        // 30.00 / 45.20 * 100 = 66.37... rounds to 66%.
        #expect(PlanTreePresentation.costShare(for: rows[1]) == "66%")

        let noCostJSON = """
        [ { "Plan": { "Node Type": "Result" } } ]
        """
        let noCost = try QueryPlan.parse(explainJSON: noCostJSON)
        #expect(PlanTreePresentation.costShare(for: noCost.displayRows[0]) == nil)
    }

    @Test("timing shows ANALYZE actual time and rows, nil without ANALYZE")
    func timing() throws {
        let analyzed = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        #expect(PlanTreePresentation.timing(for: analyzed.displayRows[0]) == "actual 2.456 ms · 180 rows")
        #expect(PlanTreePresentation.timing(for: analyzed.displayRows[1]) == "actual 1.000 ms · 500 rows")

        // A plain (non-ANALYZE) plan has no actual timing.
        let plain = try QueryPlan.parse(explainJSON: Self.plainSeqScanJSON)
        #expect(PlanTreePresentation.timing(for: plain.displayRows[0]) == nil)
    }

    @Test("indentation scales with depth")
    func indentation() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        let rows = plan.displayRows

        #expect(PlanTreePresentation.indent(for: rows[0]) == 0)
        #expect(PlanTreePresentation.indent(for: rows[1]) == PlanTreePresentation.indentStep)
        #expect(PlanTreePresentation.indent(for: rows[3]) == PlanTreePresentation.indentStep * 2)
    }

    @Test("accessibility label describes node, cost share, and costliest flag")
    func accessibilityLabel() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        let rows = plan.displayRows

        #expect(
            PlanTreePresentation.accessibilityLabel(for: rows[0])
                == "Hash Join, 100% of total cost, most expensive node"
        )
        #expect(
            PlanTreePresentation.accessibilityLabel(for: rows[1])
                == "Seq Scan on orders, 66% of total cost"
        )
    }

    @Test("plan summary reports node count and execution time when analyzed")
    func summary() throws {
        let analyzed = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        #expect(PlanTreePresentation.summary(for: analyzed) == "4 nodes · Execution 3.210 ms")

        let plain = try QueryPlan.parse(explainJSON: Self.plainSeqScanJSON)
        #expect(PlanTreePresentation.summary(for: plain) == "1 node")
    }

    @Test("presentation output never exposes connection secrets")
    func excludesSecrets() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        for row in plan.displayRows {
            let fragments = [
                PlanTreePresentation.nodeLabel(for: row),
                PlanTreePresentation.costDetail(for: row) ?? "",
                PlanTreePresentation.costShare(for: row) ?? "",
                PlanTreePresentation.timing(for: row) ?? "",
                PlanTreePresentation.accessibilityLabel(for: row),
            ]
            for fragment in fragments {
                #expect(!fragment.contains("@"))
                #expect(!fragment.lowercased().contains("password"))
                #expect(!fragment.contains("://"))
            }
        }
    }
}
