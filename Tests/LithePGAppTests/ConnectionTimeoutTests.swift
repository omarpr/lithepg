import Darwin
import Foundation
import LithePGCore
import Testing

@testable import LithePGAppUI

/// A TCP port that completes the handshake and then says nothing.
///
/// The socket is bound and listening but never accepted, so the kernel finishes the three-way
/// handshake into the backlog queue. A client sees a connected socket and waits forever for a
/// first byte, which is exactly the condition that used to hang the connect sheet.
private final class SilentTCPPort {
  private let descriptor: Int32
  let port: Int

  init() throws {
    (descriptor, port) = try Self.openListeningSocket()
  }

  private static func openListeningSocket() throws -> (Int32, Int) {
    let descriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw SilentPortError.couldNotOpen }

    var reuse: Int32 = 1
    setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0  // let the kernel choose a free port
    address.sin_addr.s_addr = inet_addr("127.0.0.1")

    let bound = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
    guard bound == 0 else { close(descriptor); throw SilentPortError.couldNotBind }
    guard listen(descriptor, 8) == 0 else {
      close(descriptor)
      throw SilentPortError.couldNotListen
    }

    var assigned = sockaddr_in()
    var length = socklen_t(MemoryLayout<sockaddr_in>.size)
    let read = withUnsafeMutablePointer(to: &assigned) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        getsockname(descriptor, $0, &length)
      }
    }
    guard read == 0 else { close(descriptor); throw SilentPortError.couldNotReadPort }
    return (descriptor, Int(assigned.sin_port.byteSwapped))
  }

  func shutDown() {
    close(descriptor)
  }

  enum SilentPortError: Error {
    case couldNotOpen, couldNotBind, couldNotListen, couldNotReadPort
  }
}

@Suite("Connection timeout")
struct ConnectionTimeoutTests {
  private func config(port: Int) -> ConnectionConfig {
    ConnectionConfig(
      host: "127.0.0.1",
      port: port,
      database: "postgres",
      username: "tester",
      password: "secret",
      tlsMode: .disable
    )
  }

  @Test("a server that accepts and never responds fails instead of hanging")
  func timesOutOnSilentServer() async throws {
    let silent = try SilentTCPPort()
    defer { silent.shutDown() }

    let tester = PostgresConnectionTester(timeout: .seconds(2))
    let start = ContinuousClock.now
    var caught: (any Error)?
    do {
      try await tester.test(config: config(port: silent.port))
    } catch {
      caught = error
    }
    let elapsed = ContinuousClock.now - start

    #expect(caught as? ConnectionTestError == .timedOut(seconds: 2))
    // Generous upper bound: the point is that it returns at all, near the deadline rather than
    // hanging. Before the fix this never returned.
    #expect(elapsed < .seconds(12))
  }

  @Test("the timeout message names the likely cause")
  func timeoutMessageIsActionable() {
    let message = ConnectionTestError.timedOut(seconds: 15).errorDescription ?? ""
    #expect(message.contains("15 seconds"))
    #expect(message.contains("PostgreSQL"))
  }

  @Test("cancelling a running test stops it promptly")
  func cancellationStopsAStalledTest() async throws {
    let silent = try SilentTCPPort()
    defer { silent.shutDown() }

    // A timeout long enough that only cancellation can end this.
    let tester = PostgresConnectionTester(timeout: .seconds(300))
    let stalled = config(port: silent.port)
    let start = ContinuousClock.now
    let work = Task { try await tester.test(config: stalled) }

    try await Task.sleep(for: .milliseconds(400))
    work.cancel()

    var caught: (any Error)?
    do { try await work.value } catch { caught = error }
    let elapsed = ContinuousClock.now - start

    #expect(caught != nil)
    #expect(elapsed < .seconds(12))
  }

  @Test(
    "a healthy connection is unaffected by the watchdog",
    .enabled(if: connectionTimeoutLiveURL != nil)
  )
  func healthyConnectionStillSucceeds() async throws {
    // Guards against the watchdog tearing down a connector that actually worked.
    let tester = PostgresConnectionTester(timeout: .seconds(15))
    try await tester.test(config: try ConnectionConfig(url: connectionTimeoutLiveURL!))
  }
}

private let connectionTimeoutLiveURL = ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]
