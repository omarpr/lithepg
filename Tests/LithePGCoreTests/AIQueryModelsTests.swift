import Testing
@testable import LithePGCore

@Suite("AIQueryModels")
struct AIQueryModelsTests {
    @Test("requests trim prompts and require schema context")
    func requestsValidatePromptAndSchemaContext() throws {
        let schemaIndex = SchemaIndex(schema: fixtureSchema)

        let request = try AIQueryRequest(prompt: "  show customer emails  ", schemaIndex: schemaIndex)

        #expect(request.prompt == "show customer emails")
        #expect(request.schemaIndex == schemaIndex)
        #expect(throws: AIQueryValidationError.emptyPrompt) {
            try AIQueryRequest(prompt: " \n\t ", schemaIndex: schemaIndex)
        }
        #expect(throws: AIQueryValidationError.missingSchema) {
            try AIQueryRequest(prompt: "show customers", schemaIndex: SchemaIndex(documents: []))
        }
    }

    @Test("drafts carry sql explanation references status and confidence")
    func draftsCarryReviewMetadata() {
        let draft = AIQueryDraft(
            sql: "SELECT * FROM \"public\".\"customers\" LIMIT 100;",
            explanation: "Lists customer rows for review before execution.",
            referencedObjects: ["public.customers"],
            status: .ready,
            confidence: 0.84
        )

        #expect(draft.sql == "SELECT * FROM \"public\".\"customers\" LIMIT 100;")
        #expect(draft.explanation == "Lists customer rows for review before execution.")
        #expect(draft.referencedObjects == ["public.customers"])
        #expect(draft.status == .ready)
        #expect(draft.confidence == 0.84)

        let unsupported = AIQueryDraft(
            sql: "",
            explanation: "A local model is needed for this prompt.",
            referencedObjects: [],
            status: .needsModel,
            confidence: 0
        )
        #expect(unsupported.status == .needsModel)
    }

    @Test("service protocol drafts SQL asynchronously from validated requests")
    func serviceProtocolDraftsSQL() async throws {
        let service: any AIQueryService = FixtureAIQueryService()
        let request = try AIQueryRequest(prompt: "show customers", schemaIndex: SchemaIndex(schema: fixtureSchema))

        let draft = try await service.draftSQL(for: request)

        #expect(draft.sql == "SELECT * FROM \"public\".\"customers\" LIMIT 100;")
        #expect(draft.referencedObjects == ["public.customers"])
        #expect(draft.status == .ready)
    }

    private var fixtureSchema: DatabaseSchema {
        DatabaseSchema(schemas: [
            .init(name: "public", relations: [
                .init(schema: "public", name: "customers", kind: .table, columns: [
                    .init(name: "id", typeName: "int8", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                    .init(name: "email", typeName: "text", isNullable: false, ordinalPosition: 2),
                ]),
            ]),
        ])
    }

    private struct FixtureAIQueryService: AIQueryService {
        func draftSQL(for request: AIQueryRequest) async throws -> AIQueryDraft {
            AIQueryDraft(
                sql: "SELECT * FROM \"public\".\"customers\" LIMIT 100;",
                explanation: "Fixture draft for \(request.prompt).",
                referencedObjects: ["public.customers"],
                status: .ready,
                confidence: 1
            )
        }
    }
}
