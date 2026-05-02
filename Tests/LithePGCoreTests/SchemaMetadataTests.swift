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

    @Test("identifiers are stable for SwiftUI tree rendering")
    func identifiersAreStable() {
        let schema = DatabaseSchema.Schema(name: "public", relations: [])
        let relation = DatabaseSchema.Relation(schema: "public", name: "orders", kind: .table, columns: [])
        let column = DatabaseSchema.Column(name: "id", typeName: "int4", isNullable: false, ordinalPosition: 1)

        #expect(schema.id == "public")
        #expect(relation.id == "public.orders")
        #expect(column.id == "1:id")
    }
}
