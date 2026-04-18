import Testing
import Foundation
@testable import lithepg

@Suite("PostgresConnector (integration)")
struct PostgresConnectorTests {
    static var plainURL: String? {
        ProcessInfo.processInfo.environment["POSTGRES_TEST_URL"]
    }

    @Test(
        "connects over plain TCP and runs SELECT 1",
        .enabled(if: plainURL != nil)
    )
    func plainSelect1() async throws {
        let config = try ConnectionConfig(url: Self.plainURL!)
        let connector = PostgresConnector()
        let value = try await connector.runSelect1(config: config)
        #expect(value == 1)
    }
}
