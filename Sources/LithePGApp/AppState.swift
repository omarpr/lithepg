import Foundation
import Observation
import LithePGCore

@Observable
@MainActor
public final class AppState {
    public enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(label: String)
    }

    public var connectionState: ConnectionState = .disconnected
    public var editorText: String = "" {
        didSet {
            if lastError != nil { lastError = nil }
        }
    }
    public var lastResult: QueryResult?
    public var lastError: String?
    public var isRunning: Bool = false

    public init() {}

    public func markConnecting() {
        connectionState = .connecting
    }

    public func markConnected(label: String) {
        connectionState = .connected(label: label)
        lastError = nil
    }

    public func markDisconnected() {
        connectionState = .disconnected
        lastResult = nil
        isRunning = false
    }

    public func markRunning() {
        isRunning = true
        lastResult = nil
        lastError = nil
    }

    public func markIdle() {
        isRunning = false
    }

    public func setResult(_ result: QueryResult) {
        lastResult = result
        lastError = nil
    }

    public func setError(_ message: String) {
        lastError = message
    }

    public func clearError() {
        lastError = nil
    }
}
