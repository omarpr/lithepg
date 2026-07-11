import LithePGCore
import SwiftUI

/// Force-directed schema graph: tables as nodes, foreign keys as edges.
/// Read-only view over already-loaded schema metadata. Physics ticks only
/// while the layout is settling or a node is being dragged.
struct SchemaGraphView: View {
  let schema: DatabaseSchema

  @Environment(\.dismiss) private var dismiss
  @State private var graph: SchemaGraph
  @State private var layout: ForceLayout
  @State private var selectedID: String?
  @State private var cameraOffset: CGSize = .zero
  @State private var cameraScale: CGFloat = 1
  @State private var draggingNodeID: String?
  @State private var panStartOffset: CGSize?

  init(schema: DatabaseSchema) {
    self.schema = schema
    let graph = SchemaGraph.build(from: schema)
    _graph = State(initialValue: graph)
    _layout = State(initialValue: ForceLayout(graph: graph))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      HStack(spacing: 0) {
        canvas
        if let selectedID {
          Divider()
          inspector(for: selectedID)
        }
      }
    }
    .frame(minWidth: 900, idealWidth: 1100, minHeight: 600, idealHeight: 720)
    .task {
      while !Task.isCancelled {
        if !layout.isSettled {
          layout.step()
          try? await Task.sleep(for: .milliseconds(16))
        } else {
          try? await Task.sleep(for: .milliseconds(120))
        }
      }
    }
  }

  private var header: some View {
    HStack(spacing: 12) {
      Label("Schema graph", systemImage: "point.3.connected.trianglepath.dotted")
        .font(.headline)
      if let message = SchemaGraphPresentation.emptyStateMessage(for: graph) {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        withAnimation { cameraScale = min(3, cameraScale * 1.25) }
      } label: {
        Image(systemName: "plus.magnifyingglass")
      }
      .help("Zoom in")
      Button {
        withAnimation { cameraScale = max(0.3, cameraScale / 1.25) }
      } label: {
        Image(systemName: "minus.magnifyingglass")
      }
      .help("Zoom out")
      Button("Re-run layout") {
        layout = ForceLayout(graph: graph)
        cameraOffset = .zero
        cameraScale = 1
      }
      Button("Done") { dismiss() }
        .keyboardShortcut(.defaultAction)
    }
    .padding(12)
  }

  private var canvas: some View {
    GeometryReader { proxy in
      let nodes = SchemaGraphPresentation.nodes(
        graph: graph, layout: layout, selectedID: selectedID)
      let edges = SchemaGraphPresentation.edges(
        graph: graph, layout: layout, selectedID: selectedID)

      Canvas { context, size in
        context.translateBy(
          x: size.width / 2 + cameraOffset.width,
          y: size.height / 2 + cameraOffset.height)
        context.scaleBy(x: cameraScale, y: cameraScale)

        for edge in edges {
          draw(edge: edge, in: &context)
        }
        for node in nodes {
          draw(node: node, hasSelection: selectedID != nil, in: &context)
        }
      }
      .accessibilityElement()
      .accessibilityIdentifier("schema-graph-canvas")
      .accessibilityLabel(
        "Schema graph with \(nodes.count) tables and \(edges.count) relationships")
      .gesture(dragGesture(canvasSize: proxy.size))
      .simultaneousGesture(
        MagnifyGesture().onChanged { value in
          cameraScale = min(3, max(0.3, value.magnification))
        }
      )
    }
    .background(Color(nsColor: .textBackgroundColor))
  }

  private func inspector(for nodeID: String) -> some View {
    let rows = SchemaGraphPresentation.inspectorRows(nodeID: nodeID, schema: schema, graph: graph)
    let node = graph.nodes.first { $0.id == nodeID }
    return VStack(alignment: .leading, spacing: 8) {
      Text(node?.name ?? nodeID)
        .font(.headline)
      Text("\(node?.kind == .view ? "View" : "Table") · \(node?.schema ?? "")")
        .font(.caption)
        .foregroundStyle(.secondary)
      Divider()
      List(rows) { row in
        HStack(spacing: 6) {
          Text(row.name)
            .font(.callout.monospaced())
          Spacer()
          ForEach(row.badges, id: \.self) { badge in
            Text(badge)
              .font(.caption2.bold())
              .padding(.horizontal, 5)
              .padding(.vertical, 2)
              .background(
                (badge == "PK" ? Color.orange : Color.blue).opacity(0.18), in: Capsule())
          }
          Text(row.typeName)
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)
        }
      }
      .listStyle(.plain)
    }
    .padding(12)
    .frame(width: 280)
    .accessibilityIdentifier("schema-graph-inspector")
  }

  // MARK: - Drawing

  private func draw(edge: SchemaGraphPresentation.GraphEdge, in context: inout GraphicsContext) {
    let color: Color = edge.isHighlighted ? .accentColor : .secondary.opacity(0.35)
    if edge.isSelfReference {
      let loop = Path(
        ellipseIn: CGRect(x: edge.sourceX + 12, y: edge.sourceY - 30, width: 26, height: 26))
      context.stroke(loop, with: .color(color), lineWidth: edge.isHighlighted ? 2 : 1)
      return
    }
    var path = Path()
    path.move(to: CGPoint(x: edge.sourceX, y: edge.sourceY))
    path.addLine(to: CGPoint(x: edge.targetX, y: edge.targetY))
    context.stroke(path, with: .color(color), lineWidth: edge.isHighlighted ? 2 : 1)

    if edge.isHighlighted {
      let midpoint = CGPoint(
        x: (edge.sourceX + edge.targetX) / 2, y: (edge.sourceY + edge.targetY) / 2)
      context.draw(
        Text(edge.label).font(.caption2).foregroundStyle(.secondary),
        at: CGPoint(x: midpoint.x, y: midpoint.y - 8))
    }
  }

  private func draw(
    node: SchemaGraphPresentation.GraphNode,
    hasSelection: Bool,
    in context: inout GraphicsContext
  ) {
    let base: Color = node.isView ? .purple : .accentColor
    let dimmed = hasSelection && !node.isSelected && !node.isNeighbor
    let fill = base.opacity(dimmed ? 0.18 : node.isSelected ? 0.95 : 0.6)
    let rect = CGRect(
      x: node.x - node.radius, y: node.y - node.radius,
      width: node.radius * 2, height: node.radius * 2)

    context.fill(Path(ellipseIn: rect), with: .color(fill))
    if node.isSelected {
      context.stroke(
        Path(ellipseIn: rect.insetBy(dx: -3, dy: -3)),
        with: .color(base.opacity(0.5)), lineWidth: 2)
    }
    context.draw(
      Text(node.title)
        .font(.caption)
        .foregroundStyle(dimmed ? Color.secondary.opacity(0.5) : Color.primary),
      at: CGPoint(x: node.x, y: node.y + node.radius + 10))
  }

  // MARK: - Interaction

  private func dragGesture(canvasSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if draggingNodeID == nil && panStartOffset == nil {
          if let hit = hitTest(value.startLocation, canvasSize: canvasSize) {
            draggingNodeID = hit
          } else {
            panStartOffset = cameraOffset
          }
        }
        if let draggingNodeID {
          let world = worldPoint(for: value.location, canvasSize: canvasSize)
          layout.pin(draggingNodeID, at: .init(x: world.x, y: world.y))
        } else if let panStartOffset {
          cameraOffset = CGSize(
            width: panStartOffset.width + value.translation.width,
            height: panStartOffset.height + value.translation.height)
        }
      }
      .onEnded { value in
        let moved = hypot(value.translation.width, value.translation.height)
        if moved < 4 {
          selectedID = hitTest(value.startLocation, canvasSize: canvasSize)
        }
        draggingNodeID = nil
        panStartOffset = nil
      }
  }

  private func worldPoint(for location: CGPoint, canvasSize: CGSize) -> CGPoint {
    CGPoint(
      x: (location.x - canvasSize.width / 2 - cameraOffset.width) / cameraScale,
      y: (location.y - canvasSize.height / 2 - cameraOffset.height) / cameraScale)
  }

  private func hitTest(_ location: CGPoint, canvasSize: CGSize) -> String? {
    let world = worldPoint(for: location, canvasSize: canvasSize)
    let nodes = SchemaGraphPresentation.nodes(graph: graph, layout: layout, selectedID: nil)
    return nodes
      .filter { hypot($0.x - world.x, $0.y - world.y) <= max($0.radius, 16) }
      .min { hypot($0.x - world.x, $0.y - world.y) < hypot($1.x - world.x, $1.y - world.y) }?
      .id
  }
}
