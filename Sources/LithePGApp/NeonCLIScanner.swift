import Foundation
import LithePGCore

public enum NeonCLIAvailability: Sendable, Equatable {
  case unavailable
  case available(executableURL: URL, version: String?)

  public var isAvailable: Bool {
    if case .available = self { return true }
    return false
  }
}

public struct NeonCLIConnection: Sendable, Equatable, Identifiable {
  public let projectID: String
  public let projectName: String
  public let branchID: String
  public let branchName: String
  public let databaseName: String
  public let connectionURL: String

  public init(
    projectID: String,
    projectName: String,
    branchID: String,
    branchName: String,
    databaseName: String,
    connectionURL: String
  ) {
    self.projectID = projectID
    self.projectName = projectName
    self.branchID = branchID
    self.branchName = branchName
    self.databaseName = databaseName
    self.connectionURL = connectionURL
  }

  public var id: String { "\(projectID)|\(branchID)|\(databaseName)" }

  public var suggestedName: String {
    "Neon · \(projectName) · \(branchName) · \(databaseName)"
  }
}

public struct NeonCLIScanReport: Sendable, Equatable {
  public let connections: [NeonCLIConnection]
  public let skippedResources: Int

  public init(connections: [NeonCLIConnection], skippedResources: Int) {
    self.connections = connections
    self.skippedResources = skippedResources
  }
}

public protocol NeonCLIScanning: Sendable {
  func availability() -> NeonCLIAvailability
  func scan() async throws -> NeonCLIScanReport
}

public protocol NeonCLICommandRunning: Sendable {
  func run(executableURL: URL, arguments: [String]) async throws -> Data
}

