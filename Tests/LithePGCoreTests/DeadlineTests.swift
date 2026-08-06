import Testing
import Foundation
import LithePGCore

@Suite("withDeadline")
struct DeadlineTests {
    private struct OperationFailure: Error, Equatable {}

    // MARK: - Racing

    @Test("returns the operation's value when it finishes first")
    func returnsOperationValue() async throws {
        let value = try await withDeadline(.seconds(10)) { 42 }
        #expect(value == 42)
    }

    @Test("throws DeadlineExceededError when the operation outlives the deadline")
    func throwsOnExpiry() async {
        await #expect(throws: DeadlineExceededError(seconds: 0)) {
            try await withDeadline(.milliseconds(50)) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
    }

    @Test("propagates an error thrown by the operation")
    func propagatesOperationError() async {
        await #expect(throws: OperationFailure()) {
            try await withDeadline(.seconds(10)) { throw OperationFailure() }
        }
    }

    // MARK: - onExpiry

    @Test("runs onExpiry when the deadline wins")
    func runsExpiryHandlerOnExpiry() async throws {
        let ran = Flag()
        _ = try? await withDeadline(.milliseconds(50), onExpiry: { ran.set() }) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return 1
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(ran.isSet)
    }

    @Test("leaves onExpiry alone when the operation wins")
    func skipsExpiryHandlerOnSuccess() async throws {
        let ran = Flag()
        let value = try await withDeadline(.milliseconds(200), onExpiry: { ran.set() }) { 7 }
        #expect(value == 7)
        // Outlive the deadline, so a sleeper that fired anyway would be caught.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(!ran.isSet)
    }

    // MARK: - Deadline conversion

    /// The sleeper converts the `Duration` to nanoseconds itself, because `Task.sleep(for:)` was
    /// miscompiled by Swift 6.3.3 and crashed 1.0.8. These cover the conversion: a sub-second
    /// deadline must not truncate to zero or round up to a whole second, and a deadline with both
    /// whole and fractional parts must keep both.
    @Test("honours a sub-second deadline")
    func honoursSubSecondDeadline() async {
        let start = ContinuousClock.now
        _ = try? await withDeadline(.milliseconds(150)) {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            return 1
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed >= .milliseconds(100))
        #expect(elapsed < .seconds(2))
    }

    @Test("honours a deadline with whole and fractional seconds")
    func honoursMixedDeadline() async {
        let start = ContinuousClock.now
        _ = try? await withDeadline(.milliseconds(1_200)) {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return 1
        }
        let elapsed = ContinuousClock.now - start
        #expect(elapsed >= .seconds(1))
        #expect(elapsed < .seconds(4))
    }

    // MARK: - Regression

    /// The sleeper keeps running after the operation wins, so it wakes once the deadline passes
    /// with nothing left to do. Swift 6.3.3 miscompiled `Task.sleep(for:)` there: the sleep's async
    /// frame came off the task allocator out of order and the runtime aborted the process with
    /// "freed pointer was not the last allocation", roughly `duration` after every connection
    /// attempt whatever its outcome. That shipped in 1.0.8.
    ///
    /// Worth being honest about the reach here: this exercises the shape that crashed, and it
    /// would fail by taking the test process down, but it did not reproduce the miscompile inside
    /// a test bundle even on the toolchain that crashes a release executable. The guard that does
    /// catch it is the Swift version floor in `script/build_and_run.sh`, covered by
    /// `script/test_build_and_run.sh`.
    @Test("survives its own sleeper waking after the operation already won")
    func sleeperOutlivesDeadlineWithoutAbort() async throws {
        for _ in 0..<20 {
            let value = try await withDeadline(.milliseconds(200), onExpiry: { }) { 1 }
            #expect(value == 1)
        }
        try await Task.sleep(nanoseconds: 600_000_000)
    }

    @Test("survives the expiry path outliving the deadline")
    func expiryPathOutlivesDeadlineWithoutAbort() async throws {
        for _ in 0..<20 {
            _ = try? await withDeadline(.milliseconds(50)) {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return 1
            }
        }
        try await Task.sleep(nanoseconds: 500_000_000)
    }
}

/// Minimal thread-safe flag, because the expiry handler runs off the test's task.
private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
