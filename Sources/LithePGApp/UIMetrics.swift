import SwiftUI

/// Shared spacing, so every sidebar section and the main area start at the same edge.
enum UIMetrics {
  /// Leading and trailing inset of every sidebar section and of the main area's bars.
  static let inset: CGFloat = 16
  /// Vertical padding of a section header.
  static let headerVertical: CGFloat = 12
}

extension ConnectionEnvironment {
  /// The capsule label beside a connection: short enough to never crowd the name.
  var shortName: String {
    switch self {
    case .development: "Dev"
    case .staging: "Staging"
    case .production: "Prod"
    case .custom: "Custom"
    }
  }

  var tint: Color {
    switch self {
    case .development: .green
    case .staging: .orange
    case .production: .red
    case .custom: .blue
    }
  }
}

/// A small tinted capsule naming a connection's environment.
struct EnvironmentCapsule: View {
  let environment: ConnectionEnvironment
  var long = false

  var body: some View {
    Text(long ? environment.displayName : environment.shortName)
      .font(long ? .callout.bold() : .caption2.weight(.semibold))
      .foregroundStyle(environment.tint)
      .lineLimit(1)
      .padding(.horizontal, long ? 10 : 6)
      .padding(.vertical, long ? 5 : 2)
      .background(environment.tint.opacity(0.15), in: Capsule())
      .accessibilityLabel("\(environment.displayName) environment")
  }
}

/// Toolbar commands: icon and label side by side, drawn as their own chip with a margin, so
/// neighbouring buttons never touch. The system draws adjacent bordered items flush.
struct ToolbarCommandLabelStyle: LabelStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    Chip(configuration: configuration, prominent: prominent)
  }

  private struct Chip: View {
    let configuration: LabelStyleConfiguration
    let prominent: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
      HStack(spacing: 5) {
        configuration.icon
          .font(.system(size: 12))
        configuration.title
          .font(.system(size: 12))
          .lineLimit(1)
      }
      .foregroundStyle(prominent && isEnabled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
      .padding(.horizontal, 9)
      .padding(.vertical, 4)
      .background(
        prominent && isEnabled ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
        in: RoundedRectangle(cornerRadius: 6)
      )
      // The margin that keeps neighbouring chips apart.
      .padding(.horizontal, 3)
      .contentShape(Rectangle())
    }
  }
}

extension View {
  /// Shows a row action only while the pointer is over the row. It stays in the
  /// accessibility tree, so VoiceOver and keyboard users can always reach it.
  func revealedOnHover(_ isHovering: Bool) -> some View {
    opacity(isHovering ? 1 : 0)
  }
}
