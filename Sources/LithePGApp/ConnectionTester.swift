import Foundation
import LithePGCore

public protocol ConnectionTesting: Sendable {
  func test(config: ConnectionConfig) async throws
}

public struct PostgresConnectionTester: ConnectionTesting, Sendable {
  /// PostgresNIO's own `connectTimeout` bounds only the TCP connect. A server that accepts the
  /// socket and then stalls leaves the TLS handshake, the startup exchange and the query with
  /// no deadline at all, which used to wedge the connect sheet until the app restarted.
  ///
  /// Sits above that 10 second TCP timeout so an unreachable host still reports the more
  /// specific error, and above a cold provider compute start.
  public static let defaultTimeout: Duration = .seconds(15)

  private let timeout: Duration

  public init(timeout: Duration = PostgresConnectionTester.defaultTimeout) {
    self.timeout = timeout
  }

  public func test(config: ConnectionConfig) async throws {
    let connector = PostgresConnector()
    do {
      let value = try await withDeadline(
        timeout,
        onExpiry: { try? await connector.shutdown() }
      ) {
        try await connector.runSelect1(config: config)
      }
      try await connector.shutdown()
      guard value == 1 else { throw ConnectionTestError.unexpectedResult }
    } catch let expired as DeadlineExceededError {
      // `onExpiry` already released the connector's event-loop threads.
      throw ConnectionTestError.timedOut(seconds: expired.seconds)
    } catch {
      try? await connector.shutdown()
      throw error
    }
  }
}

public enum ConnectionTestError: Error, Sendable, LocalizedError, Equatable {
  case unexpectedResult
  case timedOut(seconds: Int)

  public var errorDescription: String? {
    switch self {
    case .unexpectedResult:
      "The server returned an unexpected response to the connection test."
    case .timedOut(let seconds):
      """
      The server did not respond within \(seconds) seconds. It accepted the connection but \
      never completed the PostgreSQL handshake, so check that the host and port point at a \
      PostgreSQL server.
      """
    }
  }
}
