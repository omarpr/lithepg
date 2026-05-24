import Foundation

public struct AIQueryPrivacyReceipt: Sendable, Equatable {
  public let localOnly: Bool
  public let networkCallsAllowed: Bool
  public let includesCredentials: Bool
  public let includesRawConnectionURLs: Bool
  public let includesResultRows: Bool
  public let modelArtifactsBundled: Bool
  public let requiresGeneratedSQLReview: Bool

  public init(
    localOnly: Bool = true,
    networkCallsAllowed: Bool = false,
    includesCredentials: Bool = false,
    includesRawConnectionURLs: Bool = false,
    includesResultRows: Bool = false,
    modelArtifactsBundled: Bool = false,
    requiresGeneratedSQLReview: Bool = true
  ) {
    self.localOnly = localOnly
    self.networkCallsAllowed = networkCallsAllowed
    self.includesCredentials = includesCredentials
    self.includesRawConnectionURLs = includesRawConnectionURLs
    self.includesResultRows = includesResultRows
    self.modelArtifactsBundled = modelArtifactsBundled
    self.requiresGeneratedSQLReview = requiresGeneratedSQLReview
  }
}

public struct AIQueryContext: Sendable, Equatable {
  public let prompt: String
  public let schemaDocuments: [SchemaDocument]
  public let privacyReceipt: AIQueryPrivacyReceipt

  public init(
    prompt: String,
    schemaDocuments: [SchemaDocument],
    privacyReceipt: AIQueryPrivacyReceipt = AIQueryPrivacyReceipt()
  ) {
    self.prompt = prompt
    self.schemaDocuments = schemaDocuments
    self.privacyReceipt = privacyReceipt
  }

  public var serializedPromptContext: String {
    var lines = [
      "Local-only NL2SQL context",
      "User request: \(prompt)",
      "Schema documents:",
    ]
    lines.append(contentsOf: schemaDocuments.map { "- [\($0.kind)] \($0.title): \($0.body)" })
    lines.append("Privacy receipt: localOnly=\(privacyReceipt.localOnly); networkCallsAllowed=\(privacyReceipt.networkCallsAllowed); includesCredentials=\(privacyReceipt.includesCredentials); includesRawConnectionURLs=\(privacyReceipt.includesRawConnectionURLs); includesResultRows=\(privacyReceipt.includesResultRows); modelArtifactsBundled=\(privacyReceipt.modelArtifactsBundled); requiresGeneratedSQLReview=\(privacyReceipt.requiresGeneratedSQLReview)")
    return lines.joined(separator: "\n")
  }
}

public enum AIQueryContextBuilder {
  public static func build(
    prompt: String,
    schemaIndex: SchemaIndex,
    rawConnectionURL: String? = nil,
    latestResult: QueryResult? = nil
  ) throws -> AIQueryContext {
    let request = try AIQueryRequest(
      prompt: ErrorRedaction.redactCredentials(in: prompt),
      schemaIndex: schemaIndex
    )

    _ = rawConnectionURL
    _ = latestResult

    return AIQueryContext(
      prompt: request.prompt,
      schemaDocuments: request.schemaIndex.documents,
      privacyReceipt: AIQueryPrivacyReceipt()
    )
  }
}
