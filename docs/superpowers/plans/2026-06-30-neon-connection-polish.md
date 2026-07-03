# Neon Connection Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recognize pasted Neon Postgres URLs in the connect sheet, preserve verified TLS, show a Neon hint, and suggest a saved-connection name without adding Neon API/token handling.

**Architecture:** Add a pure `NeonConnectionProfile` helper to `LithePGCore` and cover it with Swift Testing. Add a small `ConnectSheetPresentation` helper in `ConnectSheet.swift` so the SwiftUI view can show provider hints and auto-fill the saved-connection name only while it is user-unmodified.

**Tech Stack:** Swift 6.2, Swift Testing, SwiftUI, existing `ConnectionConfig`, existing JSON/Keychain persistence paths.

---

## File Structure

- Create `Sources/LithePGCore/NeonConnectionProfile.swift`: pure URL/provider detection and safe presentation values.
- Create `Tests/LithePGCoreTests/NeonConnectionProfileTests.swift`: TDD coverage for Neon compute hosts, pooled hosts, malformed URLs, non-Neon URLs, names, TLS, and password exclusion.
- Modify `Sources/LithePGApp/ConnectSheet.swift`: render the Neon hint, track auto-suggested save names, and expose `ConnectSheetPresentation` helpers.
- Create `Tests/LithePGAppTests/ConnectSheetPresentationTests.swift`: headless coverage for hint text and auto-name overwrite behavior.
- Optionally modify `README.md` only if the final UI is not self-explanatory. The expected implementation should not require README changes.

## Task 1: Core Neon URL Profile

**Files:**
- Create: `Sources/LithePGCore/NeonConnectionProfile.swift`
- Create: `Tests/LithePGCoreTests/NeonConnectionProfileTests.swift`

- [x] **Step 1: Write failing core tests**

Create `Tests/LithePGCoreTests/NeonConnectionProfileTests.swift`:

```swift
import Testing
@testable import LithePGCore

@Suite("NeonConnectionProfile")
struct NeonConnectionProfileTests {
  @Test("detects standard Neon compute endpoint URLs")
  func detectsStandardNeonURL() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgresql://omar:secret@ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech/appdb?sslmode=require"
      )
    )

    #expect(profile.host == "ep-lively-sun-a1b2c3.us-east-2.aws.neon.tech")
    #expect(profile.endpointID == "ep-lively-sun-a1b2c3")
    #expect(profile.database == "appdb")
    #expect(profile.username == "omar")
    #expect(profile.isPooled == false)
    #expect(profile.suggestedName == "Neon - appdb")
    #expect(profile.tlsMode == .verifyFull)
  }

  @Test("detects pooled Neon hosts")
  func detectsPooledNeonURL() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://writer:p%40ss@ep-lively-sun-a1b2c3-pooler.us-east-2.aws.neon.tech/neondb?sslmode=require"
      )
    )

    #expect(profile.endpointID == "ep-lively-sun-a1b2c3")
    #expect(profile.isPooled == true)
    #expect(profile.database == "neondb")
    #expect(profile.username == "writer")
  }

  @Test("detects Neon domains even without an endpoint-shaped first label")
  func detectsNeonDomainWithoutEndpointID() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(url: "postgres://u:p@custom.neon.tech/main?sslmode=require")
    )

    #expect(profile.endpointID == nil)
    #expect(profile.host == "custom.neon.tech")
    #expect(profile.suggestedName == "Neon - main")
  }

  @Test("ignores non-Neon Postgres URLs and malformed URLs")
  func ignoresNonNeonAndMalformedURLs() {
    #expect(NeonConnectionProfile.detect(url: "postgres://u:p@db.example.com/main") == nil)
    #expect(NeonConnectionProfile.detect(url: "not a url") == nil)
    #expect(NeonConnectionProfile.detect(url: "mysql://u:p@ep-test.neon.tech/main") == nil)
  }

  @Test("profile output excludes password values")
  func profileOutputExcludesPasswords() throws {
    let password = "super-secret"
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://reader:\(password)@ep-long-river-a9b8c7.us-east-1.aws.neon.tech/reporting?sslmode=require"
      )
    )

    let mirrorDump = String(describing: profile)
    #expect(!mirrorDump.contains(password))
    #expect(!profile.suggestedName.contains(password))
  }
}
```

