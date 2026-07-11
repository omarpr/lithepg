import Foundation

/// Deterministic force-directed layout for `SchemaGraph`.
///
/// Nodes seed onto a golden-angle spiral in sorted-id order, so the same graph
/// always produces the same positions with no randomness. `step()` applies
/// edge springs, pair repulsion, centering pull and damping with a fixed
/// timestep. Graphs above `physicsNodeLimit` skip physics entirely and use a
/// deterministic grid so the canvas stays responsive.
public struct ForceLayout: Sendable {
  public struct Point: Sendable, Equatable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
      self.x = x
      self.y = y
    }

    public func distance(to other: Point) -> Double {
      let dx = x - other.x
      let dy = y - other.y
      return (dx * dx + dy * dy).squareRoot()
    }
  }

  public static let physicsNodeLimit = 300

  public private(set) var positions: [String: Point]
  public let usesGridFallback: Bool

  private let orderedIDs: [String]
  private let edges: [(source: String, target: String)]
  private var velocities: [String: Point]
  private var pinned: Set<String> = []
  private var hasStepped = false

  private static let repulsion = 12_000.0
  private static let springStiffness = 0.02
  private static let springRestLength = 140.0
  private static let centering = 0.005
  private static let damping = 0.85
  private static let settledSpeed = 0.05
  private static let minSeparation = 0.1

  public init(graph: SchemaGraph) {
    let ids = graph.nodes.map(\.id).sorted()
    self.orderedIDs = ids
    self.edges = graph.edges
      .filter { !$0.isSelfReference }
      .map { (source: $0.sourceID, target: $0.targetID) }
    self.usesGridFallback = ids.count > Self.physicsNodeLimit

    var seeded: [String: Point] = [:]
    if usesGridFallback {
      let columns = Int(Double(ids.count).squareRoot().rounded(.up))
      for (index, id) in ids.enumerated() {
        seeded[id] = Point(
          x: Double(index % columns) * 160.0,
          y: Double(index / columns) * 160.0
        )
      }
    } else {
      // Golden-angle spiral: well spread, deterministic, no hashing needed.
      for (index, id) in ids.enumerated() {
        let radius = 60.0 * Double(index + 1).squareRoot()
        let angle = Double(index) * 2.399963229728653
        seeded[id] = Point(x: radius * Foundation.cos(angle), y: radius * Foundation.sin(angle))
      }
    }
    self.positions = seeded
    self.velocities = Dictionary(uniqueKeysWithValues: ids.map { ($0, Point(x: 0, y: 0)) })
  }

  public var isSettled: Bool {
    if usesGridFallback { return true }
    guard hasStepped else { return orderedIDs.isEmpty }
    let peak = velocities.values.map { ($0.x * $0.x + $0.y * $0.y).squareRoot() }.max() ?? 0
    return peak < Self.settledSpeed
  }

  public mutating func step() {
    guard !usesGridFallback, !orderedIDs.isEmpty else { return }
    hasStepped = true
    var forces = Dictionary(uniqueKeysWithValues: orderedIDs.map { ($0, Point(x: 0, y: 0)) })

    // Pair repulsion, deterministic order.
    for (i, a) in orderedIDs.enumerated() {
      for b in orderedIDs.dropFirst(i + 1) {
        let pa = positions[a]!, pb = positions[b]!
        var dx = pa.x - pb.x
        var dy = pa.y - pb.y
        var d = (dx * dx + dy * dy).squareRoot()
        if d < Self.minSeparation {
          // Coincident seeds: push apart along a stable direction.
          dx = 1
          dy = 0
          d = Self.minSeparation
        }
        let magnitude = Self.repulsion / (d * d)
        forces[a]!.x += dx / d * magnitude
        forces[a]!.y += dy / d * magnitude
        forces[b]!.x -= dx / d * magnitude
        forces[b]!.y -= dy / d * magnitude
      }
    }

    // Edge springs.
    for edge in edges {
      guard let pa = positions[edge.source], let pb = positions[edge.target] else { continue }
      let dx = pb.x - pa.x
      let dy = pb.y - pa.y
      let d = max((dx * dx + dy * dy).squareRoot(), Self.minSeparation)
      let magnitude = Self.springStiffness * (d - Self.springRestLength)
      forces[edge.source]!.x += dx / d * magnitude
      forces[edge.source]!.y += dy / d * magnitude
      forces[edge.target]!.x -= dx / d * magnitude
      forces[edge.target]!.y -= dy / d * magnitude
    }

    // Centering pull, integration and damping.
    for id in orderedIDs where !pinned.contains(id) {
      let position = positions[id]!
      var velocity = velocities[id]!
      velocity.x = (velocity.x + forces[id]!.x - position.x * Self.centering) * Self.damping
      velocity.y = (velocity.y + forces[id]!.y - position.y * Self.centering) * Self.damping
      velocities[id] = velocity
      positions[id] = Point(x: position.x + velocity.x, y: position.y + velocity.y)
    }
  }

  /// Runs steps until the layout settles or the budget runs out.
  public mutating func settle(maxSteps: Int = 600) {
    var steps = 0
    repeat {
      step()
      steps += 1
    } while !isSettled && steps < maxSteps
  }

  /// Fixes a node under the user's pointer; pinned nodes ignore forces.
  public mutating func pin(_ id: String, at point: Point) {
    guard positions[id] != nil else { return }
    positions[id] = point
    velocities[id] = Point(x: 0, y: 0)
    pinned.insert(id)
  }

  public mutating func unpin(_ id: String) {
    pinned.remove(id)
  }
}
