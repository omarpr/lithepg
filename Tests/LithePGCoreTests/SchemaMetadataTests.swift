import Testing
@testable import LithePGCore

@Suite("SchemaMetadata")
struct SchemaMetadataTests {
    @Test("schemas are sorted alphabetically for display")
    func schemasSortAlphabetically() {
        let metadata = DatabaseSchema(schemas: [
            .init(name: "z_reporting", relations: []),
            .init(name: "public", relations: []),
            .init(name: "analytics", relations: []),
        ])

        #expect(metadata.schemas.map(\.name) == ["analytics", "public", "z_reporting"])
    }

    @Test("relations sort by kind then name")
    func relationsSortByKindThenName() {
        let schema = DatabaseSchema.Schema(name: "public", relations: [
            .init(schema: "public", name: "z_view", kind: .view, columns: []),
            .init(schema: "public", name: "orders", kind: .table, columns: []),
            .init(schema: "public", name: "customers", kind: .table, columns: []),
            .init(schema: "public", name: "a_view", kind: .view, columns: []),
        ])

        #expect(schema.relations.map(\.name) == ["customers", "orders", "a_view", "z_view"])
        #expect(schema.relations.map(\.kind) == [.table, .table, .view, .view])
    }

    @Test("columns sort by ordinal position")
    func columnsSortByOrdinalPosition() {
        let relation = DatabaseSchema.Relation(schema: "public", name: "people", kind: .table, columns: [
            .init(name: "email", typeName: "text", isNullable: true, ordinalPosition: 3),
            .init(name: "id", typeName: "int4", isNullable: false, defaultValue: "nextval('people_id_seq'::regclass)", ordinalPosition: 1),
            .init(name: "name", typeName: "text", isNullable: false, ordinalPosition: 2),
        ])

        #expect(relation.columns.map(\.name) == ["id", "name", "email"])
        #expect(relation.columns.first?.defaultValue == "nextval('people_id_seq'::regclass)")
    }

    @Test("columns can mark primary keys")
    func columnsMarkPrimaryKeys() {
        let column = DatabaseSchema.Column(
            name: "id",
            typeName: "int4",
            isNullable: false,
            ordinalPosition: 1,
            isPrimaryKey: true
        )

        #expect(column.isPrimaryKey)
    }

    @Test("foreign keys sort deterministically by child path and name")
    func foreignKeysSortDeterministically() {
        let metadata = DatabaseSchema(
            schemas: [],
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
                .init(
                    name: "line_items_order_id_fkey",
                    childSchema: "public",
                    childRelation: "line_items",
                    childColumns: ["order_id"],
                    parentSchema: "public",
                    parentRelation: "orders",
                    parentColumns: ["id"]
                ),
            ]
        )

        #expect(metadata.foreignKeys.map(\.name) == ["line_items_order_id_fkey", "orders_customer_id_fkey"])
        #expect(metadata.foreignKeys.first?.id == "public.line_items.line_items_order_id_fkey")
    }

    @Test("identifiers are stable for SwiftUI tree rendering")
    func identifiersAreStable() {
        let schema = DatabaseSchema.Schema(name: "public", relations: [])
        let relation = DatabaseSchema.Relation(schema: "public", name: "orders", kind: .table, columns: [])
        let column = DatabaseSchema.Column(name: "id", typeName: "int4", isNullable: false, ordinalPosition: 1)
        let foreignKey = DatabaseSchema.ForeignKey(
            name: "orders_customer_id_fkey",
            childSchema: "public",
            childRelation: "orders",
            childColumns: ["customer_id"],
            parentSchema: "public",
            parentRelation: "customers",
            parentColumns: ["id"]
        )

        #expect(schema.id == "public")
        #expect(relation.id == "public.orders")
        #expect(column.id == "1:id")
        #expect(foreignKey.id == "public.orders.orders_customer_id_fkey")
    }
}