- [x] **Step 2: Run focused test and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NeonConnectionProfile
```

Expected: compile failure because `NeonConnectionProfile` does not exist.

- [x] **Step 3: Implement minimal core helper**

Create `Sources/LithePGCore/NeonConnectionProfile.swift`:

```swift
import Foundation

public struct NeonConnectionProfile: Sendable, Equatable, CustomStringConvertible {
  public let host: String
  public let endpointID: String?
  public let database: String
  public let username: String
  public let isPooled: Bool
  public let suggestedName: String
  public let tlsMode: ConnectionConfig.TLSMode

  public var description: String {
    "NeonConnectionProfile(host: \(host), endpointID: \(endpointID ?? "nil"), database: \(database), username: \(username), isPooled: \(isPooled), suggestedName: \(suggestedName), tlsMode: \(tlsMode))"
  }

  public static func detect(url: String) -> NeonConnectionProfile? {
    guard let config = try? ConnectionConfig(url: url) else { return nil }
    let host = config.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard isNeonHost(host) else { return nil }

    let firstLabel = host.split(separator: ".", maxSplits: 1).first.map(String.init) ?? host
    let isPooled = firstLabel.hasSuffix("-pooler") || host.contains("-pooler.")
    let endpointLabel = isPooled && firstLabel.hasSuffix("-pooler")
      ? String(firstLabel.dropLast("-pooler".count))
      : firstLabel
    let endpointID = endpointLabel.hasPrefix("ep-") ? endpointLabel : nil
    let suggestedName = "Neon - \(config.database)"

    return NeonConnectionProfile(
      host: host,
      endpointID: endpointID,
      database: config.database,
      username: config.username,
      isPooled: isPooled,
      suggestedName: suggestedName,
      tlsMode: config.tlsMode
    )
  }

  private static func isNeonHost(_ host: String) -> Bool {
    host == "neon.tech" || host.hasSuffix(".neon.tech")
  }
}
```

- [x] **Step 4: Run focused test and verify GREEN**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter NeonConnectionProfile
```

Expected: all `NeonConnectionProfile` tests pass.

- [x] **Step 5: Commit core helper**

Run:

```sh
git add Sources/LithePGCore/NeonConnectionProfile.swift Tests/LithePGCoreTests/NeonConnectionProfileTests.swift
git commit -s -m "feat(core): detect Neon connection strings"
```

## Task 2: Connect Sheet Presentation Wiring

**Files:**
- Modify: `Sources/LithePGApp/ConnectSheet.swift`
- Create: `Tests/LithePGAppTests/ConnectSheetPresentationTests.swift`

- [x] **Step 1: Write failing presentation tests**

Create `Tests/LithePGAppTests/ConnectSheetPresentationTests.swift`:

```swift
import Testing
@testable import LithePGAppUI
@testable import LithePGCore

@Suite("ConnectSheet presentation")
struct ConnectSheetPresentationTests {
  @Test("Neon hint summarizes database user and pooled state")
  func neonHintSummarizesProfile() throws {
    let profile = try #require(
      NeonConnectionProfile.detect(
        url: "postgres://writer:secret@ep-small-moon-a1b2c3-pooler.us-east-1.aws.neon.tech/appdb?sslmode=require"
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
        url: "postgres://writer:secret@ep-small-moon-a1b2c3.us-east-1.aws.neon.tech/appdb?sslmode=require"
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
}
```

- [x] **Step 2: Run focused test and verify RED**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConnectSheetPresentation
```

Expected: compile failure because `ConnectSheetPresentation` does not exist.

- [x] **Step 3: Add presentation helper and wire UI**

Modify `Sources/LithePGApp/ConnectSheet.swift`:

1. Add state:

```swift
  @State private var lastAutoConnectionName: String?
