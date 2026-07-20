import Testing
@testable import LithePGCore

@Suite("DeterministicAIQueryService")
struct DeterministicAIQueryServiceTests {
    @Test("simple show prompt drafts a safe limited select")
    func simpleShowPromptDraftsLimitedSelect() async throws {
        let draft = try await draftSQL(for: "show customers")

        #expect(draft.sql == "SELECT * FROM \"lithepg_demo\".\"customers\" LIMIT 100;")
        #expect(draft.explanation == "Drafted a read-only SELECT for lithepg_demo.customers.")
        #expect(draft.referencedObjects == ["lithepg_demo.customers"])
        #expect(draft.status == .ready)
        #expect(draft.confidence == 0.75)
    }

    @Test("top customers by revenue drafts deterministic aggregate SQL")
    func topCustomersByRevenueDraftsAggregate() async throws {
        let draft = try await draftSQL(for: "top customers by revenue")

        #expect(draft.sql == """
        SELECT
          c."id",
          c."name",
          SUM(o."total_cents") AS "revenue_cents"
        FROM "lithepg_demo"."customers" c
        JOIN "lithepg_demo"."orders" o ON o."customer_id" = c."id"
        GROUP BY c."id", c."name"
        ORDER BY "revenue_cents" DESC
        LIMIT 10;
        """)
        #expect(draft.referencedObjects == ["lithepg_demo.customers", "lithepg_demo.orders"])
        #expect(draft.status == .ready)
        #expect(draft.confidence == 0.7)
    }

    @Test("join prompt uses foreign-key metadata")
    func joinPromptUsesForeignKeyMetadata() async throws {
        let draft = try await draftSQL(for: "show orders with customer names")

        #expect(draft.sql == """
        SELECT
          o.*,
          c."name" AS "customer_name"
        FROM "lithepg_demo"."orders" o
        JOIN "lithepg_demo"."customers" c ON o."customer_id" = c."id"
        LIMIT 100;
        """)
        #expect(draft.explanation == "Joined lithepg_demo.orders to lithepg_demo.customers using orders_customer_id_fkey.")
        #expect(draft.referencedObjects == ["lithepg_demo.orders", "lithepg_demo.customers"])
        #expect(draft.status == .ready)
        #expect(draft.confidence == 0.72)
    }

    @Test("unsupported prompts return a low confidence needs-model draft")
    func unsupportedPromptsNeedModel() async throws {
        let draft = try await draftSQL(for: "predict churn next quarter")

        #expect(draft.sql.isEmpty)
        #expect(draft.explanation.contains("built-in local drafter"))
        #expect(draft.referencedObjects.isEmpty)
        #expect(draft.status == .needsModel)
        #expect(draft.confidence == 0)
    }

    @Test("generic count prompt uses the matched schema relation")
    func genericCountPrompt() async throws {
        let draft = try await draftSQL(for: "how many customers are there?")

        #expect(draft.sql == "SELECT COUNT(*) AS \"count\" FROM \"lithepg_demo\".\"customers\";")
        #expect(draft.referencedObjects == ["lithepg_demo.customers"])
        #expect(draft.status == .ready)
    }

    @Test("generic list prompt understands projected columns ordering and limit")
    func genericOrderedProjection() async throws {
        let draft = try await draftSQL(for: "list customer names and plans ordered by name descending limit 25")

        #expect(draft.sql == "SELECT \"name\", \"plan\" FROM \"lithepg_demo\".\"customers\" ORDER BY \"name\" DESC LIMIT 25;")
        #expect(draft.referencedObjects == ["lithepg_demo.customers"])
        #expect(draft.status == .ready)
    }

    @Test("mutation prompts are rejected instead of drafted")
    func mutationPromptsAreRejected() async throws {
        let draft = try await draftSQL(for: "delete all customers")

        #expect(draft.sql.isEmpty)
        #expect(draft.status == .rejected)
        #expect(draft.explanation.contains("read-only"))
    }

    @Test("unsupported filters are not silently omitted")
    func unsupportedFiltersNeedModel() async throws {
        let draft = try await draftSQL(for: "show customers where plan is pro")

        #expect(draft.sql.isEmpty)
        #expect(draft.status == .needsModel)
        #expect(draft.explanation.contains("filter"))
    }

    private func draftSQL(for prompt: String) async throws -> AIQueryDraft {
        let request = try AIQueryRequest(prompt: prompt, schemaIndex: SchemaIndex(schema: dogfoodSchema))
        return try await DeterministicAIQueryService().draftSQL(for: request)
    }

    private var dogfoodSchema: DatabaseSchema {
        DatabaseSchema(
            schemas: [
                .init(name: "lithepg_demo", relations: [
                    .init(schema: "lithepg_demo", name: "customers", kind: .table, columns: [
                        .init(name: "id", typeName: "uuid", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                        .init(name: "name", typeName: "text", isNullable: false, ordinalPosition: 2),
                        .init(name: "plan", typeName: "text", isNullable: false, ordinalPosition: 3),
                    ]),
                    .init(schema: "lithepg_demo", name: "orders", kind: .table, columns: [
                        .init(name: "id", typeName: "int8", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                        .init(name: "customer_id", typeName: "uuid", isNullable: false, ordinalPosition: 2),
                        .init(name: "total_cents", typeName: "int4", isNullable: false, ordinalPosition: 3),
                    ]),
                ]),
            ],
            foreignKeys: [
                .init(
                    name: "orders_customer_id_fkey",
                    childSchema: "lithepg_demo",
                    childRelation: "orders",
                    childColumns: ["customer_id"],
                    parentSchema: "lithepg_demo",
                    parentRelation: "customers",
                    parentColumns: ["id"]
                ),
            ]
        )
    }
}
