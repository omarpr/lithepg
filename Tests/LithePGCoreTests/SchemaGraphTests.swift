import Testing
@testable import LithePGCore

@Suite("SchemaGraph")
struct SchemaGraphTests {
  private func column(_ name: String, pk: Bool = false, position: Int = 1) -> DatabaseSchema.Column {
    .init(name: name, typeName: "int4", isNullable: false, ordinalPosition: position, isPrimaryKey: pk)
  }

  private var fixture: DatabaseSchema {
    DatabaseSchema(
      schemas: [
        .init(name: "public", relations: [
          .init(schema: "public", name: "customers", kind: .table, columns: [
            column("id", pk: true), column("name", position: 2),
          ]),
          .init(schema: "public", name: "orders", kind: .table, columns: [
            column("id", pk: true), column("customer_id", position: 2), column("note", position: 3),
          ]),
          .init(schema: "public", name: "order_totals", kind: .view, columns: [
            column("order_id"),
          ]),
        ]),
        .init(name: "audit", relations: [
          .init(schema: "audit", name: "events", kind: .table, columns: [
            column("id", pk: true), column("actor_id", position: 2),
          ]),
        ]),
      ],
      foreignKeys: [
        .init(
          name: "orders_customer_fk",
          childSchema: "public", childRelation: "orders", childColumns: ["customer_id"],
          parentSchema: "public", parentRelation: "customers", parentColumns: ["id"]
        ),
        .init(
          name: "events_actor_fk",
          childSchema: "audit", childRelation: "events", childColumns: ["actor_id"],
          parentSchema: "public", parentRelation: "customers", parentColumns: ["id"]
        ),
      ]
    )
  }

  @Test("builds one node per relation including views")
  func buildsNodesForAllRelations() {
    let graph = SchemaGraph.build(from: fixture)
    #expect(graph.nodes.count == 4)
    #expect(graph.nodes.map(\.id).sorted() == [
      "audit.events", "public.customers", "public.order_totals", "public.orders",
    ])
    let orders = graph.nodes.first { $0.id == "public.orders" }
    #expect(orders?.columnCount == 3)
    #expect(orders?.kind == .table)
    let view = graph.nodes.first { $0.id == "public.order_totals" }
    #expect(view?.kind == .view)
  }

  @Test("derives edges from foreign keys, child to parent, across schemas")
  func derivesEdgesFromForeignKeys() {
    let graph = SchemaGraph.build(from: fixture)
    #expect(graph.edges.count == 2)
    let cross = graph.edges.first { $0.id == "audit.events.events_actor_fk" }
    #expect(cross?.sourceID == "audit.events")
    #expect(cross?.targetID == "public.customers")
    #expect(cross?.label == "actor_id → id")
  }

  @Test("flags self-referencing foreign keys")
  func flagsSelfReferences() {
    let schema = DatabaseSchema(
      schemas: [
        .init(name: "public", relations: [
          .init(schema: "public", name: "employees", kind: .table, columns: [
            column("id", pk: true), column("manager_id", position: 2),
          ])
        ])
      ],
      foreignKeys: [
        .init(
          name: "employees_manager_fk",
          childSchema: "public", childRelation: "employees", childColumns: ["manager_id"],
          parentSchema: "public", parentRelation: "employees", parentColumns: ["id"]
        )
      ]
    )
    let graph = SchemaGraph.build(from: schema)
    #expect(graph.edges.count == 1)
    #expect(graph.edges[0].isSelfReference)
  }

  @Test("drops edges whose endpoints are not in the schema")
  func dropsDanglingEdges() {
    let schema = DatabaseSchema(
      schemas: [
        .init(name: "public", relations: [
          .init(schema: "public", name: "orders", kind: .table, columns: [column("id", pk: true)])
        ])
      ],
      foreignKeys: [
        .init(
          name: "orders_ghost_fk",
          childSchema: "public", childRelation: "orders", childColumns: ["ghost_id"],
          parentSchema: "public", parentRelation: "ghosts", parentColumns: ["id"]
        )
      ]
    )
    let graph = SchemaGraph.build(from: schema)
    #expect(graph.edges.isEmpty)
  }

  @Test("composite foreign keys label every column pair")
  func compositeKeysKeepAllColumns() {
    let schema = DatabaseSchema(
      schemas: [
        .init(name: "public", relations: [
          .init(schema: "public", name: "a", kind: .table, columns: [column("x"), column("y", position: 2)]),
          .init(schema: "public", name: "b", kind: .table, columns: [column("x"), column("y", position: 2)]),
        ])
      ],
      foreignKeys: [
        .init(
          name: "a_b_fk",
          childSchema: "public", childRelation: "a", childColumns: ["x", "y"],
          parentSchema: "public", parentRelation: "b", parentColumns: ["x", "y"]
        )
      ]
    )
    let graph = SchemaGraph.build(from: schema)
    #expect(graph.edges[0].label == "x, y → x, y")
  }

  @Test("empty schema produces an empty graph")
  func emptySchemaProducesEmptyGraph() {
    let graph = SchemaGraph.build(from: DatabaseSchema(schemas: []))
    #expect(graph.nodes.isEmpty)
    #expect(graph.edges.isEmpty)
  }
}
