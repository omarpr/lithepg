import Foundation

/// Thrown by ``withDeadline(_:onExpiry:operation:)`` when the operation outlived its deadline.
public struct DeadlineExceededError: Error, Equatable, Sendable {
    public let seconds: Int

    public init(seconds: Int) {
        self.seconds = seconds
    }
}

/// Runs `operation`, giving up after `duration`.
///
/// Deliberately abandons the operation rather than waiting for it, because the case this exists
/// for cannot be interrupted at all. PostgresNIO's connect does not observe task cancellation,
/// and shutting the event-loop group down returns immediately while orphaning the pending
/// connect promise, so the underlying `await` never resumes. Measured against a server that
/// accepts TCP and then stays silent.
///
/// That also rules out the obvious structured approaches: `withTaskGroup` and `async let` both
/// wait for every child before returning, so a stuck child hangs the parent no matter how the
/// race is written. Only an unstructured task the caller can walk away from actually returns.
///
/// The abandoned task stays suspended on a promise that never fulfills, so it leaks its own
/// stack. `onExpiry` runs once the deadline has been claimed and is the place to release the
/// heavier resources, such as the connector's event-loop threads. It never runs when the
/// operation wins the race, so it is safe to tear down state the success path still needs.
public func withDeadline<T: Sendable>(
    _ duration: Duration,
    onExpiry: @escaping @Sendable () async -> Void = {},
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let seconds = Int(duration.components.seconds)
    let gate = ContinuationGate<T>()

    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, any Error>) in
            gate.attach(continuation)

            let work = Task {
                do {
                    gate.finish(.success(try await operation()))
                } catch {
                    gate.finish(.failure(error))
                }
            }

            Task {
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return  // the deadline itself was cancelled
                }
                // Claim the outcome before acting, so a success that lands in this instant is
                // never torn down by `onExpiry`.
                guard gate.finish(.failure(DeadlineExceededError(seconds: seconds))) else {
                    return
                }
                work.cancel()
                await onExpiry()
            }
        }
    } onCancel: {
        guard gate.finish(.failure(CancellationError())) else { return }
        Task { await onExpiry() }
    }
}

/// Resumes a continuation exactly once, whichever racer gets there first.
///
/// Tolerates finishing before the continuation is attached: `withCheckedThrowingContinuation`
/// runs its body synchronously, but cancellation can fire from another thread in that window.
private final class ContinuationGate<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, any Error>?
    private var settled = false
    private var pending: Result<T, any Error>?

    func attach(_ continuation: CheckedContinuation<T, any Error>) {
        lock.lock()
        if let pending {
            self.pending = nil
            lock.unlock()
            continuation.resume(with: pending)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    /// Returns true when this caller settled the race, false when someone else already had.
    @discardableResult
    func finish(_ result: Result<T, any Error>) -> Bool {
        lock.lock()
        if settled {
            lock.unlock()
            return false
        }
        settled = true
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
            return true
        }
        pending = result
        lock.unlock()
        return true
    }
}
