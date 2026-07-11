import Foundation

/// Pure graph derived from `DatabaseSchema`: one node per relation, one edge
/// per foreign key. Read-only metadata; no SQL, no credentials, no network.
public struct SchemaGraph: Sendable, Equatable {
  public struct Node: Sendable, Equatable, Identifiable {
    public let id: String
    public let schema: String
    public let name: String
    public let kind: DatabaseSchema.Relation.Kind
    public let columnCount: Int
  }

  public struct Edge: Sendable, Equatable, Identifiable {
    public let id: String
    public let sourceID: String
    public let targetID: String
    /// Column mapping, child side first: `customer_id → id`.
    public let label: String
    public let isSelfReference: Bool
  }

  public let nodes: [Node]
  public let edges: [Edge]

  public static func build(from schema: DatabaseSchema) -> SchemaGraph {
    let nodes = schema.schemas.flatMap { namespace in
      namespace.relations.map { relation in
        Node(
          id: relation.id,
          schema: relation.schema,
          name: relation.name,
          kind: relation.kind,
          columnCount: relation.columns.count
        )
      }
    }
    let nodeIDs = Set(nodes.map(\.id))

    // Foreign keys can reference relations hidden from introspection (filtered
    // system schemas, missing privileges); drop those instead of drawing
    // edges into nothing.
    let edges = schema.foreignKeys.compactMap { fk -> Edge? in
      let sourceID = "\(fk.childSchema).\(fk.childRelation)"
      let targetID = "\(fk.parentSchema).\(fk.parentRelation)"
      guard nodeIDs.contains(sourceID), nodeIDs.contains(targetID) else { return nil }
      return Edge(
        id: fk.id,
        sourceID: sourceID,
        targetID: targetID,
        label: "\(fk.childColumns.joined(separator: ", ")) → \(fk.parentColumns.joined(separator: ", "))",
        isSelfReference: sourceID == targetID
      )
    }

    return SchemaGraph(nodes: nodes, edges: edges)
  }
}
