import Foundation

public struct LocalModelRegistry {
  public enum Availability: Sendable, Equatable {
    case unavailable(expectedDirectory: URL)
    case available(URL)
    case missing(URL)
  }

  public let applicationSupportDirectory: URL
  public let configuredModelPath: String?
  public let fileManager: FileManager

  public init(
    applicationSupportDirectory: URL? = nil,
    configuredModelPath: String? = nil,
    fileManager: FileManager = .default
  ) {
    self.applicationSupportDirectory = applicationSupportDirectory
      ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? fileManager.homeDirectoryForCurrentUser.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    self.configuredModelPath = configuredModelPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    self.fileManager = fileManager
  }

  public var defaultModelDirectory: URL {
    applicationSupportDirectory
      .appending(path: "LithePG", directoryHint: .isDirectory)
      .appending(path: "Models", directoryHint: .isDirectory)
      .standardizedFileURL
  }

  public func availability() -> Availability {
    guard let configuredModelPath else {
      return .unavailable(expectedDirectory: defaultModelDirectory)
    }

    let url = URL(fileURLWithPath: configuredModelPath).standardizedFileURL
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
      return .available(url)
    }
    return .missing(url)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
