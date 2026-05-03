import Foundation

public struct QueryTab: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var text: String

    public init(id: UUID = UUID(), title: String, text: String = "") {
        self.id = id
        self.title = title
        self.text = text
    }
}
