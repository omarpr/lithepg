import Foundation

public struct DeterministicAIQueryService: AIQueryService {
    public init() {}

    public func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft {
        let catalog = SchemaDocumentCatalog(index: request.schemaIndex)
        let orderedPromptTokens = Self.tokens(in: request.prompt)
        let promptTokens = Set(orderedPromptTokens)

        if !promptTokens.isDisjoint(with: Self.mutationTokens) {
            return AIQueryDraft(
                sql: "",
                explanation: "The built-in English-to-SQL drafter is read-only and will not draft mutation or DDL statements.",
                referencedObjects: [],
                status: .rejected,
                confidence: 1
            )
        }

        if let draft = revenueDraft(catalog: catalog, promptTokens: promptTokens) {
            return draft
        }

        if let draft = joinDraft(catalog: catalog, promptTokens: promptTokens) {
            return draft
        }

        if let relation = catalog.relations.first(where: { Self.matches($0, promptTokens: promptTokens) }) {
            return genericDraft(
                relation: relation,
                catalog: catalog,
                orderedPromptTokens: orderedPromptTokens,
                promptTokens: promptTokens
            )
        }

        return AIQueryDraft(
            sql: "",
            explanation: "The built-in local drafter could not map this request to a schema relation. Try naming a table and asking to list, count, or order its rows; broader language requires a reviewed local model.",
            referencedObjects: [],
            status: .needsModel,
            confidence: 0
        )
    }

    private func genericDraft(
        relation: RelationRef,
        catalog: SchemaDocumentCatalog,
        orderedPromptTokens: [String],
        promptTokens: Set<String>
    ) -> AIQueryDraft {
        let qualified = Self.quotedQualified(schema: relation.schema, name: relation.name)
        if !promptTokens.isDisjoint(with: ["filter", "having", "where", "whose"]) {
            return AIQueryDraft(
                sql: "",
                explanation: "The built-in local drafter will not guess filter values or operators. Write the WHERE clause in SQL or use a reviewed local model.",
                referencedObjects: [relation.qualifiedName],
                status: .needsModel,
                confidence: 0
            )
        }
        if promptTokens.contains("count")
            || promptTokens.contains("number")
            || (promptTokens.contains("how") && promptTokens.contains("many"))
        {
            return AIQueryDraft(
                sql: "SELECT COUNT(*) AS \"count\" FROM \(qualified);",
                explanation: "Counted rows in \(relation.qualifiedName) with a read-only aggregate.",
                referencedObjects: [relation.qualifiedName],
                status: .ready,
                confidence: 0.82
            )
        }

        let columns = catalog.columns(in: relation)
        let projectedColumns = Self.mentionedColumns(
            in: orderedPromptTokens,
            availableColumns: columns
        )
        let projection = projectedColumns.isEmpty
            ? "*"
            : projectedColumns.map(Self.quoted).joined(separator: ", ")
        let ordering = Self.orderingClause(
            promptTokens: orderedPromptTokens,
            availableColumns: columns
        )
        let limit = Self.requestedLimit(in: orderedPromptTokens) ?? 100
        let sql = "SELECT \(projection) FROM \(qualified)\(ordering) LIMIT \(limit);"
        return AIQueryDraft(
            sql: sql,
            explanation: "Drafted a read-only SELECT for \(relation.qualifiedName).",
            referencedObjects: [relation.qualifiedName],
            status: .ready,
            confidence: projectedColumns.isEmpty && ordering.isEmpty ? 0.75 : 0.8
        )
    }

