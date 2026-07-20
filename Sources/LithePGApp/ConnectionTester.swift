import Foundation
import LithePGCore

public protocol ConnectionTesting: Sendable {
  func test(config: ConnectionConfig) async throws
}

public struct PostgresConnectionTester: ConnectionTesting, Sendable {
  public init() {}

  public func test(config: ConnectionConfig) async throws {
    let connector = PostgresConnector()
    do {
      let value = try await connector.runSelect1(config: config)
      try await connector.shutdown()
      guard value == 1 else { throw ConnectionTestError.unexpectedResult }
    } catch {
      try? await connector.shutdown()
      throw error
    }
  }
}

public enum ConnectionTestError: Error, Sendable, LocalizedError {
  case unexpectedResult

  public var errorDescription: String? {
    "The server returned an unexpected response to the connection test."
  }
}
