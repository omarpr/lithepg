import Testing
@testable import LithePGCore

@Suite("SchemaIndex")
struct SchemaIndexTests {
    @Test("builds relation column and relationship documents from a schema snapshot")
    func buildsDocumentsFromSchemaSnapshot() {
        let index = SchemaIndex(schema: fixtureSchema)

        #expect(index.documents.map(\.id) == [
            "relation:public.customers",
            "column:public.customers.id",
            "column:public.customers.email",
            "relation:public.orders",
            "column:public.orders.id",
            "column:public.orders.customer_id",
            "column:public.orders.total_cents",
            "relationship:public.orders.orders_customer_id_fkey",
        ])

        let customers = index.documents.first { $0.id == "relation:public.customers" }
        #expect(customers?.kind == .relation)
        #expect(customers?.title == "public.customers")
        #expect(customers?.body.contains("table public.customers") == true)
        #expect(customers?.body.contains("primary key id") == true)
        #expect(customers?.body.contains("columns id int8, email text") == true)

        let orderTotal = index.documents.first { $0.id == "column:public.orders.total_cents" }
        #expect(orderTotal?.kind == .column)
        #expect(orderTotal?.title == "public.orders.total_cents")
        #expect(orderTotal?.body.contains("column total_cents int8") == true)
        #expect(orderTotal?.body.contains("required") == true)

        let foreignKey = index.documents.first { $0.id == "relationship:public.orders.orders_customer_id_fkey" }
        #expect(foreignKey?.kind == .relationship)
        #expect(foreignKey?.title == "public.orders -> public.customers")
        #expect(foreignKey?.body.contains("orders.customer_id references customers.id") == true)
    }

    @Test("lexical search ranks matching table and column documents above unrelated documents")
    func lexicalSearchRanksRelevantDocuments() {
        let index = SchemaIndex(schema: fixtureSchema)

        let results = index.search("customer email", limit: 3)

        #expect(results.map(\.id) == [
            "column:public.customers.email",
            "relation:public.customers",
            "relationship:public.orders.orders_customer_id_fkey",
        ])
    }

    @Test("search ignores case punctuation and empty queries")
    func searchNormalizesInput() {
        let index = SchemaIndex(schema: fixtureSchema)

        #expect(index.search("TOTAL-CENTS").first?.id == "column:public.orders.total_cents")
        #expect(index.search("   ").isEmpty)
    }

    private var fixtureSchema: DatabaseSchema {
        DatabaseSchema(
            schemas: [
                .init(
                    name: "public",
                    relations: [
                        .init(
                            schema: "public",
                            name: "orders",
                            kind: .table,
                            columns: [
                                .init(name: "id", typeName: "int8", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                                .init(name: "customer_id", typeName: "int8", isNullable: false, ordinalPosition: 2),
                                .init(name: "total_cents", typeName: "int8", isNullable: false, ordinalPosition: 3),
                            ]
                        ),
                        .init(
                            schema: "public",
                            name: "customers",
                            kind: .table,
                            columns: [
                                .init(name: "id", typeName: "int8", isNullable: false, ordinalPosition: 1, isPrimaryKey: true),
                                .init(name: "email", typeName: "text", isNullable: false, ordinalPosition: 2),
                            ]
                        ),
                    ]
                ),
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
                ),
            ]
        )
    }
}
