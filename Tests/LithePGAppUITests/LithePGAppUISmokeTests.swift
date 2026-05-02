#if canImport(XCTest)
import XCTest

@MainActor
final class LithePGAppUISmokeTests: XCTestCase {
    func testConnectsToDockerPostgresAndRendersSelectResult() throws {
        guard let url = ProcessInfo.processInfo.environment["LITHEPG_UI_SMOKE_URL"], !url.isEmpty else {
            throw XCTSkip("Set LITHEPG_UI_SMOKE_URL to run the app UI Postgres smoke test.")
        }

        guard let appPath = ProcessInfo.processInfo.environment["LITHEPG_UI_SMOKE_APP_PATH"], !appPath.isEmpty else {
            throw XCTSkip("Set LITHEPG_UI_SMOKE_APP_PATH to a built LithePGApp executable or .app bundle.")
        }

        let app = XCUIApplication(url: URL(fileURLWithPath: appPath))
        app.launchEnvironment["LITHEPG_UI_SMOKE_URL"] = url
        app.launchEnvironment["LITHEPG_UI_SMOKE_QUERY"] = "SELECT 42 AS lithepg_ui_smoke"
        app.launch()

        let status = app.staticTexts["connection-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "connection status should be visible")
        XCTAssertTrue(
            status.waitUntilLabelContains("@", timeout: 20),
            "app should reach a connected state, current status: \\(status.label)"
        )

        let header = app.staticTexts["result-header-0"]
        XCTAssertTrue(header.waitForExistence(timeout: 20), "result header should render")
        XCTAssertEqual(header.label, "lithepg_ui_smoke")

        let cell = app.staticTexts["result-cell-0-0"]
        XCTAssertTrue(cell.waitForExistence(timeout: 5), "result cell should render")
        XCTAssertEqual(cell.label, "42")

        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "LithePG connected Docker Postgres smoke"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

@MainActor
private extension XCUIElement {
    func waitUntilLabelContains(_ needle: String, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", needle)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
#endif
