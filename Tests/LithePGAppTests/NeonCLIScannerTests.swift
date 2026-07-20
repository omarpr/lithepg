import Foundation
import LithePGCore
import Testing

@testable import LithePGAppUI

@Suite("Neon CLI scanner")
struct NeonCLIScannerTests {
  @Test("scanner scopes projects to a Neon organization and uses machine-readable output")
  func scannerWalksNeonResources() async throws {
    let runner = FixtureNeonCommandRunner()
    let scanner = NeonCLIScanner(
      executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/neon"),
      version: "2.34.1",
      commandRunner: runner
    )

    let report = try await scanner.scan()

    #expect(report.connections == [
      NeonCLIConnection(
        projectID: "project-one",
        projectName: "Analytics",
        branchID: "br-main",
        branchName: "production",
        databaseName: "warehouse",
        connectionURL: "postgresql://owner:secret@ep-blue.neon.tech/warehouse?sslmode=require"
      )
    ])
    #expect(report.skippedResources == 0)

    let invocations = await runner.invocations
    #expect(invocations.count == 5)
    #expect(invocations[0].arguments == [
      "orgs", "list", "--output", "json", "--no-color", "--no-analytics",
    ])
    #expect(invocations[1].arguments == [
      "projects", "list", "--org-id", "org-one",
      "--output", "json", "--no-color", "--no-analytics",
    ])
    #expect(invocations[2].arguments.contains("branches"))
    #expect(invocations[3].arguments.contains("databases"))
    #expect(invocations[4].arguments.contains("connection-string"))
    #expect(invocations[4].arguments.contains("--role-name"))
    #expect(invocations[4].arguments.contains("owner"))
  }

  @Test("scanner maps interactive terminal output to an invalid response")
  func scannerRejectsInteractiveOutput() async {
    let scanner = NeonCLIScanner(
      executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/neon"),
      commandRunner: InteractivePromptCommandRunner()
    )

    do {
      _ = try await scanner.scan()
      Issue.record("Expected the interactive prompt to be rejected")
    } catch let error as NeonCLIScannerError {
      guard case .invalidResponse = error else {
        Issue.record("Expected invalidResponse, received \(error)")
        return
      }
    } catch {
      Issue.record("Expected NeonCLIScannerError, received \(error)")
    }
  }

  @Test("invalid Neon output becomes a useful scan error")
  @MainActor
  func interactiveOutputIsNotShownAsADecoderDump() async {
    let state = AppState(
      savedConnectionStore: InMemorySavedConnectionStore(),
      credentialStore: InMemoryCredentialStore(),
      neonScanner: FixtureNeonScanner(shouldReturnInvalidResponse: true)
    )

    await state.scanAndImportNeonConnections()

    #expect(
      state.neonScanError
        == "Neon CLI did not return usable JSON. Run `neon auth` in Terminal, confirm your account, then try again."
    )
    #expect(state.neonScanError?.contains("DecodingError") == false)
  }

  @Test("app state imports only Neon endpoints that are not already saved")
  @MainActor
  func appStateImportsOnlyMissingEndpoints() async throws {
    let savedStore = InMemorySavedConnectionStore(connections: [
      SavedConnectionMetadata(
        name: "Existing Neon",
        host: "ep-existing.neon.tech",
        port: 5432,
        database: "app",
        username: "owner",
        tlsMode: "verify-full",
        environment: .development,
        secretReference: "existing-secret"
      )
    ])
    let credentialStore = InMemoryCredentialStore(secrets: ["existing-secret": "old"])
    let scanner = FixtureNeonScanner(connections: [
      NeonCLIConnection(
        projectID: "project-one", projectName: "App", branchID: "br-main",
        branchName: "production", databaseName: "app",
        connectionURL: "postgresql://owner:new@ep-existing.neon.tech/app?sslmode=require"
      ),
      NeonCLIConnection(
        projectID: "project-two", projectName: "Reports", branchID: "br-main",
        branchName: "production", databaseName: "reporting",
        connectionURL: "postgresql://analyst:secret@ep-reporting.neon.tech/reporting?sslmode=require"
      ),
    ])
    let state = AppState(
      savedConnectionStore: savedStore,
      credentialStore: credentialStore,
      neonScanner: scanner
    )

    await state.scanAndImportNeonConnections()

    #expect(state.savedConnections.count == 2)
    #expect(state.savedConnections.map(\.name).contains("Neon · Reports · production · reporting"))
    #expect(state.neonScanMessage == "Imported 1 Neon database. 1 was already saved.")
    #expect(state.neonScanError == nil)
    let imported = try #require(
      state.savedConnections.first { $0.host == "ep-reporting.neon.tech" }
    )
    #expect(try await credentialStore.loadSecret(for: imported.secretReference!) == "secret")
  }

  @Test("missing CLI is represented as an unavailable disabled action")
  @MainActor
  func missingCLIAvailability() {
    let state = AppState(neonScanner: FixtureNeonScanner(availability: .unavailable))

    #expect(state.neonCLIAvailability == .unavailable)
    #expect(state.canScanNeon == false)
    #expect(ConnectionNavigatorPresentation.neonButtonTitle(
      availability: state.neonCLIAvailability,
      isScanning: false
    ) == "Neon CLI not installed")
  }
}

private struct InteractivePromptCommandRunner: NeonCLICommandRunning {
  func run(executableURL: URL, arguments: [String]) async throws -> Data {
    Data("\u{001B}[?25l? What organization would you like to use?".utf8)
  }
}

private actor FixtureNeonCommandRunner: NeonCLICommandRunning {
  struct Invocation: Sendable, Equatable {
    let arguments: [String]
  }

  private(set) var invocations: [Invocation] = []

  func run(executableURL: URL, arguments: [String]) async throws -> Data {
    invocations.append(.init(arguments: arguments))
    if arguments.starts(with: ["orgs", "list"]) {
      return Data(#"[{"id":"org-one","name":"Example"}]"#.utf8)
    }
    if arguments.starts(with: ["projects", "list"]) {
      return Data(#"[{"id":"project-one","name":"Analytics"}]"#.utf8)
    }
    if arguments.starts(with: ["branches", "list"]) {
      return Data(#"[{"id":"br-main","name":"production","default":true}]"#.utf8)
    }
    if arguments.starts(with: ["databases", "list"]) {
      return Data(#"[{"name":"warehouse","owner_name":"owner"}]"#.utf8)
    }
    if arguments.starts(with: ["connection-string"]) {
      return Data("postgresql://owner:secret@ep-blue.neon.tech/warehouse?sslmode=require\n".utf8)
    }
    throw FixtureError.unexpectedCommand
  }

  enum FixtureError: Error { case unexpectedCommand }
}

private struct FixtureNeonScanner: NeonCLIScanning {
  let availabilityState: NeonCLIAvailability
  let connections: [NeonCLIConnection]
  let shouldReturnInvalidResponse: Bool

  init(
    availability: NeonCLIAvailability = .available(
      executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/neon"),
      version: "2.34.1"
    ),
    connections: [NeonCLIConnection] = [],
    shouldReturnInvalidResponse: Bool = false
  ) {
    availabilityState = availability
    self.connections = connections
    self.shouldReturnInvalidResponse = shouldReturnInvalidResponse
  }

  func availability() -> NeonCLIAvailability { availabilityState }

  func scan() async throws -> NeonCLIScanReport {
    if shouldReturnInvalidResponse {
      throw NeonCLIScannerError.invalidResponse
    }
    return NeonCLIScanReport(connections: connections, skippedResources: 0)
  }
}
