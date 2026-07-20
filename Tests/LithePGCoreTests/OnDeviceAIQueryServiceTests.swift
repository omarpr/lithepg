import Foundation
import Testing

@testable import LithePGCore

private let systemModelSmokeEnabled =
  ProcessInfo.processInfo.environment["LITHEPG_SYSTEM_MODEL_SMOKE"] == "1"

@Suite("On-device AI query service")
struct OnDeviceAIQueryServiceTests {
  @Test("does not substitute another model when Apple's model is unavailable")
  func unavailableWithoutFallback() async throws {
    let service = OnDeviceAIQueryService(modelAvailability: .unsupportedSystem)
    let request = try AIQueryRequest(
      prompt: "show customers",
      schemaIndex: SchemaIndex(schema: schema)
    )

    let draft = try await service.draftSQL(for: request)

    #expect(draft.status == .needsModel)
    #expect(draft.sql.isEmpty)
    #expect(draft.explanation.contains("macOS 26"))
  }

  @Test("duplicate known relation references remain valid")
  func duplicateKnownRelationReferences() {
    let knownRelations: Set<String> = ["public.customers"]

    #expect(
      OnDeviceAIQueryService.validatedReferencedObjects(
        ["public.customers", "\"public\".\"customers\""],
        knownRelations: knownRelations
      ) == ["public.customers"]
    )
    #expect(
      OnDeviceAIQueryService.validatedReferencedObjects(
        ["public.customers", "public.unknown"],
        knownRelations: knownRelations
      ) == nil
    )
  }

  @Test("accepts one read-only SELECT and normalizes its terminator")
  func acceptsReadOnlySelect() {
    let sql = """
      SELECT "id", 'delete; drop table customers' AS "note"
      FROM "public"."customers"
      WHERE "name" = 'Update'
      """

    let normalized = AIQuerySQLSafety.normalizedReadOnlyStatement(sql)

    #expect(normalized?.hasSuffix(";") == true)
    #expect(normalized?.contains("drop table customers") == true)
  }

  @Test("accepts a read-only CTE and ignores mutation words in comments")
  func acceptsReadOnlyCTE() {
    let sql = """
      WITH "recent" AS (
        SELECT * FROM "public"."customers" -- do not DELETE anything
      )
      SELECT * FROM "recent";
      """

    #expect(AIQuerySQLSafety.normalizedReadOnlyStatement(sql) != nil)
  }

  @Test(
    "rejects mutation CTEs SELECT INTO locking clauses and multiple statements",
    arguments: [
      "WITH gone AS (DELETE FROM customers RETURNING *) SELECT * FROM gone;",
      "SELECT * INTO archived_customers FROM customers;",
      "SELECT * FROM customers FOR UPDATE;",
      "SELECT * FROM customers; DROP TABLE customers;",
      "UPDATE customers SET name = 'x';",
    ]
  )
  func rejectsUnsafeSQL(sql: String) {
    #expect(AIQuerySQLSafety.normalizedReadOnlyStatement(sql) == nil)
  }

  @Test("rejects malformed quoted strings and comments")
  func rejectsMalformedSQL() {
    #expect(AIQuerySQLSafety.normalizedReadOnlyStatement("SELECT 'unfinished") == nil)
    #expect(AIQuerySQLSafety.normalizedReadOnlyStatement("SELECT 1 /* unfinished") == nil)
  }

  @Test(
    "optional Apple system model smoke drafts a schema-aware aggregate",
    .enabled(if: systemModelSmokeEnabled)
  )
  func optionalSystemModelSmoke() async throws {
    let service = OnDeviceAIQueryService()
    let request = try AIQueryRequest(
      prompt:
        "List customer names with their order count, highest count first, only customers with at least two orders",
      schemaIndex: SchemaIndex(schema: smokeSchema)
    )

    let draft = try await service.draftSQL(for: request)

    #expect(draft.status == .ready)
    #expect(draft.sql.contains("COUNT"))
    #expect(draft.sql.contains("JOIN"))
    #expect(draft.referencedObjects.contains("public.customers"))
    #expect(draft.referencedObjects.contains("public.orders"))
  }

  private var schema: DatabaseSchema {
    DatabaseSchema(schemas: [
      .init(
        name: "public",
        relations: [
          .init(
            schema: "public", name: "customers", kind: .table,
            columns: [
              .init(
                name: "id", typeName: "uuid", isNullable: false,
                ordinalPosition: 1, isPrimaryKey: true
              ),
              .init(
                name: "name", typeName: "text", isNullable: false,
                ordinalPosition: 2
              ),
            ])
        ])
    ])
  }

  private var smokeSchema: DatabaseSchema {
    DatabaseSchema(
      schemas: [
        .init(
          name: "public",
          relations: [
            .init(
              schema: "public", name: "customers", kind: .table,
              columns: [
                .init(
                  name: "id", typeName: "uuid", isNullable: false,
                  ordinalPosition: 1, isPrimaryKey: true
                ),
                .init(
                  name: "name", typeName: "text", isNullable: false,
                  ordinalPosition: 2
                ),
              ]),
            .init(
              schema: "public", name: "orders", kind: .table,
              columns: [
                .init(
                  name: "id", typeName: "int8", isNullable: false,
                  ordinalPosition: 1, isPrimaryKey: true
                ),
                .init(
                  name: "customer_id", typeName: "uuid", isNullable: false,
                  ordinalPosition: 2
                ),
              ]),
          ])
      ],
      foreignKeys: [
        .init(
          name: "orders_customer_id_fkey",
          childSchema: "public",
          childRelation: "orders",
          childColumns: ["customer_id"],
          parentSchema: "public",
          parentRelation: "customers",
          parentColumns: ["id"]
        )
      ]
    )
  }
}
