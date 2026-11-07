import Foundation
import LithePGCore

public struct QueryTab: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String
    public var lastResult: QueryResult?
    /// The statement and connection that produced `lastResult`, so cells can be written back
    /// to the right table, and only while connected to the same database.
    public var lastResultSQL: String?
    public var lastResultConnectionLabel: String?

    public init(id: UUID = UUID(), title: String, text: String = "", lastResult: QueryResult? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.lastResult = lastResult
    }
}
