import Testing
@testable import LithePGCore

@Suite("QueryPlan")
struct QueryPlanTests {
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

    @Test("parses a plain single-node EXPLAIN plan")
    func parsesPlainPlan() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.plainSeqScanJSON)

        #expect(plan.root.nodeType == "Seq Scan")
        #expect(plan.root.relationName == "users")
        #expect(plan.root.alias == "users")
        #expect(plan.root.startupCost == 0.00)
        #expect(plan.root.totalCost == 21.00)
        #expect(plan.root.planRows == 1000)
        #expect(plan.root.planWidth == 244)
        #expect(plan.root.actualTotalTime == nil)
        #expect(plan.root.actualRows == nil)
        #expect(plan.root.children.isEmpty)
        #expect(plan.planningTime == nil)
        #expect(plan.executionTime == nil)
        #expect(plan.analyzed == false)
    }

    @Test("parses a nested ANALYZE plan tree with timing")
    func parsesNestedAnalyzePlan() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)

        #expect(plan.root.nodeType == "Hash Join")
        #expect(plan.root.actualTotalTime == 2.456)
        #expect(plan.root.actualRows == 180)
        #expect(plan.root.actualLoops == 1)
        #expect(plan.root.children.count == 2)

        let scan = plan.root.children[0]
        #expect(scan.nodeType == "Seq Scan")
        #expect(scan.relationName == "orders")
        #expect(scan.alias == "o")
        #expect(scan.children.isEmpty)

        let hash = plan.root.children[1]
        #expect(hash.nodeType == "Hash")
        #expect(hash.children.count == 1)
        #expect(hash.children[0].nodeType == "Seq Scan")
        #expect(hash.children[0].relationName == "customers")

        #expect(plan.planningTime == 0.345)
        #expect(plan.executionTime == 3.210)
        #expect(plan.analyzed == true)
        #expect(plan.nodeCount == 4)
    }

    @Test("renders an indented text outline of the plan tree")
    func rendersOutlinePlain() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.plainSeqScanJSON)

        #expect(plan.outline == "Seq Scan on users (cost=0.00..21.00 rows=1000)")
    }

    @Test("renders a nested indented text outline")
    func rendersOutlineNested() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)

        let expected = [
            "Hash Join (cost=1.50..45.20 rows=200)",
            "  -> Seq Scan on orders (cost=0.00..30.00 rows=500)",
            "  -> Hash (cost=10.00..10.00 rows=200)",
            "    -> Seq Scan on customers (cost=0.00..10.00 rows=200)",
        ].joined(separator: "\n")

        #expect(plan.outline == expected)
    }

    @Test("identifies the most expensive node by total cost")
    func findsCostliestNode() throws {
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)

        let costliest = plan.costliestNode
        #expect(costliest.nodeType == "Hash Join")
        #expect(costliest.totalCost == 45.20)
    }

    @Test("throws invalidJSON for malformed input")
    func throwsOnMalformedJSON() {
        #expect(throws: QueryPlan.ParseError.invalidJSON) {
            try QueryPlan.parse(explainJSON: "not json at all")
        }
    }

    @Test("throws missingPlan when no Plan node is present")
    func throwsOnMissingPlan() {
        #expect(throws: QueryPlan.ParseError.missingPlan) {
            try QueryPlan.parse(explainJSON: "[]")
        }
        #expect(throws: QueryPlan.ParseError.missingPlan) {
            try QueryPlan.parse(explainJSON: "[{\"NotAPlan\": 1}]")
        }
    }

    @Test("outline output never contains password-like connection secrets")
    func outlineExcludesSecrets() throws {
        // The parser only sees plan JSON, never a connection URL, but guard the
        // invariant that its rendered output is derived solely from plan fields.
        let plan = try QueryPlan.parse(explainJSON: Self.nestedAnalyzeJSON)
        #expect(!plan.outline.contains("@"))
        #expect(!plan.outline.lowercased().contains("password"))
    }
}
