import Foundation
import LithePGCore
import Testing

@Suite("LocalModelRegistry")
struct LocalModelRegistryTests {
  @Test("default model directory lives under Application Support")
  func defaultDirectoryUsesApplicationSupport() throws {
    let root = try temporaryDirectory()
    let appSupport = root.appending(path: "Application Support", directoryHint: .isDirectory)
    let registry = LocalModelRegistry(applicationSupportDirectory: appSupport)

    #expect(registry.defaultModelDirectory == appSupport.appending(path: "LithePG/Models", directoryHint: .isDirectory))
    #expect(registry.availability() == .unavailable(expectedDirectory: registry.defaultModelDirectory))
  }

  @Test("configured model path is available when the artifact exists")
  func configuredModelPathAvailable() throws {
    let root = try temporaryDirectory()
    let modelURL = root.appending(path: "lithepg-nl2sql.mlpackage")
    FileManager.default.createFile(atPath: modelURL.path, contents: Data("placeholder".utf8))

    let registry = LocalModelRegistry(
      applicationSupportDirectory: root.appending(path: "AppSupport", directoryHint: .isDirectory),
      configuredModelPath: modelURL.path
    )

    #expect(registry.availability() == .available(modelURL.standardizedFileURL))
  }

  @Test("configured model path reports missing without downloading")
  func configuredModelPathMissing() throws {
    let root = try temporaryDirectory()
    let missingURL = root.appending(path: "missing.mlpackage")
    let registry = LocalModelRegistry(
      applicationSupportDirectory: root.appending(path: "AppSupport", directoryHint: .isDirectory),
      configuredModelPath: "  \(missingURL.path)  "
    )

    #expect(registry.availability() == .missing(missingURL.standardizedFileURL))
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "lithepg-local-model-registry-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