    private func revenueDraft(catalog: SchemaDocumentCatalog, promptTokens: Set<String>) -> AIQueryDraft? {
        guard promptTokens.contains("revenue"),
              promptTokens.contains("customer"),
              let relationship = catalog.relationship(child: "orders", parent: "customers"),
              let customers = catalog.relation(schema: relationship.parent.schema, name: relationship.parent.name),
              let orders = catalog.relation(schema: relationship.child.schema, name: relationship.child.name),
              catalog.hasColumn("total_cents", in: orders),
              catalog.hasColumn("name", in: customers),
              let childColumn = relationship.childColumns.first,
              let parentColumn = relationship.parentColumns.first else {
            return nil
        }

        return AIQueryDraft(
            sql: """
            SELECT
              c."id",
              c."name",
              SUM(o."total_cents") AS "revenue_cents"
            FROM \(Self.quotedQualified(schema: customers.schema, name: customers.name)) c
            JOIN \(Self.quotedQualified(schema: orders.schema, name: orders.name)) o ON o.\(Self.quoted(childColumn)) = c.\(Self.quoted(parentColumn))
            GROUP BY c."id", c."name"
            ORDER BY "revenue_cents" DESC
            LIMIT 10;
            """,
            explanation: "Aggregated order totals by customer using \(relationship.name).",
            referencedObjects: [customers.qualifiedName, orders.qualifiedName],
            status: .ready,
            confidence: 0.7
        )
    }

    private func joinDraft(catalog: SchemaDocumentCatalog, promptTokens: Set<String>) -> AIQueryDraft? {
        guard promptTokens.contains("order"),
              promptTokens.contains("customer"),
              let relationship = catalog.relationship(child: "orders", parent: "customers"),
              let orders = catalog.relation(schema: relationship.child.schema, name: relationship.child.name),
              let customers = catalog.relation(schema: relationship.parent.schema, name: relationship.parent.name),
              catalog.hasColumn("name", in: customers),
              let childColumn = relationship.childColumns.first,
              let parentColumn = relationship.parentColumns.first else {
            return nil
        }

        return AIQueryDraft(
            sql: """
            SELECT
              o.*,
              c."name" AS "customer_name"
            FROM \(Self.quotedQualified(schema: orders.schema, name: orders.name)) o
            JOIN \(Self.quotedQualified(schema: customers.schema, name: customers.name)) c ON o.\(Self.quoted(childColumn)) = c.\(Self.quoted(parentColumn))
            LIMIT 100;
            """,
            explanation: "Joined \(orders.qualifiedName) to \(customers.qualifiedName) using \(relationship.name).",
            referencedObjects: [orders.qualifiedName, customers.qualifiedName],
            status: .ready,
            confidence: 0.72
        )
    }

    private static func matches(_ relation: RelationRef, promptTokens: Set<String>) -> Bool {
        let relationTokens = tokens(in: relation.name)
        return relationTokens.contains { promptTokens.contains($0) }
    }

    private static let mutationTokens: Set<String> = [
        "alter", "create", "delete", "drop", "grant", "insert", "revoke", "truncate", "update",
    ]

    private static func mentionedColumns(
        in promptTokens: [String],
        availableColumns: [String]
    ) -> [String] {
        let projectionTokens = Array(promptTokens.prefix {
            !["order", "ordered", "sort", "sorted"].contains($0)
        })
        var selected: [String] = []
        for token in projectionTokens {
            guard let column = availableColumns.first(where: {
                tokens(in: $0).contains(token)
            }), !selected.contains(column) else { continue }
            selected.append(column)
        }
        return selected
    }

    private static func orderingClause(
        promptTokens: [String],
        availableColumns: [String]
    ) -> String {
        guard promptTokens.contains(where: { ["order", "ordered", "sort", "sorted"].contains($0) })
        else { return "" }

        let searchStart = promptTokens.firstIndex(of: "by").map { $0 + 1 } ?? 0
        guard searchStart < promptTokens.count,
            let column = promptTokens[searchStart...].compactMap({ token in
                availableColumns.first { tokens(in: $0).contains(token) }
            }).first
        else { return "" }

        let descending = promptTokens.contains(where: {
            ["desc", "descending", "latest", "newest", "top"].contains($0)
        })
        return " ORDER BY \(quoted(column)) \(descending ? "DESC" : "ASC")"
    }

    private static func requestedLimit(in promptTokens: [String]) -> Int? {
        for (index, token) in promptTokens.enumerated()
            where ["first", "limit", "top"].contains(token) && index + 1 < promptTokens.count
        {
            guard let value = Int(promptTokens[index + 1]) else { continue }
            return min(max(value, 1), 1_000)
        }
        return nil
    }

