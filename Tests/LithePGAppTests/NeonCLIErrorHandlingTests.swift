import Foundation
import Testing

@testable import LithePGAppUI

@Suite("Neon CLI error handling")
struct NeonCLIErrorHandlingTests {
  @Test("CLI failures become explanations with a next step")
  func classifiesFailures() {
    func classify(_ text: String, status: Int32 = 1) -> NeonCLIScannerError {
      NeonCLIScannerError.classify(errorOutput: text, status: status)
    }
    #expect(classify("env: node: No such file or directory", status: 127) == .nodeMissing)
    // The exact output Neon CLI 8 printed for an expired session, recommended command included.
    #expect(
      classify(
        """
        ERROR: The Neon authorization server rejected the stored session: invalid_grant: The provided authorization grant is invalid
        ERROR: Run `neon login --profile DEFAULT` to sign in again.
        """
      ) == .sessionExpired(signIn: "neon login --profile DEFAULT"))
    #expect(classify("ERROR: invalid_grant") == .sessionExpired(signIn: "neon login"))
    #expect(
      classify("ERROR: ENOENT: no such file or directory, open '\(NSHomeDirectory())/.config/neon/.refresh-1082c642b8613821.lock'")
        == .configFolderUnusable(path: "~/.config/neon", signIn: "neon login"))
    #expect(classify("Error: Unauthorized (401). Please run neon auth") == .notSignedIn(signIn: "neon login"))
    #expect(classify("FetchError: request failed, reason: getaddrinfo ENOTFOUND console.neon.tech") == .offline)
    #expect(classify("ERROR: Too Many Requests (429)") == .rateLimited)
    #expect(classify("ERROR: project not found\nstack trace...") == .commandFailed("project not found"))
    #expect(classify("", status: 3) == .commandFailed("it exited with status 3 without saying why."))
  }

  @Test("messages say what to do and avoid raw CLI output")
  func messagesAreActionable() {
    let expired = NeonCLIScannerError.sessionExpired(signIn: "neon login --profile DEFAULT")
    #expect(expired.errorDescription == "Your Neon CLI sign-in has expired. Run “neon login --profile DEFAULT” in Terminal to sign in again, then scan again.")
    #expect(expired.suggestedCommand == "neon login --profile DEFAULT")
    #expect(NeonCLIScannerError.offline.suggestedCommand == nil)
    #expect(NeonCLIScannerError.nodeMissing.errorDescription?.contains("Node.js") == true)
    #expect(NeonCLIScannerError.offline.stopsScan)
    #expect(!NeonCLIScannerError.invalidResponse.stopsScan)
  }

  @Test("an older sign-in folder is passed to the CLI only when the new one has no sign-in")
  func configDirectoryOverride() throws {
    let home = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: home) }
    let legacy = home.appendingPathComponent(".config/neonctl")
    #expect(NeonCLIScanner.configDirectoryArguments(home: home, fileManager: .default).isEmpty)

    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: legacy.appendingPathComponent("credentials.json"))
    #expect(NeonCLIScanner.configDirectoryArguments(home: home, fileManager: .default) == ["--config-dir", legacy.path])

    let current = home.appendingPathComponent(".config/neon")
    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
    try Data("{}".utf8).write(to: current.appendingPathComponent("credentials.json"))
    #expect(NeonCLIScanner.configDirectoryArguments(home: home, fileManager: .default).isEmpty)
  }

  @Test("the CLI runs with the Node installation beside it and Homebrew on its PATH")
  func searchPathIncludesNode() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    // nvm layout: versions/node/v22/bin/node next to lib/node_modules/neonctl/cli.js
    let version = root.appendingPathComponent("versions/node/v22")
    let bin = version.appendingPathComponent("bin")
    let cli = version.appendingPathComponent("lib/node_modules/neonctl/cli.js")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: cli.deletingLastPathComponent(), withIntermediateDirectories: true)
    try executableScript("#!/bin/sh\nexit 0\n", at: bin.appendingPathComponent("node"))

    let path = FoundationNeonCLICommandRunner.searchPath(
      for: cli, inherited: "/usr/bin:/bin", fileManager: .default
    ).split(separator: ":").map(String.init)
    #expect(path.first == bin.path)
    #expect(path.contains("/opt/homebrew/bin"))
    #expect(path.suffix(2) == ["/usr/bin", "/bin"])
  }

  @Test("a CLI that never finishes is stopped and explained", .timeLimit(.minutes(1)))
  func timesOut() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("neon")
    try executableScript("#!/bin/sh\nsleep 30\n", at: script)
    let started = ContinuousClock.now
    await #expect(throws: NeonCLIScannerError.timedOut(seconds: 0)) {
      _ = try await FoundationNeonCLICommandRunner(timeout: 0.5).run(executableURL: script, arguments: [])
    }
    #expect(ContinuousClock.now - started < .seconds(10))
  }

  @Test("a CLI that writes a lot of error output fails instead of hanging", .timeLimit(.minutes(1)))
  func largeErrorOutputDoesNotDeadlock() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("neon")
    try executableScript(
      "#!/bin/sh\nhead -c 300000 /dev/zero | tr '\\\\0' 'x' >&2\necho >&2\nexit 2\n", at: script)
    await #expect(throws: NeonCLIScannerError.self) {
      _ = try await FoundationNeonCLICommandRunner(timeout: 10).run(executableURL: script, arguments: [])
    }
  }

  // Regression: the runner used to block a Swift concurrency thread until the CLI exited. With
  // more CLIs than pool threads every other task froze, which hung the whole CI test process.
  @Test("CLIs that are still running leave other tasks free to run", .timeLimit(.minutes(1)))
  func runningCLIsDoNotStarveOtherTasks() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("neon")
    let marker = root.appendingPathComponent("go")
    // Each CLI waits until a task in this process creates the marker file.
    try executableScript("#!/bin/sh\nwhile [ ! -f \"$1\" ]; do sleep 0.05; done\n", at: script)
    let count = ProcessInfo.processInfo.activeProcessorCount + 2
    try await withThrowingTaskGroup(of: Data.self) { group in
      for _ in 0..<count {
        group.addTask {
          try await FoundationNeonCLICommandRunner(timeout: 10).run(executableURL: script, arguments: [marker.path])
        }
      }
      try await Task.sleep(nanoseconds: 200_000_000)
      try Data().write(to: marker)
      for try await _ in group {}
    }
  }

  @Test("cancelling a scan stops the CLI", .timeLimit(.minutes(1)))
  func cancellationStopsTheCLI() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("neon")
    try executableScript("#!/bin/sh\nexec sleep 30\n", at: script)
    let started = ContinuousClock.now
    let run = Task {
      try await FoundationNeonCLICommandRunner(timeout: 60).run(executableURL: script, arguments: [])
    }
    try await Task.sleep(nanoseconds: 200_000_000)
    run.cancel()
    await #expect(throws: CancellationError.self) { _ = try await run.value }
    #expect(ContinuousClock.now - started < .seconds(10))
  }

  @Test("a missing Node.js is reported as such", .timeLimit(.minutes(1)))
  func missingNode() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let script = root.appendingPathComponent("neon")
    try executableScript("#!/usr/bin/env lithepg-test-missing-node\n", at: script)
    await #expect(throws: NeonCLIScannerError.nodeMissing) {
      _ = try await FoundationNeonCLICommandRunner(timeout: 10).run(executableURL: script, arguments: [])
    }
  }

  @Test("an expired session stops the scan instead of skipping every branch")
  func fatalErrorsStopTheScan() async throws {
    let scanner = NeonCLIScanner(
      executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/neon"),
      commandRunner: ExpiringSessionRunner(),
      globalArguments: ["--config-dir", "/tmp/legacy"]
    )
    await #expect(throws: NeonCLIScannerError.sessionExpired(signIn: "neon login")) {
      _ = try await scanner.scan()
    }
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("lithepg-neon-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func executableScript(_ contents: String, at url: URL) throws {
    try Data(contents.utf8).write(to: url)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
  }
}

/// Lists one project, then fails every branch lookup as an expired session would.
private struct ExpiringSessionRunner: NeonCLICommandRunning {
  func run(executableURL: URL, arguments: [String]) async throws -> Data {
    #expect(arguments.suffix(2) == ["--config-dir", "/tmp/legacy"])
    if arguments.starts(with: ["orgs", "list"]) { return Data("[]".utf8) }
    if arguments.starts(with: ["projects", "list"]) {
      return Data(#"[{"id":"project-one","name":"Analytics"}]"#.utf8)
    }
    throw NeonCLIScannerError.sessionExpired(signIn: "neon login")
  }
}
