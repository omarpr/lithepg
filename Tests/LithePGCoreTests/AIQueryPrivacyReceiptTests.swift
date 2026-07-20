import Foundation
import LithePGCore
import Testing

@Suite("AI query privacy receipts")
struct AIQueryPrivacyReceiptTests {
  @Test("prompt context excludes credentials raw connection URLs and result rows")
  func contextExcludesSensitiveInputs() throws {
    let schemaIndex = SchemaIndex(schema: privacySchema)
    let result = QueryResult(
      columns: [
        .init(name: "email", typeName: "text"),
        .init(name: "card_token", typeName: "text"),
      ],
      rows: [.init(id: 0, cells: [.text("alice@example.com"), .text("tok_live_sensitive")])],
      rowCount: 1,
      elapsed: .milliseconds(1),
      status: .rows,
      truncated: false
    )

    let context = try AIQueryContextBuilder.build(
      prompt: "Show customers password=hunter2 from postgres://dbuser:supersecret@db.example.com/prod",
      schemaIndex: schemaIndex,
      rawConnectionURL: "postgres://dbuser:supersecret@db.example.com/prod",
      latestResult: result
    )

    let serialized = context.serializedPromptContext
    #expect(serialized.contains("public.customers"))
    #expect(serialized.contains("[redacted]"))
    #expect(!serialized.contains("hunter2"))
    #expect(!serialized.contains("supersecret"))
    #expect(!serialized.contains("postgres://dbuser:supersecret@db.example.com/prod"))
    #expect(!serialized.contains("alice@example.com"))
    #expect(!serialized.contains("tok_live_sensitive"))
  }

  @Test("receipt makes local-only generated-SQL review invariants explicit")
  func receiptDocumentsPrivacyInvariants() throws {
    let context = try AIQueryContextBuilder.build(
      prompt: "show customers",
      schemaIndex: SchemaIndex(schema: privacySchema),
      rawConnectionURL: "postgres://dbuser:supersecret@db.example.com/prod",
      latestResult: nil
    )

    #expect(context.privacyReceipt.localOnly)
    #expect(!context.privacyReceipt.networkCallsAllowed)
    #expect(!context.privacyReceipt.includesCredentials)
    #expect(!context.privacyReceipt.includesRawConnectionURLs)
    #expect(!context.privacyReceipt.includesResultRows)
    #expect(!context.privacyReceipt.modelArtifactsBundled)
    #expect(context.privacyReceipt.requiresGeneratedSQLReview)
  }
}

private let privacySchema = DatabaseSchema(schemas: [
  .init(name: "public", relations: [
    .init(schema: "public", name: "customers", kind: .table, columns: [
      .init(name: "id", typeName: "uuid", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
      .init(name: "email", typeName: "text", isNullable: false, ordinalPosition: 2),
    ]),
  ]),
])
