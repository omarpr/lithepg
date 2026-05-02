import Foundation
import Testing
@testable import LithePGApp
import LithePGCore

@Suite("AppState")
@MainActor
struct AppStateTests {
    @Test("starts disconnected with empty editor")
    func initialState() {
        let s = AppState()
        #expect(s.connectionState == .disconnected)
        #expect(s.editorText.isEmpty)
        #expect(s.lastResult == nil)
        #expect(s.lastError == nil)
        #expect(s.isRunning == false)
    }

    @Test("setError moves to error state without clobbering editor text")
    func setErrorPreservesEditor() {
        let s = AppState()
        s.editorText = "SELECT 1"
        s.setError("boom")
        #expect(s.lastError == "boom")
        #expect(s.editorText == "SELECT 1")
    }

    @Test("clearError wipes the banner")
    func clearError() {
        let s = AppState()
        s.setError("boom")
        s.clearError()
        #expect(s.lastError == nil)
    }

    @Test("editing the buffer clears any prior error")
    func editingClearsError() {
        let s = AppState()
        s.setError("boom")
        s.editorText = "SELECT 1"
        #expect(s.lastError == nil)
    }

    @Test("setResult stores the result and clears error")
    func setResultClearsError() {
        let s = AppState()
        s.setError("boom")
        let r = QueryResult(
            columns: [.init(name: "n", typeName: "int4")],
            rows: [.init(id: 0, cells: [.text("1")])],
            rowCount: 1,
            elapsed: .milliseconds(5),
            status: .rows,
            truncated: false
        )
        s.setResult(r)
        #expect(s.lastResult?.rowCount == 1)
        #expect(s.lastError == nil)
    }

    @Test("connection lifecycle transitions: disconnected → connecting → connected → disconnected")
    func connectionLifecycle() {
        let s = AppState()
        #expect(s.connectionState == .disconnected)
        s.markConnecting()
        #expect(s.connectionState == .connecting)
        s.markConnected(label: "alice@db:5432/shop")
        if case .connected(let label) = s.connectionState {
            #expect(label == "alice@db:5432/shop")
        } else {
            Issue.record("expected .connected, got \(s.connectionState)")
        }
        s.markDisconnected()
        #expect(s.connectionState == .disconnected)
    }

    @Test("markRunning toggles isRunning and clears prior result")
    func markRunningClearsResult() {
        let s = AppState()
        let r = QueryResult(
            columns: [], rows: [], rowCount: 0, elapsed: .zero, status: .empty, truncated: false
        )
        s.setResult(r)
        s.markRunning()
        #expect(s.isRunning == true)
        #expect(s.lastResult == nil)
    }

    @Test("markIdle clears isRunning without touching result")
    func markIdleKeepsResult() {
        let s = AppState()
        s.markRunning()
        let r = QueryResult(
            columns: [], rows: [], rowCount: 0, elapsed: .zero, status: .empty, truncated: false
        )
        s.setResult(r)
        s.markIdle()
        #expect(s.isRunning == false)
        #expect(s.lastResult != nil)
    }

    @Test("computed UI state tracks connection and runnable query state")
    func computedUIState() {
        let s = AppState()
        #expect(s.windowTitle == "LithePG")
        #expect(s.connectionLabel == nil)
        #expect(s.isConnected == false)
        #expect(s.canRunQuery == false)

        s.editorText = "SELECT 1"
        #expect(s.canRunQuery == false)

        s.markConnected(label: "alice@db:5432/shop")
        #expect(s.windowTitle == "LithePG — alice@db:5432/shop")
        #expect(s.connectionLabel == "alice@db:5432/shop")
        #expect(s.isConnected == true)
        #expect(s.canRunQuery == true)

        s.markRunning()
        #expect(s.canRunQuery == false)
    }
}
