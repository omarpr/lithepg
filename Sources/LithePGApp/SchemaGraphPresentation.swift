import Foundation
import LithePGCore

/// Headless mapping from `SchemaGraph` + `ForceLayout` + selection to drawable
/// primitives and inspector rows. Everything here derives from local schema
/// metadata; no connection URLs, credentials or row data can appear.
enum SchemaGraphPresentation {
  struct GraphNode: Equatable, Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let x: Double
    let y: Double
    let radius: Double
    let isView: Bool
    let isSelected: Bool
    let isNeighbor: Bool
    let accessibilityLabel: String
  }

  struct GraphEdge: Equatable, Identifiable {
    let id: String
    let sourceX: Double
    let sourceY: Double
    let targetX: Double
    let targetY: Double
    let label: String
    let isSelfReference: Bool
    let isHighlighted: Bool
  }

  struct InspectorRow: Equatable, Identifiable {
    var id: String { name }
    let name: String
    let typeName: String
    let badges: [String]
  }

  static func radius(columnCount: Int) -> Double {
    min(34, max(12, 12 + 3 * Double(columnCount).squareRoot()))
  }

  static func nodes(
    graph: SchemaGraph,
    layout: ForceLayout,
    selectedID: String?
  ) -> [GraphNode] {
    let neighborIDs = neighborIDs(of: selectedID, in: graph)
    return graph.nodes.compactMap { node in
      guard let position = layout.positions[node.id] else { return nil }
      let relationshipCount = graph.edges.count {
        $0.sourceID == node.id || $0.targetID == node.id
      }
      return GraphNode(
        id: node.id,
        title: node.name,
        subtitle: "\(node.columnCount) \(node.columnCount == 1 ? "column" : "columns")",
        x: position.x,
        y: position.y,
        radius: radius(columnCount: node.columnCount),
        isView: node.kind == .view,
        isSelected: node.id == selectedID,
        isNeighbor: neighborIDs.contains(node.id),
        accessibilityLabel: accessibilityLabel(for: node, relationshipCount: relationshipCount)
      )
    }
  }

  static func edges(
    graph: SchemaGraph,
    layout: ForceLayout,
    selectedID: String?
  ) -> [GraphEdge] {
    graph.edges.compactMap { edge in
      guard let source = layout.positions[edge.sourceID],
        let target = layout.positions[edge.targetID]
      else { return nil }
      let highlighted =
        selectedID != nil && (edge.sourceID == selectedID || edge.targetID == selectedID)
      return GraphEdge(
        id: edge.id,
        sourceX: source.x,
        sourceY: source.y,
        targetX: target.x,
        targetY: target.y,
        label: edge.label,
        isSelfReference: edge.isSelfReference,
        isHighlighted: highlighted
      )
    }
  }

  static func inspectorRows(
    nodeID: String,
    schema: DatabaseSchema,
    graph: SchemaGraph
  ) -> [InspectorRow] {
    let relation = schema.schemas
      .flatMap(\.relations)
      .first { $0.id == nodeID }
    guard let relation else { return [] }

    let fkColumns = Set(
      schema.foreignKeys
        .filter { "\($0.childSchema).\($0.childRelation)" == nodeID }
        .flatMap(\.childColumns)
    )

    return relation.columns.map { column in
      var badges: [String] = []
      if column.isPrimaryKey { badges.append("PK") }
      if fkColumns.contains(column.name) { badges.append("FK") }
      return InspectorRow(name: column.name, typeName: column.typeName, badges: badges)
    }
  }

  static func emptyStateMessage(for graph: SchemaGraph) -> String? {
    if graph.nodes.isEmpty { return "No tables in the current schema." }
    if graph.edges.isEmpty { return "No foreign keys detected. Tables are shown unconnected." }
    return nil
  }

  private static func neighborIDs(of selectedID: String?, in graph: SchemaGraph) -> Set<String> {
    guard let selectedID else { return [] }
    var neighbors: Set<String> = []
    for edge in graph.edges where !edge.isSelfReference {
      if edge.sourceID == selectedID { neighbors.insert(edge.targetID) }
      if edge.targetID == selectedID { neighbors.insert(edge.sourceID) }
    }
    return neighbors
  }

  private static func accessibilityLabel(
    for node: SchemaGraph.Node, relationshipCount: Int
  ) -> String {
    let kind = node.kind == .view ? "view" : "table"
    let columns = "\(node.columnCount) \(node.columnCount == 1 ? "column" : "columns")"
    let relationships: String
    switch relationshipCount {
    case 0: relationships = "no relationships"
    case 1: relationships = "1 relationship"
    default: relationships = "\(relationshipCount) relationships"
    }
    return "\(node.name), \(kind) in \(node.schema), \(columns), \(relationships)"
  }
}
