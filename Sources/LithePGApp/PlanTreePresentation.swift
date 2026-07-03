import CoreGraphics
import Foundation
import LithePGCore

/// Headless presentation helpers for rendering a parsed `QueryPlan` as an
/// indented plan-tree list.
///
/// This is the view-model seam that a SwiftUI plan-tree view builds on, mirroring
/// how `ResultsTablePresentation` backs the results table. Every value here is
/// derived solely from already-parsed `QueryPlan` fields (node type, relation,
/// cost, row estimates, ANALYZE timing), so no connection string, credential, or
/// SQL text can appear in the output — enforced by a privacy-receipt test.
enum PlanTreePresentation {
    /// Horizontal indentation applied per depth level, in points.
    static let indentStep: CGFloat = 16

    /// Leading indentation for a row, scaling with its tree depth.
    static func indent(for row: QueryPlan.DisplayRow) -> CGFloat {
        indentStep * CGFloat(row.depth)
    }

    /// The primary label for a node: its type, plus the relation it reads when
    /// present (e.g. `Seq Scan on orders`).
    static func nodeLabel(for row: QueryPlan.DisplayRow) -> String {
        if let relation = row.node.relationName {
            return "\(row.node.nodeType) on \(relation)"
        }
        return row.node.nodeType
    }

    /// The planner cost detail (`cost=<startup>..<total> · rows≈<estimate>`), or
    /// `nil` when the node carries no cost bounds.
    static func costDetail(for row: QueryPlan.DisplayRow) -> String? {
        guard let startup = row.node.startupCost, let total = row.node.totalCost else {
            return nil
        }
        var text = String(format: "cost=%.2f..%.2f", startup, total)
        if let rows = row.node.planRows {
            text += " · rows≈\(rows)"
        }
        return text
    }

    /// The node's share of the root's total cost as a rounded whole-percent
    /// string (e.g. `66%`), or `nil` when the share is unknown.
    static func costShare(for row: QueryPlan.DisplayRow) -> String? {
        guard let percent = row.costPercent else { return nil }
        return "\(Int(percent.rounded()))%"
    }

    /// ANALYZE timing detail (`actual <ms> ms · <rows> rows`), or `nil` when the
    /// plan was not run with `ANALYZE`.
    static func timing(for row: QueryPlan.DisplayRow) -> String? {
        guard let actualTime = row.node.actualTotalTime else { return nil }
        var text = String(format: "actual %.3f ms", actualTime)
        if let rows = row.node.actualRows {
            text += " · \(rows) rows"
        }
        return text
    }

    /// A VoiceOver-friendly description combining the node label, its cost share,
    /// and whether it is the most expensive node.
    static func accessibilityLabel(for row: QueryPlan.DisplayRow) -> String {
        var parts = [nodeLabel(for: row)]
        if let share = costShare(for: row) {
            parts.append("\(share) of total cost")
        }
        if row.isCostliest {
            parts.append("most expensive node")
        }
        return parts.joined(separator: ", ")
    }

    /// A one-line summary of the whole plan: node count, plus execution time when
    /// the plan was run with `ANALYZE`.
    static func summary(for plan: QueryPlan) -> String {
        let count = plan.nodeCount
        var text = "\(count) node\(count == 1 ? "" : "s")"
        if plan.analyzed, let execution = plan.executionTime {
            text += String(format: " · Execution %.3f ms", execution)
        }
        return text
    }
}
