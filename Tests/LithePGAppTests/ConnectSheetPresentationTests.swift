import Testing

@testable import LithePGAppUI
@testable import LithePGCore

@Suite("ConnectSheet presentation")
struct ConnectSheetPresentationTests {
  @Test("Neon hint summarizes database user and pooled state")
  func neonHintSummarizesProfile() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url:
          "postgres://writer:***@ep-small-moon-a1b2c3-pooler.us-east-1.aws.neon.tech/appdb?sslmode=require"
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
        url:
          "postgres://writer:***@ep-small-moon-a1b2c3.us-east-1.aws.neon.tech/appdb?sslmode=require"
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

  @Test("save mode uses an enabled Save & Connect action with an automatic name")
  func saveAndConnectPresentation() {
    #expect(ConnectSheetPresentation.primaryActionTitle(saveConnection: true) == "Save & Connect")
    #expect(ConnectSheetPresentation.primaryActionTitle(saveConnection: false) == "Connect")
    #expect(
      !ConnectSheetPresentation.primaryActionDisabled(
        connectionInputEmpty: false,
        isConnecting: false,
        isTestingConnection: false
      )
    )
    #expect(
      ConnectSheetPresentation.savedConnectionName(
        enteredName: "",
        host: "localhost",
        database: "postgres"
      ) == "localhost · postgres"
    )
    #expect(
      ConnectSheetPresentation.savedConnectionName(
        enteredName: "  Local dev  ",
        host: "localhost",
        database: "postgres"
      ) == "Local dev"
    )
  }

  @Test("URL naming never leaks values from the manual-fields mode")
  func urlNamingIsModeIsolated() {
    #expect(
      ConnectSheetPresentation.savedConnectionName(
        enteredName: "",
        inputMode: .url,
        url: "postgres://incomplete",
        fieldHost: "hidden-host",
        fieldDatabase: "hidden-database"
      ) == "Postgres connection"
    )
    #expect(
      ConnectSheetPresentation.savedConnectionName(
        enteredName: "",
        inputMode: .url,
        url: "postgres://user@url-host:5432/url-database",
        fieldHost: "hidden-host",
        fieldDatabase: "hidden-database"
      ) == "url-host · url-database"
    )
  }

  @Test("required fields use a consistent indicator and conditional requirements disable submit")
  func requiredFieldPresentation() {
    #expect(ConnectSheetPresentation.requiredFieldLabel("Host") == "Host *")
    #expect(
      ConnectSheetPresentation.primaryActionDisabled(
        connectionInputEmpty: false,
        requiredSupplementalInputEmpty: true,
        isConnecting: false,
        isTestingConnection: false
      )
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

  // MARK: - TLS mode picker

  @Test("titles every TLS mode")
  func titlesEveryMode() {
    #expect(ConnectSheetPresentation.tlsModeTitle(.disable) == "Off")
    #expect(ConnectSheetPresentation.tlsModeTitle(.prefer) == "Prefer")
    #expect(ConnectSheetPresentation.tlsModeTitle(.require) == "Encrypt only")
    #expect(ConnectSheetPresentation.tlsModeTitle(.verifyFull) == "Verify")
  }

  @Test("orders the picker from weakest to strongest")
  func ordersPickerWeakestFirst() {
    #expect(ConnectSheetPresentation.tlsModeOrder == [.disable, .prefer, .require, .verifyFull])
  }

  @Test("captions every TLS mode")
  func captionsEveryMode() {
    for mode in ConnectionConfig.TLSMode.allCases {
      #expect(ConnectSheetPresentation.tlsModeCaption(mode).isEmpty == false)
    }
  }

  @Test("shows the CA certificate field only for verify")
  func showsCAFieldOnlyForVerify() {
    #expect(ConnectSheetPresentation.showsCACertificateField(mode: .verifyFull))
    #expect(ConnectSheetPresentation.showsCACertificateField(mode: .require) == false)
    #expect(ConnectSheetPresentation.showsCACertificateField(mode: .prefer) == false)
    #expect(ConnectSheetPresentation.showsCACertificateField(mode: .disable) == false)
  }

  @Test("warns about cleartext for a remote host with encryption off")
  func warnsForRemoteCleartext() throws {
    let warning = try #require(
      ConnectSheetPresentation.encryptionWarning(mode: .disable, host: "db.example.com"))
    #expect(warning.contains("Cleartext"))
  }

  @Test("warns that prefer may fall back for a remote host")
  func warnsForRemotePrefer() throws {
    let warning = try #require(
      ConnectSheetPresentation.encryptionWarning(mode: .prefer, host: "db.example.com"))
    #expect(warning.contains("fall back"))
  }

  @Test("does not warn for a loopback host")
  func doesNotWarnForLoopback() {
    #expect(ConnectSheetPresentation.encryptionWarning(mode: .disable, host: "localhost") == nil)
    #expect(ConnectSheetPresentation.encryptionWarning(mode: .prefer, host: "127.0.0.1") == nil)
  }

  @Test("does not warn for modes that always encrypt")
  func doesNotWarnForEncryptedModes() {
    #expect(
      ConnectSheetPresentation.encryptionWarning(mode: .require, host: "db.example.com") == nil)
    #expect(
      ConnectSheetPresentation.encryptionWarning(mode: .verifyFull, host: "db.example.com") == nil)
  }

  @Test("does not warn when the host is not yet known")
  func doesNotWarnWithoutHost() {
    #expect(ConnectSheetPresentation.encryptionWarning(mode: .disable, host: "") == nil)
    #expect(ConnectSheetPresentation.encryptionWarning(mode: .disable, host: "   ") == nil)
  }
}
