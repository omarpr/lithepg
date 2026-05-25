import Foundation
import Testing
@testable import LithePGCore

private let localModelSmokePath = ProcessInfo.processInfo.environment["LITHEPG_LOCAL_MODEL_PATH"]
private let localModelSmokeEnabled = ProcessInfo.processInfo.environment["LITHEPG_ENABLE_LOCAL_MODEL"] == "1"

@Suite("LocalModelAIQueryService")
struct LocalModelAIQueryServiceTests {
  @Test("default adapter is CoreML but disabled until a user opts into an external model")
  func defaultAdapterNeedsExternalOptIn() async throws {
    let root = try temporaryDirectory()
    let registry = LocalModelRegistry(applicationSupportDirectory: root)
    let service = LocalModelAIQueryService(registry: registry)

    let draft = try await service.draftSQL(for: request(prompt: "show customers"))

    #expect(LocalModelAIQueryService.adapterDecision.runtime == .coreML)
    #expect(LocalModelAIQueryService.adapterDecision.requiresPackageDependency == false)
    #expect(LocalModelAIQueryService.adapterDecision.bundlesModelArtifacts == false)
    #expect(draft.status == .needsModel)
    #expect(draft.sql.isEmpty)
    #expect(draft.referencedObjects.isEmpty)
    #expect(draft.confidence == 0)
    #expect(draft.explanation.contains("CoreML"))
    #expect(draft.explanation.contains("disabled"))
  }

  @Test("enabled adapter reports a missing external CoreML artifact without downloading it")
  func enabledAdapterReportsMissingArtifact() async throws {
    let root = try temporaryDirectory()
    let missingModel = root.appending(path: "missing.mlpackage")
    let registry = LocalModelRegistry(applicationSupportDirectory: root, configuredModelPath: missingModel.path)
    let service = LocalModelAIQueryService(
      registry: registry,
      configuration: .init(isEnabled: true)
    )

    let draft = try await service.draftSQL(for: request(prompt: "show customers"))

    #expect(draft.status == .needsModel)
    #expect(draft.sql.isEmpty)
    #expect(draft.referencedObjects.isEmpty)
    #expect(draft.explanation.contains("missing"))
    #expect(FileManager.default.fileExists(atPath: missingModel.path) == false)
  }

  @Test("environment configuration gates runtime and model path explicitly")
  func environmentConfigurationGatesRuntimeAndPath() throws {
    let root = try temporaryDirectory()
    let model = root.appending(path: "lithepg-nl2sql.mlpackage")
    let environment = [
      "LITHEPG_ENABLE_LOCAL_MODEL": "1",
      "LITHEPG_LOCAL_MODEL_PATH": model.path,
    ]

    let configured = LocalModelAIQueryService.Configuration.environment(environment)
    let registry = LocalModelRegistry(
      applicationSupportDirectory: root,
      configuredModelPath: configured.configuredModelPath
    )

    #expect(configured.runtime == .coreML)
    #expect(configured.isEnabled == true)
    #expect(configured.configuredModelPath == model.path)
    #expect(registry.availability() == .missing(model.standardizedFileURL))
  }

  @Test(
    "optional CoreML model smoke is gated on env vars",
    .enabled(if: localModelSmokeEnabled && localModelSmokePath != nil)
  )
  func optionalCoreMLModelSmoke() async throws {
    let modelPath = try #require(localModelSmokePath)
    let registry = LocalModelRegistry(configuredModelPath: modelPath)
    let service = LocalModelAIQueryService(
      registry: registry,
      configuration: .init(isEnabled: true)
    )

    let draft = try await service.draftSQL(for: request(prompt: "show customers"))

    #expect([AIQueryDraft.Status.needsModel, .rejected].contains(draft.status))
    #expect(draft.sql.isEmpty)
  }

  private func request(prompt: String) throws -> AIQueryRequest {
    try AIQueryRequest(prompt: prompt, schemaIndex: SchemaIndex(schema: dogfoodSchema))
  }

  private var dogfoodSchema: DatabaseSchema {
    DatabaseSchema(
      schemas: [
        .init(name: "lithepg_demo", relations: [
          .init(schema: "lithepg_demo", name: "customers", kind: .table, columns: [
            .init(name: "id", typeName: "uuid", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
            .init(name: "name", typeName: "text", isNullable: false, ordinalPosition: 2),
          ]),
        ]),
      ]
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "lithepg-local-model-service-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
