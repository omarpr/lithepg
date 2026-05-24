import Foundation

public struct AIQueryRequest: Sendable, Equatable {
    public let prompt: String
    public let schemaIndex: SchemaIndex

    public init(prompt: String, schemaIndex: SchemaIndex) throws {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw AIQueryValidationError.emptyPrompt
        }
        guard !schemaIndex.documents.isEmpty else {
            throw AIQueryValidationError.missingSchema
        }

        self.prompt = trimmedPrompt
        self.schemaIndex = schemaIndex
    }
}

public struct AIQueryDraft: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case ready
        case needsModel
        case rejected
    }

    public let sql: String
    public let explanation: String
    public let referencedObjects: [String]
    public let status: Status
    public let confidence: Double

    public init(
        sql: String,
        explanation: String,
        referencedObjects: [String],
        status: Status,
        confidence: Double
    ) {
        self.sql = sql
        self.explanation = explanation
        self.referencedObjects = referencedObjects
        self.status = status
        self.confidence = confidence
    }
}

public enum AIQueryValidationError: Error, Sendable, Equatable {
    case emptyPrompt
    case missingSchema
}

public protocol AIQueryService: Sendable {
    func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft
}
