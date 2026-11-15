#if DEBUG
  import AppKit

  /// Debug builds only: writes a PNG of the main window, toolbar included, when
  /// `LITHEPG_DEBUG_SNAPSHOT_PATH` is set. The window draws itself into a bitmap, so this needs no
  /// screen recording permission, which makes UI changes reviewable from a terminal or an agent.
  /// Release builds compile this out.
  enum DebugWindowSnapshot {
    @MainActor
    static func scheduleIfRequested(
      environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
      guard let path = environment["LITHEPG_DEBUG_SNAPSHOT_PATH"], !path.isEmpty else { return }
      let delay = environment["LITHEPG_DEBUG_SNAPSHOT_DELAY"].flatMap(Double.init) ?? 3
      DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
        write(to: URL(fileURLWithPath: path))
      }
    }

    @MainActor
    private static func write(to url: URL) {
      guard
        let window = NSApp.windows.first(where: {
          $0.isVisible && $0.contentView != nil && $0.title != "About LithePG"
        }),
        let frameView = window.contentView?.superview
      else { return }
      let bounds = frameView.bounds
      guard let bitmap = frameView.bitmapImageRepForCachingDisplay(in: bounds) else { return }
      frameView.cacheDisplay(in: bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
  }
#endif
