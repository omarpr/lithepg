import Foundation

/// A parsed Postgres `EXPLAIN (FORMAT JSON)` plan tree.
///
/// Parsing is a local, on-device operation: it only reads the plan JSON that the
/// user already fetched via `EXPLAIN` and never contacts the network, logs
/// credentials, or auto-runs SQL. The rendered `outline` is derived solely from
/// plan node fields (node type, relation, cost, row estimates), so no connection
/// string or password can appear in it.
public struct QueryPlan: Sendable, Equatable {
    /// A single node in the plan tree.
    public struct Node: Sendable, Equatable {
        public let nodeType: String
        public let relationName: String?
        public let alias: String?
        public let startupCost: Double?
        public let totalCost: Double?
        public let planRows: Int?
        public let planWidth: Int?
        public let actualStartupTime: Double?
        public let actualTotalTime: Double?
        public let actualRows: Int?
        public let actualLoops: Int?
        public let children: [Node]
    }

    /// Errors thrown while parsing an `EXPLAIN (FORMAT JSON)` payload.
    public enum ParseError: Error, Equatable {
        case invalidJSON
        case missingPlan
        case emptyResult
    }

    public let root: Node
    public let planningTime: Double?
    public let executionTime: Double?

    /// Whether the plan carries `ANALYZE` actual-time measurements.
    public var analyzed: Bool { root.actualTotalTime != nil }

    /// Total number of nodes in the plan tree.
    public var nodeCount: Int { Self.count(root) }

    // MARK: - Parsing

    /// Parse the JSON produced by `EXPLAIN (FORMAT JSON, ...)`.
    ///
    /// Postgres returns a single-element top-level array whose element is an
    /// object with a `"Plan"` key. `ANALYZE` runs add `"Planning Time"` and
    /// `"Execution Time"` siblings.
    public static func parse(explainJSON: String) throws -> QueryPlan {
        guard let data = explainJSON.data(using: .utf8) else {
            throw ParseError.invalidJSON
        }
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ParseError.invalidJSON
        }

        guard
            let array = parsed as? [Any],
            let first = array.first as? [String: Any],
            let planObject = first["Plan"] as? [String: Any]
        else {
            throw ParseError.missingPlan
        }

