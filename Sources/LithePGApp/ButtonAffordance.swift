import AppKit
import SwiftUI

/// Gives every visible action the same macOS affordances: a concise tooltip
/// and a pointing-hand cursor only while the action is enabled.
private struct ButtonAffordance: ViewModifier {
  let tooltip: String

  @Environment(\.isEnabled) private var isEnabled

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content
        .help(tooltip)
        .pointerStyle(isEnabled ? .link : .default)
    } else {
      content
        .help(tooltip)
        .modifier(LegacyPointingHandCursor(isEnabled: isEnabled))
    }
  }
}

/// `pointerStyle` is macOS 15+, while LithePG still supports macOS 14.
/// Keep the cursor stack balanced even when an action disables or disappears
/// while the pointer is still over it.
private struct LegacyPointingHandCursor: ViewModifier {
  let isEnabled: Bool

  @State private var isHovering = false
  @State private var isShowingPointer = false

  func body(content: Content) -> some View {
    content
      .onHover { hovering in
        isHovering = hovering
        updatePointer(shouldShow: hovering && isEnabled)
      }
      .onChange(of: isEnabled) { _, enabled in
        updatePointer(shouldShow: isHovering && enabled)
      }
      .onDisappear {
        updatePointer(shouldShow: false)
      }
  }

  private func updatePointer(shouldShow: Bool) {
    guard shouldShow != isShowingPointer else { return }
    if shouldShow {
      NSCursor.pointingHand.push()
    } else {
      NSCursor.pop()
    }
    isShowingPointer = shouldShow
  }
}

extension View {
  /// Use for controls that behave like buttons but are represented by another
  /// SwiftUI type, such as links, segmented pickers, and disclosure labels.
  func controlAffordance(_ tooltip: String) -> some View {
    modifier(ButtonAffordance(tooltip: tooltip))
  }

  func buttonAffordance(_ tooltip: String) -> some View {
    controlAffordance(tooltip)
  }

  func dragAffordance(_ tooltip: String) -> some View {
    modifier(DragAffordance(tooltip: tooltip))
  }
}

private struct DragAffordance: ViewModifier {
  let tooltip: String

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(macOS 15.0, *) {
      content
        .help(tooltip)
        .pointerStyle(.grabIdle)
    } else {
      content
        .help(tooltip)
        .modifier(LegacyOpenHandCursor())
    }
  }
}

private struct LegacyOpenHandCursor: ViewModifier {
  @State private var isShowingPointer = false

  func body(content: Content) -> some View {
    content
      .onHover { hovering in
        updatePointer(shouldShow: hovering)
      }
      .onDisappear {
        updatePointer(shouldShow: false)
      }
  }

  private func updatePointer(shouldShow: Bool) {
    guard shouldShow != isShowingPointer else { return }
    if shouldShow {
      NSCursor.openHand.push()
    } else {
      NSCursor.pop()
    }
    isShowingPointer = shouldShow
  }
}
