import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Describes whether Apple's lightweight on-device system language model can
/// accept a query-drafting request.
public enum OnDeviceAIModelAvailability: Sendable, Equatable {
  case available
  case appleIntelligenceNotEnabled
  case modelNotReady
  case deviceNotEligible
  case unsupportedSystem
  case temporarilyUnavailable
}

public struct OnDeviceAIQueryService: AIQueryService {
  private let availabilityOverride: OnDeviceAIModelAvailability?

  public init() {
    availabilityOverride = nil
  }

  init(modelAvailability: OnDeviceAIModelAvailability) {
    availabilityOverride = modelAvailability
  }

  public static func modelAvailability() -> OnDeviceAIModelAvailability {
    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        switch SystemLanguageModel.default.availability {
        case .available:
          return .available
        case .unavailable(let reason):
          switch reason {
          case .appleIntelligenceNotEnabled:
            return .appleIntelligenceNotEnabled
          case .modelNotReady:
            return .modelNotReady
          case .deviceNotEligible:
            return .deviceNotEligible
          @unknown default:
            return .temporarilyUnavailable
          }
        }
      }
    #endif
    return .unsupportedSystem
  }

  public func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft {
    let availability = availabilityOverride ?? Self.modelAvailability()
    guard availability == .available else {
      return Self.unavailableDraft(for: availability)
    }

    #if canImport(FoundationModels)
      if #available(macOS 26.0, *) {
        return try await Self.systemModelDraft(
          for: request,
          model: SystemLanguageModel.default
        )
      }
    #endif
    return Self.unavailableDraft(for: .unsupportedSystem)
  }

  private static func unavailableDraft(
    for availability: OnDeviceAIModelAvailability
  ) -> AIQueryDraft {
    let explanation =
      switch availability {
      case .available:
        "Apple's on-device model could not start. Try again."
      case .appleIntelligenceNotEnabled:
        "Enable Apple Intelligence in System Settings to draft SQL."
      case .modelNotReady:
        "Apple's on-device model is still being prepared. Try again after setup finishes."
      case .deviceNotEligible:
        "Apple's on-device model is not available on this Mac."
      case .unsupportedSystem:
        "Apple's on-device model requires macOS 26 or later."
      case .temporarilyUnavailable:
        "Apple's on-device model is temporarily unavailable. Try again later."
      }

    return AIQueryDraft(
      sql: "",
      explanation: explanation,
      referencedObjects: [],
      status: .needsModel,
      confidence: 0
    )
  }
}

