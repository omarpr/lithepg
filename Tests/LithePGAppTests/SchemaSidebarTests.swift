import Testing
@testable import LithePGApp
import LithePGCore

@Suite("SchemaSidebar")
struct SchemaSidebarTests {
    @Test("presentation summarizes loaded schema metadata")
    func presentationSummarizesLoadedSchema() {
        let schema = DatabaseSchema(schemas: [
            .init(name: "public", relations: [
                .init(schema: "public", name: "users", kind: .table, columns: [
                    .init(name: "id", typeName: "int4", isNullable: false, ordinalPosition: 1),
                    .init(name: "email", typeName: "text", isNullable: false, ordinalPosition: 2),
                ]),
                .init(schema: "public", name: "active_users", kind: .view, columns: [
                    .init(name: "email", typeName: "text", isNullable: false, ordinalPosition: 1),
                ]),
            ]),
        ])

        let presentation = SchemaSidebarPresentation(
            schema: schema,
            isLoading: false,
            error: nil,
            isConnected: true
        )

        #expect(presentation.summary == "1 schema · 2 relations · 3 columns")
        #expect(presentation.message == nil)
        #expect(presentation.canRefresh == true)
    }

    @Test("presentation reports loading, errors, and disconnected refresh state")
    func presentationReportsTransientStates() {
        let loading = SchemaSidebarPresentation(
            schema: nil,
            isLoading: true,
            error: nil,
            isConnected: true
        )
        #expect(loading.message == "Loading schema…")
        #expect(loading.canRefresh == false)

        let failed = SchemaSidebarPresentation(
            schema: nil,
            isLoading: false,
            error: "permission denied",
            isConnected: true
        )
        #expect(failed.message == "permission denied")
        #expect(failed.canRefresh == true)

        let disconnected = SchemaSidebarPresentation(
            schema: nil,
            isLoading: false,
            error: nil,
            isConnected: false
        )
        #expect(disconnected.message == "Connect to load schema metadata.")
        #expect(disconnected.canRefresh == false)
    }
}
