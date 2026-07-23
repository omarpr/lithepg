import Testing
@testable import LithePGCore

@Suite("ForceLayout")
struct ForceLayoutTests {
  private func graph(nodes: Int, chained: Bool = true) -> SchemaGraph {
    let relations = (0..<nodes).map { index in
      DatabaseSchema.Relation(
        schema: "public", name: "t\(index)", kind: .table,
        columns: [.init(name: "id", typeName: "int4", isNullable: false, ordinalPosition: 1, isPrimaryKey: true)]
      )
    }
    let fks: [DatabaseSchema.ForeignKey] = chained
      ? (1..<nodes).map { index in
        .init(
          name: "fk\(index)",
          childSchema: "public", childRelation: "t\(index)", childColumns: ["id"],
          parentSchema: "public", parentRelation: "t\(index - 1)", parentColumns: ["id"]
        )
      }
      : []
    return SchemaGraph.build(from: DatabaseSchema(
      schemas: [.init(name: "public", relations: relations)],
      foreignKeys: fks
    ))
  }

  @Test("seeding is deterministic: same graph, same positions")
  func deterministicSeeding() {
    let g = graph(nodes: 6)
    let a = ForceLayout(graph: g)
    let b = ForceLayout(graph: g)
    #expect(a.positions == b.positions)
    #expect(!a.positions.isEmpty)
  }

  @Test("stepping is deterministic and settles")
  func deterministicSettling() {
    let g = graph(nodes: 6)
    var a = ForceLayout(graph: g)
    var b = ForceLayout(graph: g)
    a.settle()
    b.settle()
    #expect(a.positions == b.positions)
    #expect(a.isSettled)
  }

  @Test("connected nodes end up closer than unconnected ones")
  func edgesPullNodesTogether() {
    let g = graph(nodes: 3, chained: true)
    var layout = ForceLayout(graph: g)
    layout.settle()
    let p0 = layout.positions["public.t0"]!
    let p1 = layout.positions["public.t1"]!
    let p2 = layout.positions["public.t2"]!
    // t0-t1 and t1-t2 are linked; t0-t2 is not.
    let linked = p0.distance(to: p1)
    let unlinked = p0.distance(to: p2)
    #expect(linked < unlinked)
  }

  @Test("nodes never collapse onto each other")
  func nodesStaySeparated() {
    let g = graph(nodes: 8, chained: true)
    var layout = ForceLayout(graph: g)
    layout.settle()
    let points = layout.positions.values.map { $0 }
    for (i, a) in points.enumerated() {
      for b in points.dropFirst(i + 1) {
        #expect(a.distance(to: b) > 1.0)
      }
    }
  }

  @Test("pinning a node fixes its position through steps")
  func pinnedNodesDoNotMove() {
    let g = graph(nodes: 4)
    var layout = ForceLayout(graph: g)
    let pinned = ForceLayout.Point(x: 123, y: -45)
    layout.pin("public.t0", at: pinned)
    for _ in 0..<50 { layout.step() }
    #expect(layout.positions["public.t0"] == pinned)
  }

  /// Dense graph: `nodes` tables, each with up to `fanout` FKs to earlier tables.
  private func denseGraph(nodes: Int, fanout: Int) -> SchemaGraph {
    let relations = (0..<nodes).map { index in
      DatabaseSchema.Relation(
        schema: "public", name: "t\(index)", kind: .table,
        columns: [.init(name: "id", typeName: "int4", isNullable: false, ordinalPosition: 1, isPrimaryKey: true)]
      )
    }
    var fks: [DatabaseSchema.ForeignKey] = []
    for index in 0..<nodes {
      for k in 1...fanout where index - k >= 0 {
        fks.append(.init(
          name: "fk\(index)_\(k)",
          childSchema: "public", childRelation: "t\(index)", childColumns: ["id"],
          parentSchema: "public", parentRelation: "t\(index - k)", parentColumns: ["id"]
        ))
      }
    }
    return SchemaGraph.build(from: DatabaseSchema(
      schemas: [.init(name: "public", relations: relations)],
      foreignKeys: fks
    ))
  }

  @Test("dense graph near the physics limit settles and stays bounded")
  func denseGraphSettles() {
    // Regression: this graph used to diverge (positions ran off to ±30000 and
    // isSettled never became true, so the view span forever).
    let g = denseGraph(nodes: 250, fanout: 4)
    var layout = ForceLayout(graph: g)
    #expect(!layout.usesGridFallback)
    layout.settle()
    #expect(layout.isSettled)
    for point in layout.positions.values {
      #expect(point.x.isFinite && point.y.isFinite)
      #expect(abs(point.x) < 20_000 && abs(point.y) < 20_000)
    }
  }

  @Test("reheat wakes a settled layout, which then settles again")
  func reheatResumesThenSettles() {
    let g = graph(nodes: 8, chained: true)
    var layout = ForceLayout(graph: g)
    layout.settle()
    #expect(layout.isSettled)
    layout.reheat()
    #expect(!layout.isSettled)
    layout.settle()
    #expect(layout.isSettled)
  }

  @Test("large graphs fall back to a deterministic grid without physics")
  func gridFallbackForLargeGraphs() {
    let g = graph(nodes: ForceLayout.physicsNodeLimit + 1, chained: false)
    var layout = ForceLayout(graph: g)
    #expect(layout.usesGridFallback)
    #expect(layout.isSettled)
    let before = layout.positions
    layout.step()
    #expect(layout.positions == before)
  }
}