        let root = parseNode(planObject)
        return QueryPlan(
            root: root,
            planningTime: first["Planning Time"] as? Double,
            executionTime: first["Execution Time"] as? Double
        )
    }

    /// Build an `EXPLAIN (FORMAT JSON)` statement that wraps the user's SQL.
    ///
    /// This is a pure string transform: it trims surrounding whitespace and a
    /// single trailing semicolon so the wrapped statement stays one valid
    /// `EXPLAIN` command. When `analyze` is true it adds `ANALYZE, BUFFERS`,
    /// which actually executes the query — callers gate that on explicit intent.
    /// No connection URL or credential is ever part of the produced statement.
    public static func explainStatement(for sql: String, analyze: Bool = false) -> String {
        var trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(";") {
            trimmed.removeLast()
            trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let options = analyze ? "ANALYZE, BUFFERS, FORMAT JSON" : "FORMAT JSON"
        return "EXPLAIN (\(options)) \(trimmed)"
    }

    /// Parse a plan out of the `QueryResult` returned by running an
    /// `EXPLAIN (FORMAT JSON)` statement.
    ///
    /// Postgres returns the plan as JSON text in the first cell of the first
    /// row (column `QUERY PLAN`). This reads only that already-fetched cell —
    /// no network, no credentials, no SQL execution.
    public static func parse(explainResult result: QueryResult) throws -> QueryPlan {
        guard
            let firstRow = result.rows.first,
            case .text(let json)? = firstRow.cells.first
        else {
            throw ParseError.emptyResult
        }
        return try parse(explainJSON: json)
    }

    private static func parseNode(_ object: [String: Any]) -> Node {
        let childObjects = object["Plans"] as? [[String: Any]] ?? []
        let children = childObjects.map(parseNode)
        return Node(
            nodeType: object["Node Type"] as? String ?? "Unknown",
            relationName: object["Relation Name"] as? String,
            alias: object["Alias"] as? String,
            startupCost: object["Startup Cost"] as? Double,
            totalCost: object["Total Cost"] as? Double,
            planRows: object["Plan Rows"] as? Int,
            planWidth: object["Plan Width"] as? Int,
            actualStartupTime: object["Actual Startup Time"] as? Double,
            actualTotalTime: object["Actual Total Time"] as? Double,
            actualRows: object["Actual Rows"] as? Int,
            actualLoops: object["Actual Loops"] as? Int,
            children: children
        )
    }

    // MARK: - Derived views

    /// An indented text outline of the plan tree, one node per line. Child nodes
    /// are prefixed with `-> ` and indented two spaces per depth level.
    public var outline: String {
        var lines: [String] = []
        Self.appendOutline(root, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// The node with the highest `Total Cost` in the tree (ties resolve to the
    /// first node found in pre-order traversal). The root is used as a fallback
    /// when no node carries a cost.
    public var costliestNode: Node {
        var best = root
        Self.forEachNode(root) { node in
            if (node.totalCost ?? -1) > (best.totalCost ?? -1) {
                best = node
            }
        }
        return best
    }

    /// A single flattened row for rendering the plan as an indented list.
    ///
    /// Derived solely from plan node fields, so no connection string or password
    /// can appear in it. `id` is a stable pre-order index suitable for use as a
    /// SwiftUI `Identifiable` key; `depth` drives indentation; `costPercent` is
    /// the node's `Total Cost` as a percentage of the root's total cost (nil when
    /// the root carries no cost); `isCostliest` flags the single most expensive
    /// node (matching `costliestNode`).
    public struct DisplayRow: Sendable, Equatable, Identifiable {
        public let id: Int
        public let depth: Int
        public let node: Node
        public let costPercent: Double?
        public let isCostliest: Bool
    }

    /// The plan tree flattened into pre-order display rows.
    public var displayRows: [DisplayRow] {
        let costliest = costliestNode
        let rootTotal = root.totalCost
        var rows: [DisplayRow] = []
        var nextID = 0
        var costliestClaimed = false

        func visit(_ node: Node, depth: Int) {
            let percent: Double?
            if let rootTotal, rootTotal > 0, let total = node.totalCost {
                percent = total / rootTotal * 100
            } else {
                percent = nil
            }
            // Flag exactly one row as costliest: the first node (pre-order) whose
            // identity matches `costliestNode`.
            let isCostliest = !costliestClaimed && node == costliest
            if isCostliest {
                costliestClaimed = true
            }
            rows.append(
                DisplayRow(
                    id: nextID,
                    depth: depth,
                    node: node,
                    costPercent: percent,
                    isCostliest: isCostliest
                )
            )
            nextID += 1
            for child in node.children {
                visit(child, depth: depth + 1)
            }
        }

        visit(root, depth: 0)
        return rows
    }

    private static func appendOutline(_ node: Node, depth: Int, into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let arrow = depth == 0 ? "" : "-> "
        lines.append(indent + arrow + describe(node))
        for child in node.children {
            appendOutline(child, depth: depth + 1, into: &lines)
        }
    }

    private static func describe(_ node: Node) -> String {
        var text = node.nodeType
        if let relation = node.relationName {
            text += " on \(relation)"
        }
        if let startup = node.startupCost, let total = node.totalCost {
            text += String(format: " (cost=%.2f..%.2f", startup, total)
            if let rows = node.planRows {
                text += " rows=\(rows)"
            }
            text += ")"
        }
        return text
    }

    private static func count(_ node: Node) -> Int {
        1 + node.children.reduce(0) { $0 + count($1) }
    }

    private static func forEachNode(_ node: Node, _ body: (Node) -> Void) {
        body(node)
        for child in node.children {
            forEachNode(child, body)
        }
    }
}
