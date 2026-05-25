import Foundation
#if canImport(CoreML)
import CoreML
#endif

public struct LocalModelAIQueryService: AIQueryService {
  public enum Runtime: String, Sendable, Equatable {
    case coreML = "CoreML"
  }

  public struct AdapterDecision: Sendable, Equatable {
    public let runtime: Runtime
    public let requiresPackageDependency: Bool
    public let bundlesModelArtifacts: Bool
    public let rationale: String

    public init(
      runtime: Runtime,
      requiresPackageDependency: Bool,
      bundlesModelArtifacts: Bool,
      rationale: String
    ) {
      self.runtime = runtime
      self.requiresPackageDependency = requiresPackageDependency
      self.bundlesModelArtifacts = bundlesModelArtifacts
      self.rationale = rationale
    }
  }

  public struct Configuration: Sendable, Equatable {
    public static let enableEnvironmentKey = "LITHEPG_ENABLE_LOCAL_MODEL"
    public static let modelPathEnvironmentKey = "LITHEPG_LOCAL_MODEL_PATH"

    public let runtime: Runtime
    public let isEnabled: Bool
    public let configuredModelPath: String?

    public init(
      runtime: Runtime = .coreML,
      isEnabled: Bool = false,
      configuredModelPath: String? = nil
    ) {
      self.runtime = runtime
      self.isEnabled = isEnabled
      self.configuredModelPath = configuredModelPath?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    public static func environment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
      Self(
        runtime: .coreML,
        isEnabled: environment[enableEnvironmentKey] == "1",
        configuredModelPath: environment[modelPathEnvironmentKey]
      )
    }
  }

  public static let adapterDecision = AdapterDecision(
    runtime: .coreML,
    requiresPackageDependency: false,
    bundlesModelArtifacts: false,
    rationale: "CoreML is available from the macOS SDK and avoids adding an MLX Swift package dependency; model artifacts remain user-provided and external to the app binary."
  )

  private let registry: LocalModelRegistry
  private let configuration: Configuration

  public init(
    registry: LocalModelRegistry,
    configuration: Configuration = Configuration()
  ) {
    self.registry = registry
    self.configuration = configuration
  }

  public init(
    applicationSupportDirectory: URL? = nil,
    environment: [String: String] = ProcessInfo.processInfo.environment,
    fileManager: FileManager = .default
  ) {
    let configuration = Configuration.environment(environment)
    self.init(
      registry: LocalModelRegistry(
        applicationSupportDirectory: applicationSupportDirectory,
        configuredModelPath: configuration.configuredModelPath,
        fileManager: fileManager
      ),
      configuration: configuration
    )
  }

  public func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft {
    let context = try AIQueryContextBuilder.build(
      prompt: request.prompt,
      schemaIndex: request.schemaIndex
    )

    guard context.privacyReceipt.localOnly,
          context.privacyReceipt.networkCallsAllowed == false,
          context.privacyReceipt.modelArtifactsBundled == false else {
      return Self.rejected("Local model context violated LithePG's local-only AI privacy receipt.")
    }

    guard configuration.isEnabled else {
      return Self.needsModel(
        "CoreML local model adapter is present but disabled. Set \(Configuration.enableEnvironmentKey)=1 and \(Configuration.modelPathEnvironmentKey) to a user-provided CoreML artifact to run the gated smoke path."
      )
    }

    switch registry.availability() {
    case .unavailable(let expectedDirectory):
      return Self.needsModel(
        "CoreML local model adapter is enabled, but no external model path is configured. Place a user-provided artifact under \(expectedDirectory.path) or set \(Configuration.modelPathEnvironmentKey)."
      )
    case .missing:
      return Self.needsModel(
        "CoreML local model adapter is enabled, but the configured external model artifact is missing. LithePG will not download or create model files."
      )
    case .available(let modelURL):
      return Self.availableModelDraft(for: modelURL)
    }
  }

  private static func availableModelDraft(for modelURL: URL) -> AIQueryDraft {
#if canImport(CoreML)
    do {
      try validateCoreMLArtifact(at: modelURL)
      return needsModel(
        "CoreML artifact loaded from the external model registry, but NL2SQL model I/O mapping is intentionally not implemented in v0.5. Generated SQL remains unavailable until a reviewed local model contract is added."
      )
    } catch {
      return rejected("CoreML rejected the configured external model artifact: \(error.localizedDescription)")
    }
#else
    return needsModel("CoreML is unavailable in this build, so the local model adapter cannot load the configured artifact.")
#endif
  }

#if canImport(CoreML)
  private static func validateCoreMLArtifact(at url: URL) throws {
    switch url.pathExtension.lowercased() {
    case "mlmodel", "mlpackage":
      let compiledURL = try MLModel.compileModel(at: url)
      _ = try MLModel(contentsOf: compiledURL)
    default:
      _ = try MLModel(contentsOf: url)
    }
  }
#endif

  private static func needsModel(_ explanation: String) -> AIQueryDraft {
    AIQueryDraft(
      sql: "",
      explanation: explanation,
      referencedObjects: [],
      status: .needsModel,
      confidence: 0
    )
  }

  private static func rejected(_ explanation: String) -> AIQueryDraft {
    AIQueryDraft(
      sql: "",
      explanation: explanation,
      referencedObjects: [],
      status: .rejected,
      confidence: 0
    )
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