```

2. Add derived profile/hint near other private computed properties:

```swift
  private var neonProfile: NeonConnectionProfile? {
    guard inputMode == .url else { return nil }
    return NeonConnectionProfile.detect(url: effectiveURL)
  }

  private var neonHint: ConnectSheetPresentation.ProviderHint? {
    ConnectSheetPresentation.neonHint(for: neonProfile)
  }
```

3. Add hint UI below the URL field:

```swift
          if let neonHint {
            Label {
              VStack(alignment: .leading, spacing: 2) {
                Text(neonHint.title)
                  .font(.caption.bold())
                Text(neonHint.detail)
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
            } icon: {
              Image(systemName: "sparkle.magnifyingglass")
            }
            .foregroundStyle(.green)
            .accessibilityIdentifier("neon-connection-hint")
          }
```

4. Update the URL `onChange` body after TLS assignment:

```swift
              applyNeonConnectionNameSuggestion()
```

5. Update the save toggle section so enabling save applies the suggestion:

```swift
        Toggle("Save this connection", isOn: $saveConnection)
          .onChange(of: saveConnection) { _, enabled in
            if enabled { applyNeonConnectionNameSuggestion() }
          }
```

6. Add helper method inside `ConnectSheet`:

```swift
  private func applyNeonConnectionNameSuggestion() {
    let nextSuggestion = neonProfile?.suggestedName
    let nextName = ConnectSheetPresentation.connectionName(
      current: connectionName,
      previousSuggestion: lastAutoConnectionName,
      nextSuggestion: saveConnection ? nextSuggestion : nil
    )
    if nextName != connectionName {
      connectionName = nextName
    }
    lastAutoConnectionName = nextName == nextSuggestion ? nextSuggestion : nil
  }
```

7. Add helper outside `ConnectSheet`:

```swift
enum ConnectSheetPresentation {
  struct ProviderHint: Equatable {
    let title: String
    let detail: String
  }

  static func neonHint(for profile: NeonConnectionProfile?) -> ProviderHint? {
    guard let profile else { return nil }
    let path = profile.isPooled ? "Pooled" : "Direct"
    return ProviderHint(
      title: "Neon connection detected",
      detail: "Database \(profile.database) · User \(profile.username) · \(path)"
    )
  }

  static func connectionName(
    current: String,
    previousSuggestion: String?,
    nextSuggestion: String?
  ) -> String {
    guard let nextSuggestion else { return current }
    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || current == previousSuggestion {
      return nextSuggestion
    }
    return current
  }
}
```

- [x] **Step 4: Run focused test and verify GREEN**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter ConnectSheetPresentation
```

Expected: all `ConnectSheetPresentation` tests pass.

- [x] **Step 5: Run broader app/core tests**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --filter "NeonConnectionProfile|ConnectSheetPresentation|ConnectionConfig|AppState"
```

Expected: focused related suites pass; env-gated live tests may skip as designed.

- [x] **Step 6: Commit UI wiring**

Run:

```sh
git add Sources/LithePGApp/ConnectSheet.swift Tests/LithePGAppTests/ConnectSheetPresentationTests.swift
git commit -s -m "feat(app): polish Neon connection paste flow"
```

## Task 3: Final Verification

**Files:**
- Verify all changed files.
- No docs update expected unless implementation differs from the spec.

- [x] **Step 1: Run formatting whitespace check**

Run:

```sh
git diff --check
```

Expected: no output and exit code 0.

- [x] **Step 2: Run full Swift test suite**

Run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

Expected: full suite passes; live/Postgres/UI/model-artifact tests skip when env vars are absent.

- [x] **Step 3: Check git history and status**

Run:

```sh
git status --short --branch
git log --oneline --decorate -n 8
```

Expected: branch contains the plan commit and two implementation commits, with a clean working tree.

## Self-Review

- Spec coverage: all approved scope items are covered by Task 1 and Task 2; out-of-scope Neon API/token/Console-link work is not included.
- Placeholder scan: no incomplete-marker or vague-edge-case steps are present.
- Type consistency: `NeonConnectionProfile`, `ConnectSheetPresentation.ProviderHint`, and test names match across tasks.