public struct NeonCLIScanner: NeonCLIScanning, Sendable {
  private let executableURL: URL?
  private let version: String?
  private let commandRunner: any NeonCLICommandRunning
  /// Global options added to every command, such as a `--config-dir` override.
  private let globalArguments: [String]

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    let home = environment["HOME"].map { URL(fileURLWithPath: $0) }
      ?? fileManager.homeDirectoryForCurrentUser
    executableURL = Self.findExecutable(fileManager: fileManager, environment: environment, home: home)
    version = nil
    commandRunner = FoundationNeonCLICommandRunner()
    globalArguments = Self.configDirectoryArguments(home: home, fileManager: fileManager)
  }

  init(
    executableURL: URL,
    version: String? = nil,
    commandRunner: any NeonCLICommandRunning,
    globalArguments: [String] = []
  ) {
    self.executableURL = executableURL
    self.version = version
    self.commandRunner = commandRunner
    self.globalArguments = globalArguments
  }

  /// Neon CLI 8 keeps its settings in `~/.config/neon` but still reads a sign-in saved by
  /// older versions in `~/.config/neonctl`. When only the older folder exists, refreshing that
  /// sign-in fails writing a lock file into the missing new folder ("ENOENT ... .refresh-*.lock"),
  /// which hides the real state of the session. Pointing the CLI at the folder that holds the
  /// sign-in avoids that, and a fresh `neon auth` (which creates the new folder) takes over.
  static func configDirectoryArguments(home: URL, fileManager: FileManager) -> [String] {
    let current = home.appendingPathComponent(".config/neon/credentials.json")
    let legacyFolder = home.appendingPathComponent(".config/neonctl")
    guard !fileManager.fileExists(atPath: current.path),
      fileManager.fileExists(atPath: legacyFolder.appendingPathComponent("credentials.json").path)
    else { return [] }
    return ["--config-dir", legacyFolder.path]
  }

  public func availability() -> NeonCLIAvailability {
    guard let executableURL else { return .unavailable }
    return .available(executableURL: executableURL, version: version)
  }

  public func scan() async throws -> NeonCLIScanReport {
    guard let executableURL else { throw NeonCLIScannerError.notInstalled }

    let organizations: [Organization] = try Self.decodeArray(
      try await runJSON(["orgs", "list"], executableURL: executableURL)
    )
    var discoveredProjects: [Project] = []
    if organizations.isEmpty {
      discoveredProjects = try Self.decodeProjects(
        try await runJSON(["projects", "list"], executableURL: executableURL)
      )
    } else {
      for organization in organizations {
        discoveredProjects += try Self.decodeProjects(
          try await runJSON(
            ["projects", "list", "--org-id", organization.id],
            executableURL: executableURL
          )
        )
      }
    }
    let projects = Dictionary(grouping: discoveredProjects, by: \.id)
      .compactMap { $0.value.first }
      .sorted { ($0.name, $0.id) < ($1.name, $1.id) }
    var connections: [NeonCLIConnection] = []
    var skippedResources = 0

    for project in projects {
      let branches: [Branch]
      do {
        branches = try Self.decodeArray(
          try await runJSON(
            ["branches", "list", "--project-id", project.id],
            executableURL: executableURL
          )
        )
      } catch let error as NeonCLIScannerError where error.stopsScan {
        throw error
      } catch {
        skippedResources += 1
        continue
      }

      for branch in branches {
        let databases: [Database]
        do {
          databases = try Self.decodeArray(
            try await runJSON(
              [
                "databases", "list", "--project-id", project.id,
                "--branch", branch.id,
              ],
              executableURL: executableURL
            )
          )
        } catch let error as NeonCLIScannerError where error.stopsScan {
          throw error
        } catch {
          skippedResources += 1
          continue
        }

        for database in databases {
          var arguments = [
            "connection-string", branch.id,
            "--project-id", project.id,
            "--database-name", database.name,
          ]
          if let ownerName = database.ownerName, !ownerName.isEmpty {
            arguments.append(contentsOf: ["--role-name", ownerName])
          }
          arguments.append(contentsOf: ["--ssl", "require", "--no-color", "--no-analytics"])

          do {
            let data = try await commandRunner.run(
              executableURL: executableURL,
              arguments: arguments + globalArguments
            )
            guard data.count <= Self.maximumOutputBytes,
              let rawURL = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              NeonConnectionProfile.detect(url: rawURL) != nil
            else {
              throw NeonCLIScannerError.invalidResponse
            }
            connections.append(
              NeonCLIConnection(
                projectID: project.id,
                projectName: project.name,
                branchID: branch.id,
                branchName: branch.name,
                databaseName: database.name,
                connectionURL: rawURL
              )
            )
          } catch let error as NeonCLIScannerError where error.stopsScan {
            throw error
          } catch {
            skippedResources += 1
          }
        }
      }
    }

    let unique = Dictionary(grouping: connections, by: \.id)
      .compactMap { $0.value.first }
      .sorted {
        ($0.projectName, $0.branchName, $0.databaseName)
          < ($1.projectName, $1.branchName, $1.databaseName)
      }
    return NeonCLIScanReport(connections: unique, skippedResources: skippedResources)
  }

  private func runJSON(_ arguments: [String], executableURL: URL) async throws -> Data {
    let data = try await commandRunner.run(
      executableURL: executableURL,
      arguments: arguments + ["--output", "json", "--no-color", "--no-analytics"] + globalArguments
    )
    guard data.count <= Self.maximumOutputBytes else {
      throw NeonCLIScannerError.outputTooLarge
    }
    return data
  }

  private static let maximumOutputBytes = 5 * 1_024 * 1_024

  static func findExecutable(
    fileManager: FileManager,
    environment: [String: String],
    home: URL
  ) -> URL? {
    var candidates = [
      "/opt/homebrew/bin/neon",
      "/opt/homebrew/bin/neonctl",
      "/usr/local/bin/neon",
      "/usr/local/bin/neonctl",
    ]
    // Apps opened from the Dock get a minimal PATH, so also look where Node version managers
    // and npm install global tools. Newest nvm Node version first.
    var directories = environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []
    let nvmVersions = home.appendingPathComponent(".nvm/versions/node")
    let installed = (try? fileManager.contentsOfDirectory(atPath: nvmVersions.path)) ?? []
    directories += installed
      .sorted { $0.compare($1, options: .numeric) == .orderedDescending }
      .map { nvmVersions.appendingPathComponent($0).appendingPathComponent("bin").path }
    directories += [".volta/bin", ".npm-global/bin", ".local/bin", ".bun/bin"]
      .map { home.appendingPathComponent($0).path }
    for directory in directories where directory.hasPrefix("/") {
      candidates.append("\(directory)/neon")
      candidates.append("\(directory)/neonctl")
    }

    var seen: Set<String> = []
    for path in candidates where seen.insert(path).inserted {
      guard fileManager.isExecutableFile(atPath: path) else { continue }
      let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
      var isDirectory: ObjCBool = false
      guard fileManager.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
        !isDirectory.boolValue
      else { continue }
      return resolved
    }
    return nil
  }

  private static func decodeProjects(_ data: Data) throws -> [Project] {
    let decoder = JSONDecoder()
    if let projects = try? decoder.decode([Project].self, from: data) {
      return projects
    }
    do {
      let envelope = try decoder.decode(ProjectEnvelope.self, from: data)
      return envelope.projects + envelope.sharedWithYou
    } catch {
      throw NeonCLIScannerError.invalidResponse
    }
  }

  private static func decodeArray<T: Decodable>(_ data: Data) throws -> [T] {
    do {
      return try JSONDecoder().decode([T].self, from: data)
    } catch {
      throw NeonCLIScannerError.invalidResponse
    }
  }

  private struct Organization: Decodable {
    let id: String
  }

  private struct ProjectEnvelope: Decodable {
    let projects: [Project]
    let sharedWithYou: [Project]

    enum CodingKeys: String, CodingKey {
      case projects
      case sharedWithYou = "shared_with_you"
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      projects = try container.decodeIfPresent([Project].self, forKey: .projects) ?? []
      sharedWithYou = try container.decodeIfPresent([Project].self, forKey: .sharedWithYou) ?? []
    }
  }

  private struct Project: Decodable {
    let id: String
    let name: String
  }

  private struct Branch: Decodable {
    let id: String
    let name: String
  }

  private struct Database: Decodable {
    let name: String
    let ownerName: String?

    enum CodingKeys: String, CodingKey {
      case name
      case ownerName = "owner_name"
    }
  }
}