#if canImport(FoundationModels)
  @available(macOS 26.0, *)
  @Generable(description: "A safe PostgreSQL query draft based only on the supplied schema")
  private struct GeneratedSQLDraft {
    @Guide(description: "Whether the request can be answered using only the supplied schema")
    var canAnswer: Bool

    @Guide(
      description:
        "Exactly one read-only PostgreSQL SELECT statement, without Markdown fences; empty when canAnswer is false"
    )
    var sql: String

    @Guide(description: "One short explanation of what the query does or why it cannot be produced")
    var explanation: String

    @Guide(
      description:
        "Every schema.table relation used by the query, written exactly as it appears in the supplied schema"
    )
    var referencedObjects: [String]
  }

  @available(macOS 26.0, *)
  extension OnDeviceAIQueryService {
    fileprivate static func systemModelDraft(
      for request: AIQueryRequest,
      model: SystemLanguageModel
    ) async throws -> AIQueryDraft {
      let context = try AIQueryContextBuilder.build(
        prompt: request.prompt,
        schemaIndex: request.schemaIndex
      )
      guard context.privacyReceipt.localOnly,
        !context.privacyReceipt.networkCallsAllowed,
        !context.privacyReceipt.includesCredentials,
        !context.privacyReceipt.includesRawConnectionURLs,
        !context.privacyReceipt.includesResultRows
      else {
        return rejected(
          "LithePG blocked model context that did not satisfy its local-only privacy rules.")
      }

      let session = LanguageModelSession(
        model: model,
        instructions: """
          You are LithePG's PostgreSQL query planner. Convert a user's request into one accurate, read-only query.

          Rules:
          - Use only schemas, relations, columns, and foreign-key relationships present in the supplied schema.
          - Produce exactly one SELECT statement. A WITH clause is allowed only when every CTE is read-only.
          - Never produce INSERT, UPDATE, DELETE, MERGE, COPY, DDL, administrative commands, or SELECT INTO.
          - Fully qualify base relations as "schema"."relation" and quote PostgreSQL identifiers.
          - Preserve requested filters, joins, aggregates, grouping, ordering, and limits.
          - Prefer explicit projected columns over SELECT * when the request names columns or concepts.
          - Do not invent identifiers. If the schema is insufficient or the request is ambiguous, set canAnswer to false and leave sql empty.
          - Return SQL as plain text without Markdown fences or commentary inside the SQL.
          """
      )
      let response = try await session.respond(
        to: """
          User request:
          \(context.prompt)

          Available PostgreSQL schema:
          \(compactSchemaContext(for: request))
          """,
        generating: GeneratedSQLDraft.self,
        options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 800)
      )
      let generated = response.content
      guard generated.canAnswer else {
        return needsModel(
          generated.explanation.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
            ?? "The on-device model could not answer this request from the available schema."
        )
      }
      guard let sql = AIQuerySQLSafety.normalizedReadOnlyStatement(generated.sql) else {
        return rejected(
          "The on-device model produced SQL that failed LithePG's read-only safety checks.")
      }

      let knownRelations = Set(
        request.schemaIndex.documents
          .filter { $0.kind == .relation }
          .map { $0.title.lowercased() }
      )
      let referencedObjects = generated.referencedObjects
        .map(Self.normalizedRelationName)
        .filter { knownRelations.contains($0.lowercased()) }
        .uniqued()
      guard !referencedObjects.isEmpty,
        referencedObjects.count == generated.referencedObjects.count
      else {
        return rejected(
          "The on-device model referenced a relation that is not in the loaded schema.")
      }

      let explanation =
        generated.explanation
        .trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
        ?? "Query drafted from the loaded schema."
      return AIQueryDraft(
        sql: sql,
        explanation: "Apple on-device model: \(explanation)",
        referencedObjects: referencedObjects,
        status: .ready,
        confidence: 0.85
      )
    }

    fileprivate static func compactSchemaContext(for request: AIQueryRequest) -> String {
      let rankedIDs = request.schemaIndex.search(request.prompt, limit: 24).map(\.id)
      let usefulDocuments = request.schemaIndex.documents.filter {
        $0.kind == .relation || $0.kind == .relationship
      }
      let rankedDocuments = rankedIDs.compactMap { id in
        usefulDocuments.first { $0.id == id }
      }
      let orderedDocuments = (rankedDocuments + usefulDocuments).uniqued(by: \.id)

      let maximumCharacters = 9_000
      var lines: [String] = []
      var characterCount = 0
      for document in orderedDocuments {
        let line = "- \(document.title): \(document.body)"
        guard characterCount + line.count <= maximumCharacters else { continue }
        lines.append(line)
        characterCount += line.count + 1
      }
      return lines.joined(separator: "\n")
    }

    fileprivate static func normalizedRelationName(_ raw: String) -> String {
      raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "\".\"", with: ".")
        .replacingOccurrences(of: "\"", with: "")
    }

    fileprivate static func needsModel(_ explanation: String) -> AIQueryDraft {
      AIQueryDraft(
        sql: "",
        explanation: explanation,
        referencedObjects: [],
        status: .needsModel,
        confidence: 0
      )
    }

    fileprivate static func rejected(_ explanation: String) -> AIQueryDraft {
      AIQueryDraft(
        sql: "",
        explanation: explanation,
        referencedObjects: [],
        status: .rejected,
        confidence: 0
      )
    }
  }
#endif

enum AIQuerySQLSafety {
  private static let forbiddenTokens: Set<String> = [
    "alter", "analyze", "call", "cluster", "comment", "copy", "create", "deallocate",
    "delete", "do", "drop", "execute", "grant", "insert", "into", "listen", "load",
    "lock", "merge", "notify", "prepare", "reassign", "refresh", "reindex", "reset",
    "revoke", "security", "set", "truncate", "unlisten", "update", "vacuum",
  ]

  static func normalizedReadOnlyStatement(_ raw: String) -> String? {
    let sql = stripMarkdownFence(raw).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sql.isEmpty, sql.utf8.count <= 100_000,
      let scan = scan(sql),
      scan.tokens.first == "select" || scan.tokens.first == "with",
      scan.tokens.contains("select"),
      scan.tokens.allSatisfy({ !forbiddenTokens.contains($0) }),
      !containsLockingClause(scan.tokens)
    else { return nil }

    if scan.semicolonOffsets.count > 1 { return nil }
    if let semicolonOffset = scan.semicolonOffsets.first,
      semicolonOffset != sql.utf8.count - 1
    {
      return nil
    }
    return sql.hasSuffix(";") ? sql : sql + ";"
  }

