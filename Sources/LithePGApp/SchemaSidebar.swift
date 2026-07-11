import SwiftUI
import LithePGCore

struct SchemaSidebar: View {
    @Bindable var state: AppState
    @State private var expandedSchemas: Set<String> = []
    @State private var expandedRelations: Set<String> = []

    private var presentation: SchemaSidebarPresentation {
        SchemaSidebarPresentation(
            schema: state.schema,
            isLoading: state.isLoadingSchema,
            error: state.schemaError,
            isConnected: state.isConnected
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 320)
        .accessibilityIdentifier("schema-sidebar")
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Schema")
                    .font(.headline)
                Text(presentation.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await state.refreshSchema() }
            } label: {
                Label("Refresh Schema", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Refresh schema")
            .disabled(!presentation.canRefresh)
            .accessibilityIdentifier("refresh-schema-button")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let message = presentation.message {
            ContentUnavailableView {
                Label(messageTitle(for: message), systemImage: presentation.isError ? "exclamationmark.triangle" : "sidebar.leading")
            } description: {
                Text(messageDetail(for: message))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        } else if let schema = state.schema {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(schema.schemas) { databaseSchema in
                        schemaSection(databaseSchema)
                    }
                }
                .padding(10)
            }
        }
    }

    private func schemaSection(_ schema: DatabaseSchema.Schema) -> some View {
        DisclosureGroup(isExpanded: binding(for: schema.id, in: $expandedSchemas)) {
            VStack(alignment: .leading, spacing: 4) {
                if schema.relations.isEmpty {
                    Text("No tables or views")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 20)
                } else {
                    ForEach(schema.relations) { relation in
                        relationSection(relation)
                    }
                }
            }
            .padding(.top, 4)
        } label: {
            Label(schema.name, systemImage: "folder")
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .disclosureGroupStyle(.automatic)
        .onAppear {
            if expandedSchemas.isEmpty {
                expandedSchemas.insert(schema.id)
            }
        }
    }

    private func relationSection(_ relation: DatabaseSchema.Relation) -> some View {
        DisclosureGroup(isExpanded: binding(for: relation.id, in: $expandedRelations)) {
            VStack(alignment: .leading, spacing: 3) {
                ForEach(relation.columns) { column in
                    columnRow(column)
                }
            }
            .padding(.top, 3)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: relation.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
                Text(relation.name)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(relation.columns.count)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Button {
                    Task { await state.insertAndRunSelect(for: relation) }
                } label: {
                    Image(systemName: "text.insert")
                }
                .buttonStyle(.borderless)
                .help("Insert and run SELECT for \(relation.schema).\(relation.name)")
                .accessibilityIdentifier("insert-select-\(relation.id)")
            }
            .font(.callout)
        }
        .padding(.leading, 14)
    }

    private func columnRow(_ column: DatabaseSchema.Column) -> some View {
        HStack(spacing: 6) {
            Image(systemName: column.isNullable ? "circle" : "circle.fill")
                .font(.system(size: 7))
                .foregroundStyle(column.isNullable ? .tertiary : .secondary)
                .frame(width: 14)
            Text(column.name)
                .lineLimit(1)
            Spacer(minLength: 6)
            Text(column.typeName)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.subheadline)
        .padding(.leading, 28)
        .help(columnHelp(for: column))
    }

    private func binding(for id: String, in set: Binding<Set<String>>) -> Binding<Bool> {
        Binding(
            get: { set.wrappedValue.contains(id) },
            set: { isExpanded in
                if isExpanded {
                    set.wrappedValue.insert(id)
                } else {
                    set.wrappedValue.remove(id)
                }
            }
        )
    }

    private func messageTitle(for message: String) -> String {
        presentation.isError ? "Schema unavailable" : message
    }

    private func messageDetail(for message: String) -> String {
        presentation.isError ? message : "The tree will update after a successful connection or refresh."
    }

    private func columnHelp(for column: DatabaseSchema.Column) -> String {
        var parts = [column.typeName, column.isNullable ? "nullable" : "not null"]
        if let defaultValue = column.defaultValue {
            parts.append("default \(defaultValue)")
        }
        return parts.joined(separator: " · ")
    }
}

struct SchemaSidebarPresentation {
    let summary: String
    let message: String?
    let canRefresh: Bool
    let isError: Bool

    init(schema: DatabaseSchema?, isLoading: Bool, error: String?, isConnected: Bool) {
        let counts = Self.counts(for: schema)
        summary = "\(counts.schemas) \(Self.plural("schema", counts.schemas)) · \(counts.relations) \(Self.plural("relation", counts.relations)) · \(counts.columns) \(Self.plural("column", counts.columns))"
        canRefresh = isConnected && !isLoading

        if isLoading {
            message = "Loading schema…"
            isError = false
        } else if let error, !error.isEmpty {
            message = error
            isError = true
        } else if !isConnected {
            message = "Connect to load schema metadata."
            isError = false
        } else if schema?.schemas.isEmpty ?? true {
            message = "No schema metadata found."
            isError = false
        } else {
            message = nil
            isError = false
        }
    }

    private static func counts(for schema: DatabaseSchema?) -> (schemas: Int, relations: Int, columns: Int) {
        guard let schema else { return (0, 0, 0) }
        let relations = schema.schemas.flatMap(\.relations)
        let columns = relations.flatMap(\.columns)
        return (schema.schemas.count, relations.count, columns.count)
    }

    private static func plural(_ singular: String, _ count: Int) -> String {
        count == 1 ? singular : "\(singular)s"
    }
}

private extension DatabaseSchema.Relation.Kind {
    var systemImage: String {
        switch self {
        case .table: "tablecells"
        case .view: "eye"
        }
    }
}