public struct FoundationNeonCLICommandRunner: NeonCLICommandRunning, Sendable {
  private let timeout: TimeInterval

  public init(timeout: TimeInterval = 60) {
    self.timeout = timeout
  }

  public func run(executableURL: URL, arguments: [String]) async throws -> Data {
    let process = Process()
    process.executableURL = executableURL
    process.arguments = arguments
    var environment = ProcessInfo.processInfo.environment
    environment["CI"] = "1"
    environment["NO_COLOR"] = "1"
    environment["PATH"] = Self.searchPath(
      for: executableURL, inherited: environment["PATH"], fileManager: .default)
    process.environment = environment

    let invocation = CLIInvocation(process: process, timeout: timeout)
    return try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        invocation.start(continuation)
      }
    } onCancel: {
      invocation.cancel()
    }
  }

  /// The PATH the CLI runs with. The Neon CLI is a Node.js program started through
  /// `#!/usr/bin/env node`, and apps opened from the Dock inherit only the system PATH, so
  /// `node` from Homebrew or nvm is not found ("env: node: No such file or directory").
  /// Adds any Node installation beside the CLI (as nvm and Volta lay them out), then the
  /// Homebrew prefixes, ahead of the inherited PATH.
  static func searchPath(for executableURL: URL, inherited: String?, fileManager: FileManager) -> String {
    var directories: [String] = []
    var ancestor = executableURL.deletingLastPathComponent()
    while ancestor.path != "/" {
      let bin = ancestor.appendingPathComponent("bin")
      if fileManager.isExecutableFile(atPath: bin.appendingPathComponent("node").path) {
        directories.append(bin.path)
        break
      }
      ancestor.deleteLastPathComponent()
    }
    directories.append(executableURL.deletingLastPathComponent().path)
    directories += ["/opt/homebrew/bin", "/usr/local/bin"]
    directories += (inherited ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":").map(String.init)
    var seen: Set<String> = []
    return directories.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
  }
}

/// One run of the Neon CLI, driven entirely by callbacks so that no thread waits on it.
///
/// An earlier version blocked a Swift concurrency thread until the CLI exited, waiting on a
/// reader it had queued at user-initiated priority. Once every pool thread was blocked that way,
/// macOS never started the readers, so nothing ever finished. On a three-core CI runner three
/// scans were enough to freeze the whole test process.
///
/// Both pipes are read as data arrives, because reading them one after the other deadlocks once
/// the CLI fills a pipe's buffer. The run settles once the CLI exited and both pipes reached end
/// of file, when the deadline passes or when the calling task is cancelled, whichever comes first.
private final class CLIInvocation: @unchecked Sendable {
  /// How long to wait for the pipes to close after the CLI exits. A process the CLI left behind
  /// can keep them open long after it is gone.
  private static let drainGrace: TimeInterval = 2

  private let process: Process
  private let timeout: TimeInterval
  private let standardOutput = Pipe()
  private let standardError = Pipe()

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Data, any Error>?
  private var output = Data()
  private var errorOutput = Data()
  private var outputClosed = false
  private var errorClosed = false
  private var exited = false
  private var settled = false