  private static func stripMarkdownFence(_ raw: String) -> String {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }
    let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
    guard lines.count >= 3, lines.last?.trimmingCharacters(in: .whitespaces) == "```" else {
      return trimmed
    }
    return lines.dropFirst().dropLast().joined(separator: "\n")
  }

  private static func containsLockingClause(_ tokens: [String]) -> Bool {
    for index in tokens.indices where tokens[index] == "for" {
      guard index + 1 < tokens.count else { continue }
      if tokens[index + 1] == "update" || tokens[index + 1] == "share" {
        return true
      }
      if index + 2 < tokens.count,
        tokens[index + 1] == "no" || tokens[index + 1] == "key",
        tokens[index + 2] == "key" || tokens[index + 2] == "share"
      {
        return true
      }
    }
    return false
  }

  private struct ScanResult {
    let tokens: [String]
    let semicolonOffsets: [Int]
  }

  private static func scan(_ sql: String) -> ScanResult? {
    let bytes = Array(sql.utf8)
    var tokens: [String] = []
    var semicolonOffsets: [Int] = []
    var index = 0

    while index < bytes.count {
      let byte = bytes[index]
      if isIdentifierStart(byte) {
        let start = index
        index += 1
        while index < bytes.count, isIdentifierContinuation(bytes[index]) { index += 1 }
        tokens.append(String(decoding: bytes[start..<index], as: UTF8.self).lowercased())
        continue
      }
      if byte == 0x27 {
        guard let end = consumeQuoted(bytes, from: index, quote: 0x27) else { return nil }
        index = end
        continue
      }
      if byte == 0x22 {
        guard let end = consumeQuoted(bytes, from: index, quote: 0x22) else { return nil }
        index = end
        continue
      }
      if byte == 0x2D, index + 1 < bytes.count, bytes[index + 1] == 0x2D {
        index += 2
        while index < bytes.count, bytes[index] != 0x0A { index += 1 }
        continue
      }
      if byte == 0x2F, index + 1 < bytes.count, bytes[index + 1] == 0x2A {
        guard let end = consumeBlockComment(bytes, from: index) else { return nil }
        index = end
        continue
      }
      if byte == 0x24, let delimiter = dollarQuoteDelimiter(bytes, at: index) {
        guard let end = consumeDollarQuote(bytes, from: index, delimiter: delimiter) else {
          return nil
        }
        index = end
        continue
      }
      if byte == 0x3B { semicolonOffsets.append(index) }
      index += 1
    }
    return ScanResult(tokens: tokens, semicolonOffsets: semicolonOffsets)
  }

  private static func consumeQuoted(_ bytes: [UInt8], from start: Int, quote: UInt8) -> Int? {
    var index = start + 1
    while index < bytes.count {
      guard bytes[index] == quote else {
        index += 1
        continue
      }
      if index + 1 < bytes.count, bytes[index + 1] == quote {
        index += 2
      } else {
        return index + 1
      }
    }
    return nil
  }

  private static func consumeBlockComment(_ bytes: [UInt8], from start: Int) -> Int? {
    var index = start + 2
    var depth = 1
    while index + 1 < bytes.count {
      if bytes[index] == 0x2F, bytes[index + 1] == 0x2A {
        depth += 1
        index += 2
      } else if bytes[index] == 0x2A, bytes[index + 1] == 0x2F {
        depth -= 1
        index += 2
        if depth == 0 { return index }
      } else {
        index += 1
      }
    }
    return nil
  }

  private static func dollarQuoteDelimiter(_ bytes: [UInt8], at start: Int) -> [UInt8]? {
    var index = start + 1
    while index < bytes.count, isIdentifierContinuation(bytes[index]) { index += 1 }
    guard index < bytes.count, bytes[index] == 0x24 else { return nil }
    return Array(bytes[start...index])
  }

  private static func consumeDollarQuote(
    _ bytes: [UInt8],
    from start: Int,
    delimiter: [UInt8]
  ) -> Int? {
    var index = start + delimiter.count
    while index + delimiter.count <= bytes.count {
      if Array(bytes[index..<(index + delimiter.count)]) == delimiter {
        return index + delimiter.count
      }
      index += 1
    }
    return nil
  }

  private static func isIdentifierStart(_ byte: UInt8) -> Bool {
    byte == 0x5F || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte)
  }

  private static func isIdentifierContinuation(_ byte: UInt8) -> Bool {
    isIdentifierStart(byte) || (0x30...0x39).contains(byte) || byte == 0x24
  }
}

extension String {
  fileprivate var nilIfBlank: String? {
    isEmpty ? nil : self
  }
}

extension Array where Element: Hashable {
  fileprivate func uniqued() -> [Element] {
    var seen: Set<Element> = []
    return filter { seen.insert($0).inserted }
  }
}

extension Array {
  fileprivate func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
    var seen: Set<Key> = []
    return filter { seen.insert($0[keyPath: keyPath]).inserted }
  }
}
