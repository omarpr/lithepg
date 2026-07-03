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