  init(process: Process, timeout: TimeInterval) {
    self.process = process
    self.timeout = timeout
  }

  func start(_ continuation: CheckedContinuation<Data, any Error>) {
    lock.lock()
    guard !settled else {
      lock.unlock()
      continuation.resume(throwing: CancellationError())
      return
    }
    self.continuation = continuation
    lock.unlock()

    process.standardOutput = standardOutput
    process.standardError = standardError
    standardOutput.fileHandleForReading.readabilityHandler = { [self] handle in
      received(handle.availableData, onErrorStream: false)
    }
    standardError.fileHandleForReading.readabilityHandler = { [self] handle in
      received(handle.availableData, onErrorStream: true)
    }
    process.terminationHandler = { [self] _ in exitedNow() }

    do {
      try process.run()
    } catch {
      settle(.failure(NeonCLIScannerError.launchFailed))
      return
    }
    // Cancellation can land while the CLI is starting, before there was anything to stop.
    if isSettled, process.isRunning { process.terminate() }

    // A CLI waiting on an interactive sign-in would otherwise hold the scan forever.
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
      stop(because: NeonCLIScannerError.timedOut(seconds: Int(timeout)))
    }
  }

  func cancel() {
    stop(because: CancellationError())
  }

  private var isSettled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return settled
  }

  private func stop(because error: any Error) {
    guard settle(.failure(error)) else { return }
    if process.isRunning { process.terminate() }
  }

  private func received(_ chunk: Data, onErrorStream: Bool) {
    lock.lock()
    if chunk.isEmpty {
      if onErrorStream { errorClosed = true } else { outputClosed = true }
    } else if onErrorStream {
      errorOutput.append(chunk)
    } else {
      output.append(chunk)
    }
    lock.unlock()
    if chunk.isEmpty {
      (onErrorStream ? standardError : standardOutput).fileHandleForReading.readabilityHandler = nil
      finishIfDone()
    }
  }

  private func exitedNow() {
    lock.lock()
    exited = true
    lock.unlock()
    finishIfDone()
    DispatchQueue.global().asyncAfter(deadline: .now() + Self.drainGrace) { [self] in
      finishIfDone(evenWithOpenPipes: true)
    }
  }

  private func finishIfDone(evenWithOpenPipes: Bool = false) {
    lock.lock()
    guard exited, evenWithOpenPipes || (outputClosed && errorClosed), !settled else {
      lock.unlock()
      return
    }
    let output = self.output
    let errorOutput = self.errorOutput
    lock.unlock()

    let status = process.terminationStatus
    guard status == 0 else {
      let rawMessage = String(data: errorOutput.prefix(8_192), encoding: .utf8) ?? ""
      settle(.failure(NeonCLIScannerError.classify(
        errorOutput: ErrorRedaction.redactCredentials(in: rawMessage),
        status: status
      )))
      return
    }
    settle(.success(output))
  }

  /// Resumes the caller once. Returns true when this call settled the run.
  @discardableResult
  private func settle(_ result: Result<Data, any Error>) -> Bool {
    lock.lock()
    guard !settled else {
      lock.unlock()
      return false
    }
    settled = true
    let continuation = self.continuation
    self.continuation = nil
    lock.unlock()

    standardOutput.fileHandleForReading.readabilityHandler = nil
    standardError.fileHandleForReading.readabilityHandler = nil
    continuation?.resume(with: result)
    return true
  }
}

