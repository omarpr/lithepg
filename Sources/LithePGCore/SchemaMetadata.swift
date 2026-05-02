import Foundation

public struct DatabaseSchema: Sendable, Equatable {
    public let schemas: [Schema]

    public init(schemas: [Schema]) {
        self.schemas = schemas.sortedForDisplay()
    }

    public struct Schema: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let relations: [Relation]

        public init(name: String, relations: [Relation]) {
            self.name = name
            self.relations = relations.sortedForDisplay()
        }
    }

    public struct Relation: Sendable, Equatable, Identifiable {
        public var id: String { "\(schema).\(name)" }
        public let schema: String
        public let name: String
        public let kind: Kind
        public let columns: [Column]

        public init(schema: String, name: String, kind: Kind, columns: [Column]) {
            self.schema = schema
            self.name = name
            self.kind = kind
            self.columns = columns.sortedForDisplay()
        }

        public enum Kind: String, Sendable, Equatable {
            case table
            case view
        }
    }

    public struct Column: Sendable, Equatable, Identifiable {
        public var id: String { "\(ordinalPosition):\(name)" }
        public let name: String
        public let typeName: String
        public let isNullable: Bool
        public let defaultValue: String?
        public let ordinalPosition: Int

        public init(
            name: String,
            typeName: String,
            isNullable: Bool,
            defaultValue: String? = nil,
            ordinalPosition: Int
        ) {
            self.name = name
            self.typeName = typeName
            self.isNullable = isNullable
            self.defaultValue = defaultValue
            self.ordinalPosition = ordinalPosition
        }
    }
}

private extension Array where Element == DatabaseSchema.Schema {
    func sortedForDisplay() -> [Element] {
        sorted { lhs, rhs in
            lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == DatabaseSchema.Relation {
    func sortedForDisplay() -> [Element] {
        sorted { lhs, rhs in
            if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

private extension Array where Element == DatabaseSchema.Column {
    func sortedForDisplay() -> [Element] {
        sorted { lhs, rhs in
            if lhs.ordinalPosition != rhs.ordinalPosition { return lhs.ordinalPosition < rhs.ordinalPosition }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
