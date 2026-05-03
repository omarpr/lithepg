import Foundation
import LithePGCore

public struct QueryTab: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String
    public var lastResult: QueryResult?

    public init(id: UUID = UUID(), title: String, text: String = "", lastResult: QueryResult? = nil) {
        self.id = id
        self.title = title
        self.text = text
        self.lastResult = lastResult
    }
}
