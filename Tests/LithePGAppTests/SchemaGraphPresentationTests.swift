import Testing
import LithePGCore

@testable import LithePGAppUI

@Suite("SchemaGraphPresentation")
struct SchemaGraphPresentationTests {
  private func column(
    _ name: String, type: String = "int4", pk: Bool = false, position: Int = 1
  ) -> DatabaseSchema.Column {
    .init(name: name, typeName: type, isNullable: false, ordinalPosition: position, isPrimaryKey: pk)
  }

  private var schema: DatabaseSchema {
    DatabaseSchema(
      schemas: [
        .init(name: "public", relations: [
          .init(schema: "public", name: "customers", kind: .table, columns: [
            column("id", pk: true), column("name", type: "text", position: 2),
          ]),
          .init(schema: "public", name: "orders", kind: .table, columns: [
            column("id", pk: true), column("customer_id", position: 2),
          ]),
          .init(schema: "public", name: "stats", kind: .view, columns: [column("total")]),
        ])
      ],
      foreignKeys: [
        .init(
          name: "orders_customer_fk",
          childSchema: "public", childRelation: "orders", childColumns: ["customer_id"],
          parentSchema: "public", parentRelation: "customers", parentColumns: ["id"]
        )
      ]
    )
  }

  @Test("selection highlights the node, its neighbors and shared edges")
  func selectionHighlighting() {
    let graph = SchemaGraph.build(from: schema)
    let layout = ForceLayout(graph: graph)

    let nodes = SchemaGraphPresentation.nodes(
      graph: graph, layout: layout, selectedID: "public.orders")
    let selected = nodes.first { $0.id == "public.orders" }
    let neighbor = nodes.first { $0.id == "public.customers" }
    let bystander = nodes.first { $0.id == "public.stats" }
    #expect(selected?.isSelected == true)
    #expect(neighbor?.isNeighbor == true)
    #expect(bystander?.isNeighbor == false)

    let edges = SchemaGraphPresentation.edges(
      graph: graph, layout: layout, selectedID: "public.orders")
    #expect(edges.count == 1)
    #expect(edges[0].isHighlighted)
  }

  @Test("no selection means no highlights")
  func noSelectionNoHighlights() {
    let graph = SchemaGraph.build(from: schema)
    let layout = ForceLayout(graph: graph)
    let nodes = SchemaGraphPresentation.nodes(graph: graph, layout: layout, selectedID: nil)
    #expect(nodes.allSatisfy { !$0.isSelected && !$0.isNeighbor })
    let edges = SchemaGraphPresentation.edges(graph: graph, layout: layout, selectedID: nil)
    #expect(edges.allSatisfy { !$0.isHighlighted })
  }

  @Test("inspector rows carry types and PK/FK badges")
  func inspectorRows() {
    let graph = SchemaGraph.build(from: schema)
    let rows = SchemaGraphPresentation.inspectorRows(
      nodeID: "public.orders", schema: schema, graph: graph)
    #expect(rows.map(\.name) == ["id", "customer_id"])
    #expect(rows[0].typeName == "int4")
    #expect(rows[0].badges == ["PK"])
    #expect(rows[1].badges == ["FK"])
  }

  @Test("node radius grows with column count and stays clamped")
  func radiusScaling() {
    let small = SchemaGraphPresentation.radius(columnCount: 1)
    let medium = SchemaGraphPresentation.radius(columnCount: 20)
    let huge = SchemaGraphPresentation.radius(columnCount: 500)
    #expect(small < medium)
    #expect(medium <= huge)
    #expect(huge <= 34)
    #expect(small >= 12)
  }

  @Test("empty states explain empty schemas and missing foreign keys")
  func emptyStates() {
    let empty = SchemaGraph.build(from: DatabaseSchema(schemas: []))
    #expect(SchemaGraphPresentation.emptyStateMessage(for: empty) == "No tables in the current schema.")

    let noFK = SchemaGraph.build(from: DatabaseSchema(
      schemas: [.init(name: "public", relations: [
        .init(schema: "public", name: "lonely", kind: .table, columns: [column("id")])
      ])]
    ))
    #expect(SchemaGraphPresentation.emptyStateMessage(for: noFK)
      == "No foreign keys detected. Tables are shown unconnected.")

    let connected = SchemaGraph.build(from: schema)
    #expect(SchemaGraphPresentation.emptyStateMessage(for: connected) == nil)
  }

  @Test("accessibility labels name the table, kind and relationships")
  func accessibilityLabels() {
    let graph = SchemaGraph.build(from: schema)
    let layout = ForceLayout(graph: graph)
    let nodes = SchemaGraphPresentation.nodes(graph: graph, layout: layout, selectedID: nil)
    let orders = nodes.first { $0.id == "public.orders" }
    #expect(orders?.accessibilityLabel == "orders, table in public, 2 columns, 1 relationship")
    let stats = nodes.first { $0.id == "public.stats" }
    #expect(stats?.accessibilityLabel == "stats, view in public, 1 column, no relationships")
  }

  @Test("presentation output never contains credential-shaped content")
  func privacyReceipt() {
    let graph = SchemaGraph.build(from: schema)
    let layout = ForceLayout(graph: graph)
    let nodes = SchemaGraphPresentation.nodes(graph: graph, layout: layout, selectedID: nil)
    let edges = SchemaGraphPresentation.edges(graph: graph, layout: layout, selectedID: nil)
    let rendered = (nodes.map(\.title) + nodes.map(\.accessibilityLabel) + edges.map(\.label))
      .joined(separator: " ")
    #expect(!rendered.contains("://"))
    #expect(!rendered.contains("@"))
    #expect(!rendered.lowercased().contains("password"))
  }
}
