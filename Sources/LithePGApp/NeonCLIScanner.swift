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

  public init(
    fileManager: FileManager = .default,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    executableURL = Self.findExecutable(fileManager: fileManager, environment: environment)
    version = nil
    commandRunner = FoundationNeonCLICommandRunner()
  }

  init(
    executableURL: URL,
    version: String? = nil,
    commandRunner: any NeonCLICommandRunning
  ) {
    self.executableURL = executableURL
    self.version = version
    self.commandRunner = commandRunner
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
              arguments: arguments
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
      arguments: arguments + ["--output", "json", "--no-color", "--no-analytics"]
    )
    guard data.count <= Self.maximumOutputBytes else {
      throw NeonCLIScannerError.outputTooLarge
    }
    return data
  }

  private static let maximumOutputBytes = 5 * 1_024 * 1_024

  private static func findExecutable(
    fileManager: FileManager,
    environment: [String: String]
  ) -> URL? {
    var candidates = [
      "/opt/homebrew/bin/neon",
      "/opt/homebrew/bin/neonctl",
      "/usr/local/bin/neon",
      "/usr/local/bin/neonctl",
    ]
    if let path = environment["PATH"] {
      for directory in path.split(separator: ":").map(String.init) where directory.hasPrefix("/") {
        candidates.append("\(directory)/neon")
        candidates.append("\(directory)/neonctl")
      }
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
  public init() {}

  public func run(executableURL: URL, arguments: [String]) async throws -> Data {
    try await Task.detached(priority: .userInitiated) {
      let process = Process()
      let standardOutput = Pipe()
      let standardError = Pipe()
      process.executableURL = executableURL
      process.arguments = arguments
      process.standardOutput = standardOutput
      process.standardError = standardError
      var environment = ProcessInfo.processInfo.environment
      environment["CI"] = "1"
      environment["NO_COLOR"] = "1"
      process.environment = environment

      do {
        try process.run()
      } catch {
        throw NeonCLIScannerError.launchFailed
      }
      let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
      let errorOutput = standardError.fileHandleForReading.readDataToEndOfFile()
      process.waitUntilExit()
      guard process.terminationStatus == 0 else {
        let rawMessage = String(data: errorOutput.prefix(4_096), encoding: .utf8)
          ?? "Neon CLI exited with status \(process.terminationStatus)."
        throw NeonCLIScannerError.commandFailed(
          ErrorRedaction.redactCredentials(in: rawMessage)
        )
      }
      return output
    }.value
  }
}

public enum NeonCLIScannerError: Error, Sendable, LocalizedError {
  case notInstalled
  case launchFailed
  case commandFailed(String)
  case invalidResponse
  case outputTooLarge

  public var errorDescription: String? {
    switch self {
    case .notInstalled:
      "Neon CLI is not installed."
    case .launchFailed:
      "LithePG could not launch the installed Neon CLI."
    case .commandFailed(let message):
      message.trimmingCharacters(in: .whitespacesAndNewlines)
    case .invalidResponse:
      "Neon CLI did not return usable JSON. Run `neon auth` in Terminal, confirm your account, then try again."
    case .outputTooLarge:
      "Neon CLI returned more data than LithePG can safely import."
    }
  }
}
