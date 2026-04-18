import Testing
import Foundation
@testable import lithepg

@Suite("PostgresConnector")
struct PostgresConnectorTests {
    static var plainURL: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]
    }

    @Test("construct and shutdown without connecting")
    func lifecycleSmoke() async throws {
        let connector = PostgresConnector()
        try await connector.shutdown()
        try await connector.shutdown() // idempotent
    }

    @Test(
        "connects over plain TCP and runs SELECT 1",
        .enabled(if: plainURL != nil)
    )
    func plainSelect1() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        do {
            let value = try await connector.runSelect1(config: config)
            #expect(value == 1)
        } catch {
            try await connector.shutdown()
            throw error
        }
        try await connector.shutdown()
    }
}