public enum NeonCLIScannerError: Error, Sendable, Equatable, LocalizedError {
  case notInstalled
  case launchFailed
  case nodeMissing
  /// `signIn` is the command the CLI itself recommends, such as `neon login --profile DEFAULT`.
  case notSignedIn(signIn: String)
  case sessionExpired(signIn: String)
  case configFolderUnusable(path: String, signIn: String)
  case offline
  case rateLimited
  case timedOut(seconds: Int)
  case commandFailed(String)
  case invalidResponse
  case outputTooLarge

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      "The Neon CLI is not installed."
    case .launchFailed:
      "LithePG could not start the installed Neon CLI."
    case .nodeMissing:
      "The Neon CLI needs Node.js, and LithePG could not find it. Install Node.js, for example with “brew install node”, then scan again."
    case .notSignedIn(let signIn):
      "The Neon CLI is not signed in. Run “\(signIn)” in Terminal, then scan again."
    case .sessionExpired(let signIn):
      "Your Neon CLI sign-in has expired. Run “\(signIn)” in Terminal to sign in again, then scan again."
    case .configFolderUnusable(let path, let signIn):
      "The Neon CLI could not use its settings folder (\(path)). Run “\(signIn)” in Terminal to set it up again, then scan again."
    case .offline:
      "LithePG could not reach Neon. Check your internet connection, then scan again."
    case .rateLimited:
      "Neon is limiting requests right now. Wait a minute, then scan again."
    case .timedOut(let seconds):
      "The Neon CLI did not finish within \(seconds) seconds. If it is waiting for a sign-in, run “neon login” in Terminal first, then scan again."
    case .commandFailed(let message):
      "The Neon CLI reported an error: \(message)"
    case .invalidResponse:
      "The Neon CLI did not return usable data. Run “neon login” in Terminal, confirm your account, then scan again."
    case .outputTooLarge:
      "The Neon CLI returned more data than LithePG can safely import."
    }
  }

  /// A Terminal command that fixes the problem, offered as a copy button.
  public var suggestedCommand: String? {
    switch self {
    case .notSignedIn(let signIn), .sessionExpired(let signIn), .configFolderUnusable(_, let signIn):
      signIn
    case .nodeMissing:
      "brew install node"
    case .timedOut, .invalidResponse:
      "neon login"
    default:
      nil
    }
  }

  /// Failures that would hit every remaining command too. These end the scan with their
  /// explanation instead of being counted as skipped resources one by one.
  var stopsScan: Bool {
    switch self {
    case .nodeMissing, .notSignedIn, .sessionExpired, .configFolderUnusable, .offline,
      .rateLimited, .timedOut, .launchFailed:
      true
    default:
      false
    }
  }

  /// Turns the CLI's error output into an explanation with a next step. Unrecognized output
  /// keeps its first meaningful line, without the CLI's "ERROR:" prefix.
  static func classify(errorOutput: String, status: Int32) -> NeonCLIScannerError {
    let text = errorOutput.lowercased()
    func has(_ needles: String...) -> Bool { needles.contains { text.contains($0) } }

    if has("env: node", "env: 'node'", "node: no such file", "command not found: node") || status == 127 {
      return .nodeMissing
    }
    let signIn = Self.signInCommand(in: errorOutput)
    if has("invalid_grant", "rejected the stored session", "refresh token", "session expired", "token has expired") {
      return .sessionExpired(signIn: signIn)
    }
    if has("enoent", "eacces", "eperm"), has(".config/neon") {
      return .configFolderUnusable(
        path: Self.configFolder(in: errorOutput) ?? "~/.config/neon", signIn: signIn)
    }
    if has("not authenticated", "unauthorized", "401", "no credentials", "please authenticate",
      "neon auth", "neon login", "sign in again")
    {
      return .notSignedIn(signIn: signIn)
    }
    if has("enotfound", "econnrefused", "etimedout", "eai_again", "econnreset", "fetch failed", "socket hang up", "network") {
      return .offline
    }
    if has("429", "rate limit", "too many requests") {
      return .rateLimited
    }
    let line = errorOutput
      .split(whereSeparator: \.isNewline)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .first { !$0.isEmpty }
      .map { $0.hasPrefix("ERROR:") ? String($0.dropFirst(6)).trimmingCharacters(in: .whitespaces) : $0 }
    guard let line, !line.isEmpty else {
      return .commandFailed("it exited with status \(status) without saying why.")
    }
    return .commandFailed(line.count > 240 ? String(line.prefix(240)) + "…" : line)
  }

  /// The sign-in command the CLI recommends ("Run `neon login --profile DEFAULT` to sign in
  /// again"), so the advice matches the installed version. Falls back to `neon login`, the
  /// command in Neon CLI 8 (`neon auth` remains an alias).
  static func signInCommand(in output: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?i)run\s+`((?:neon|neonctl)\b[^`]*)`"#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let range = Range(match.range(at: 1), in: output)
    else { return "neon login" }
    return String(output[range]).trimmingCharacters(in: .whitespaces)
  }

  /// The settings folder named in a file error, with the home folder shortened to `~`.
  private static func configFolder(in output: String) -> String? {
    guard let regex = try? NSRegularExpression(pattern: #"'([^']*/\.config/neon[^/']*)/?[^']*'"#),
      let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
      let range = Range(match.range(at: 1), in: output)
    else { return nil }
    let folder = String(output[range])
    let home = NSHomeDirectory()
    return folder.hasPrefix(home) ? "~" + folder.dropFirst(home.count) : folder
  }
}
