import SwiftUI

enum SavedConnectionPagination {
  static let pageSize = 5

  static func pageCount(itemCount: Int) -> Int {
    guard itemCount > 0 else { return 0 }
    return (itemCount + pageSize - 1) / pageSize
  }

  static func normalizedPage(_ page: Int, itemCount: Int) -> Int {
    max(0, min(page, max(0, pageCount(itemCount: itemCount) - 1)))
  }

  static func page<Item>(of items: [Item], index: Int) -> [Item] {
    let page = normalizedPage(index, itemCount: items.count)
    let start = page * pageSize
    guard start < items.count else { return [] }
    return Array(items[start..<min(start + pageSize, items.count)])
  }
}

struct SavedConnectionPager: View {
  @Binding var page: Int
  let itemCount: Int
  let accessibilityPrefix: String

  private var pageCount: Int {
    SavedConnectionPagination.pageCount(itemCount: itemCount)
  }

  private var currentPage: Int {
    SavedConnectionPagination.normalizedPage(page, itemCount: itemCount)
  }

  var body: some View {
    if pageCount > 1 {
      HStack(spacing: 8) {
        Button {
          page = max(0, currentPage - 1)
        } label: {
          Label("Previous connections page", systemImage: "chevron.left")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .disabled(currentPage == 0)
        .accessibilityIdentifier("\(accessibilityPrefix)-previous-page")

        Text("Page \(currentPage + 1) of \(pageCount)")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .monospacedDigit()

        Button {
          page = min(pageCount - 1, currentPage + 1)
        } label: {
          Label("Next connections page", systemImage: "chevron.right")
            .labelStyle(.iconOnly)
        }
        .buttonStyle(.borderless)
        .disabled(currentPage >= pageCount - 1)
        .accessibilityIdentifier("\(accessibilityPrefix)-next-page")
      }
      .frame(maxWidth: .infinity, alignment: .center)
    }
  }
}
