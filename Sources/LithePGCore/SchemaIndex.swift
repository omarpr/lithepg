import Foundation

public struct SchemaDocument: Sendable, Equatable, Identifiable {
    public enum Kind: Sendable, Equatable {
        case relation
        case column
        case relationship
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let body: String

    public init(id: String, kind: Kind, title: String, body: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.body = body
    }
}

public struct SchemaIndex: Sendable, Equatable {
    public let documents: [SchemaDocument]

    public init(schema: DatabaseSchema) {
        var documents: [SchemaDocument] = []

        for schemaNamespace in schema.schemas {
            for relation in schemaNamespace.relations {
                documents.append(Self.relationDocument(for: relation))

                for column in relation.columns {
                    documents.append(Self.columnDocument(for: column, relation: relation))
                }
            }
        }

        for foreignKey in schema.foreignKeys {
            documents.append(Self.relationshipDocument(for: foreignKey))
        }

        self.documents = documents
    }

    public init(documents: [SchemaDocument]) {
        self.documents = documents
    }

    public func search(_ query: String, limit: Int = 5) -> [SchemaDocument] {
        let queryTokens = Set(Self.tokens(in: query))
        guard !queryTokens.isEmpty, limit > 0 else { return [] }

        return documents
            .enumerated()
            .compactMap { offset, document -> RankedDocument? in
                let score = Self.score(document: document, queryTokens: queryTokens)
                guard score > 0 else { return nil }
                return RankedDocument(document: document, score: score, offset: offset)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.offset < rhs.offset
            }
            .prefix(limit)
            .map(\.document)
    }

    private static func relationDocument(for relation: DatabaseSchema.Relation) -> SchemaDocument {
        let primaryKeys = relation.columns.filter(\.isPrimaryKey).map(\.name)
        let columnSummary = relation.columns
            .map { "\($0.name) \($0.typeName)" }
            .joined(separator: ", ")
        var parts = [
            "\(relation.kind.rawValue) \(relation.schema).\(relation.name)",
            "columns \(columnSummary)",
        ]
        if !primaryKeys.isEmpty {
            parts.append("primary key \(primaryKeys.joined(separator: ", "))")
        }

        return SchemaDocument(
            id: "relation:\(relation.schema).\(relation.name)",
            kind: .relation,
            title: "\(relation.schema).\(relation.name)",
            body: parts.joined(separator: "; ")
        )
    }

    private static func columnDocument(
        for column: DatabaseSchema.Column,
        relation: DatabaseSchema.Relation
    ) -> SchemaDocument {
        var parts = [
            "column \(column.name) \(column.typeName) on table \(relation.schema).\(relation.name)",
            column.isNullable ? "nullable" : "required",
        ]
        if column.isPrimaryKey {
            parts.append("primary key")
        }
        if let defaultValue = column.defaultValue {
            parts.append("default \(defaultValue)")
        }

        return SchemaDocument(
            id: "column:\(relation.schema).\(relation.name).\(column.name)",
            kind: .column,
            title: "\(relation.schema).\(relation.name).\(column.name)",
            body: parts.joined(separator: "; ")
        )
    }

    private static func relationshipDocument(for foreignKey: DatabaseSchema.ForeignKey) -> SchemaDocument {
        let childColumns = foreignKey.childColumns.joined(separator: ", ")
        let parentColumns = foreignKey.parentColumns.joined(separator: ", ")
        let childColumnPath = foreignKey.childColumns
            .map { "\(foreignKey.childRelation).\($0)" }
            .joined(separator: ", ")
        let parentColumnPath = foreignKey.parentColumns
            .map { "\(foreignKey.parentRelation).\($0)" }
            .joined(separator: ", ")

        return SchemaDocument(
            id: "relationship:\(foreignKey.childSchema).\(foreignKey.childRelation).\(foreignKey.name)",
            kind: .relationship,
            title: "\(foreignKey.childSchema).\(foreignKey.childRelation) -> \(foreignKey.parentSchema).\(foreignKey.parentRelation)",
            body: "foreign key \(foreignKey.name); \(childColumnPath) references \(parentColumnPath); columns \(childColumns) to \(parentColumns)"
        )
    }

    private static func score(document: SchemaDocument, queryTokens: Set<String>) -> Int {
        let titleTokens = tokens(in: document.title)
        let bodyTokens = tokens(in: document.body)
        let documentTokens = titleTokens + bodyTokens
        let matchedTokens = queryTokens.filter { documentTokens.contains($0) }
        guard !matchedTokens.isEmpty else { return 0 }

        let titleScore = titleTokens.reduce(0) { score, token in
            score + (queryTokens.contains(token) ? 3 : 0)
        }
        let bodyScore = bodyTokens.reduce(0) { score, token in
            score + (queryTokens.contains(token) ? 1 : 0)
        }

        return matchedTokens.count * 10 + titleScore + bodyScore
    }

    private static func tokens(in text: String) -> [String] {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .map(normalizedToken)
            .filter { !$0.isEmpty }
    }

    private static func normalizedToken(_ token: String) -> String {
        if token.count > 3, token.hasSuffix("s") {
            return String(token.dropLast())
        }
        return token
    }

    private struct RankedDocument {
        let document: SchemaDocument
        let score: Int
        let offset: Int
    }
}
