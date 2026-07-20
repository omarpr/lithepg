import Testing
@testable import LithePGAppUI
@testable import LithePGCore

@Suite("ConnectSheet presentation")
struct ConnectSheetPresentationTests {
  @Test("Neon hint summarizes database user and pooled state")
  func neonHintSummarizesProfile() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://writer:***@ep-small-moon-a1b2c3-pooler.us-east-1.aws.neon.tech/appdb?sslmode=require"
      )
    )

    let hint = ConnectSheetPresentation.neonHint(for: profile)

    #expect(hint?.title == "Neon connection detected")
    #expect(hint?.detail == "Database appdb · User writer · Pooled")
  }

  @Test("Neon hint marks direct compute hosts")
  func neonHintMarksDirectHosts() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://writer:***@ep-small-moon-a1b2c3.us-east-1.aws.neon.tech/appdb?sslmode=require"
      )
    )

    let hint = ConnectSheetPresentation.neonHint(for: profile)

    #expect(hint?.detail == "Database appdb · User writer · Direct")
  }

  @Test("auto suggested name updates only while user has not customized it")
  func autoSuggestedNameRespectsUserEdits() {
    #expect(
      ConnectSheetPresentation.connectionName(
        current: "",
        previousSuggestion: nil,
        nextSuggestion: "Neon - appdb"
      ) == "Neon - appdb"
    )
    #expect(
      ConnectSheetPresentation.connectionName(
        current: "Neon - olddb",
        previousSuggestion: "Neon - olddb",
        nextSuggestion: "Neon - appdb"
      ) == "Neon - appdb"
    )
    #expect(
      ConnectSheetPresentation.connectionName(
        current: "Production Neon",
        previousSuggestion: "Neon - olddb",
        nextSuggestion: "Neon - appdb"
      ) == "Production Neon"
    )
  }

  @Test("missing suggestion leaves current name unchanged")
  func missingSuggestionLeavesNameUnchanged() {
    #expect(
      ConnectSheetPresentation.connectionName(
        current: "Manual",
        previousSuggestion: "Neon - appdb",
        nextSuggestion: nil
      ) == "Manual"
    )
  }

  @Test("saved connections paginate in groups of five and clamp stale pages")
  func savedConnectionPaginationUsesFiveItems() {
    let connections = Array(0..<12)

    #expect(SavedConnectionPagination.pageSize == 5)
    #expect(SavedConnectionPagination.pageCount(itemCount: 0) == 0)
    #expect(SavedConnectionPagination.pageCount(itemCount: 5) == 1)
    #expect(SavedConnectionPagination.pageCount(itemCount: 6) == 2)
    #expect(SavedConnectionPagination.pageCount(itemCount: 12) == 3)
    #expect(SavedConnectionPagination.page(of: connections, index: 0) == [0, 1, 2, 3, 4])
    #expect(SavedConnectionPagination.page(of: connections, index: 1) == [5, 6, 7, 8, 9])
    #expect(SavedConnectionPagination.page(of: connections, index: 2) == [10, 11])
    #expect(SavedConnectionPagination.page(of: connections, index: 99) == [10, 11])
    #expect(SavedConnectionPagination.normalizedPage(2, itemCount: 5) == 0)
  }
}
