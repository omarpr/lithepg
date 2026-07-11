import LithePGCore
import SwiftUI

/// Indented plan tree for the last EXPLAIN run, built on the headless
/// `PlanTreePresentation` helpers. Read-only over already-parsed plan fields.
struct PlanTreeView: View {
  let plan: QueryPlan
  let isAnalyze: Bool

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        Label("Query plan", systemImage: "list.bullet.indent")
          .font(.headline)
        if isAnalyze {
          Text("ANALYZE")
            .font(.caption.bold())
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.18), in: Capsule())
            .foregroundStyle(.orange)
            .help("The query was executed to capture actual timings")
        }
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
      }
      .padding(12)
      Divider()
      List(plan.displayRows) { row in
        HStack(alignment: .firstTextBaseline, spacing: 8) {
          VStack(alignment: .leading, spacing: 2) {
            Text(PlanTreePresentation.nodeLabel(for: row))
              .font(.callout.weight(row.isCostliest ? .semibold : .regular))
            HStack(spacing: 8) {
              if let cost = PlanTreePresentation.costDetail(for: row) {
                Text(cost)
              }
              if let timing = PlanTreePresentation.timing(for: row) {
                Text(timing)
                  .foregroundStyle(.orange)
              }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
          }
          Spacer()
          if let share = PlanTreePresentation.costShare(for: row) {
            Text(share)
              .font(.caption.bold().monospacedDigit())
              .padding(.horizontal, 7)
              .padding(.vertical, 3)
              .background(
                (row.isCostliest ? Color.red : Color.secondary).opacity(0.14), in: Capsule())
              .foregroundStyle(row.isCostliest ? .red : .secondary)
              .help(row.isCostliest ? "Costliest node in the plan" : "Share of total plan cost")
          }
        }
        .padding(.leading, PlanTreePresentation.indent(for: row))
        .accessibilityElement(children: .combine)
      }
      .listStyle(.plain)
      .accessibilityIdentifier("plan-tree-list")
    }
    .frame(minWidth: 640, idealWidth: 760, minHeight: 420, idealHeight: 540)
  }
}