    private static func quotedQualified(schema: String, name: String) -> String {
        "\(quoted(schema)).\(quoted(name))"
    }

    private static func quoted(_ identifier: String) -> String {
        "\"\(identifier.replacingOccurrences(of: "\"", with: "\"\""))\""
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
}

private struct SchemaDocumentCatalog {
    let relations: [RelationRef]
    let relationships: [RelationshipRef]
    let columnsByRelation: [String: Set<String>]
    let orderedColumnsByRelation: [String: [String]]

    init(index: SchemaIndex) {
        self.relations = index.documents.compactMap { document in
            guard document.kind == .relation else { return nil }
            return RelationRef(qualifiedName: document.title)
        }
        self.relationships = index.documents.compactMap { document in
            guard document.kind == .relationship else { return nil }
            return RelationshipRef(document: document)
        }

        var columns: [String: Set<String>] = [:]
        var orderedColumns: [String: [String]] = [:]
        for document in index.documents where document.kind == .column {
            guard let column = ColumnRef(qualifiedName: document.title) else { continue }
            columns[column.relation.qualifiedName, default: []].insert(column.name)
            if !orderedColumns[column.relation.qualifiedName, default: []].contains(column.name) {
                orderedColumns[column.relation.qualifiedName, default: []].append(column.name)
            }
        }
        self.columnsByRelation = columns
        self.orderedColumnsByRelation = orderedColumns
    }

    func relation(schema: String, name: String) -> RelationRef? {
        relations.first { $0.schema == schema && $0.name == name }
    }

    func hasColumn(_ column: String, in relation: RelationRef) -> Bool {
        columnsByRelation[relation.qualifiedName, default: []].contains(column)
    }

    func columns(in relation: RelationRef) -> [String] {
        orderedColumnsByRelation[relation.qualifiedName, default: []]
    }

    func relationship(child: String, parent: String) -> RelationshipRef? {
        relationships.first { relationship in
            relationship.child.name == child && relationship.parent.name == parent
        }
    }
}

private struct RelationRef: Equatable {
    let schema: String
    let name: String

    var qualifiedName: String { "\(schema).\(name)" }

    init?(qualifiedName: String) {
        let parts = qualifiedName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2, let name = parts.last else { return nil }
        self.schema = parts.dropLast().joined(separator: ".")
        self.name = name
    }

    init(schema: String, name: String) {
        self.schema = schema
        self.name = name
    }
}

private struct ColumnRef {
    let relation: RelationRef
    let name: String

    init?(qualifiedName: String) {
        let parts = qualifiedName.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3, let columnName = parts.last else { return nil }
        self.name = columnName
        self.relation = RelationRef(
            schema: parts.dropLast(2).joined(separator: "."),
            name: parts.dropLast().last ?? ""
        )
    }
}

private struct RelationshipRef {
    let name: String
    let child: RelationRef
    let parent: RelationRef
    let childColumns: [String]
    let parentColumns: [String]

    init?(document: SchemaDocument) {
        let titleParts = document.title.components(separatedBy: " -> ")
        guard titleParts.count == 2,
              let child = RelationRef(qualifiedName: titleParts[0]),
              let parent = RelationRef(qualifiedName: titleParts[1]) else {
            return nil
        }

        self.child = child
        self.parent = parent
        self.name = document.id.split(separator: ".").last.map(String.init) ?? "foreign_key"

        let referenceText = document.body
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.contains(" references ") } ?? ""
        let referenceParts = referenceText.components(separatedBy: " references ")
        guard referenceParts.count == 2 else { return nil }

        self.childColumns = Self.columnNames(in: referenceParts[0])
        self.parentColumns = Self.columnNames(in: referenceParts[1])
    }

    private static func columnNames(in text: String) -> [String] {
        text
            .components(separatedBy: ",")
            .compactMap { path in
                path
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: ".")
                    .last
                    .map(String.init)
            }
    }
}
