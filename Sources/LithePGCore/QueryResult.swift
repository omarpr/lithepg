import Foundation

public struct QueryResult: Sendable, Equatable {
    public let columns: [Column]
    public let rows: [Row]
    public let rowCount: Int
    public let elapsed: Duration
    public let status: Status
    public let truncated: Bool

    public init(
        columns: [Column],
        rows: [Row],
        rowCount: Int,
        elapsed: Duration,
        status: Status,
        truncated: Bool
    ) {
        self.columns = columns
        self.rows = rows
        self.rowCount = rowCount
        self.elapsed = elapsed
        self.status = status
        self.truncated = truncated
    }

    public struct Column: Sendable, Equatable {
        public let name: String
        public let typeName: String

        public init(name: String, typeName: String) {
            self.name = name
            self.typeName = typeName
        }
    }

    public struct Row: Sendable, Equatable, Identifiable {
        public let id: Int
        public let cells: [Cell]

        public init(id: Int, cells: [Cell]) {
            self.id = id
            self.cells = cells
        }
    }

    public enum Cell: Sendable, Equatable {
        case null
        case text(String)
    }

    public enum Status: Sendable, Equatable {
        case rows
        case command(tag: String, affected: Int)
        case empty
    }
}
