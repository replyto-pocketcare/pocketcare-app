import Foundation

/**
 `combineLatest` for `AsyncThrowingStream` — the operator Swift does not ship
 and Kotlin does.

 **Why this exists.** Every repository in this target has the same shape:
 single-table reads are real `watch()` streams, and anything DERIVED from two or
 more of them is a one-shot `async` snapshot. `LedgerRepository`'s own
 REACTIVITY NOTE says why: "AsyncThrowingStream ... has no built-in
 combine/combineLatest operator". Android has `kotlinx.coroutines.flow.combine`,
 so the same method there is genuinely reactive. That was never a design
 decision either platform made — it was a missing forty lines, and it has been
 quietly costing iOS live updates on net worth, account balances and friend
 balances ever since.

 **Semantics, matching Kotlin's `combine` exactly:**
 - Nothing is emitted until BOTH sources have produced a value.
 - After that, either source producing a value emits a new pair with the
   other's latest.
 - The first error finishes the stream throwing; the other source is cancelled.
 - The stream finishes when both sources finish. A `watch()` never finishes, so
   a combination of two watches never finishes either — which is what a caller
   wants.

 **Sources are passed as already-created streams**, matching
 `LedgerRepository.watchAccount`'s established shape in this target: build the
 upstream on the calling side, then consume it inside a `Task`. Every `watch()`
 here is `throws`, so the caller does the `try` where it reads naturally.
 */
public func combineLatest<A: Sendable, B: Sendable>(
    _ first: AsyncThrowingStream<A, Error>,
    _ second: AsyncThrowingStream<B, Error>
) -> AsyncThrowingStream<(A, B), Error> {
    AsyncThrowingStream { continuation in
        let latest = LatestPair<A, B>()
        let task = Task {
            do {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        for try await value in first {
                            if let pair = await latest.setFirst(value) { continuation.yield(pair) }
                        }
                    }
                    group.addTask {
                        for try await value in second {
                            if let pair = await latest.setSecond(value) { continuation.yield(pair) }
                        }
                    }
                    try await group.waitForAll()
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        // Without this, a consumer that goes away leaves both source watches
        // running for the life of the process — exactly the leak a `watch` on a
        // screen the user has left would cause.
        continuation.onTermination = { _ in task.cancel() }
    }
}

/// An actor, not a lock: the two sources run in sibling child tasks with no
/// isolation of their own, so every read-modify-write of the latest values
/// crosses threads.
private actor LatestPair<A: Sendable, B: Sendable> {
    private var a: A?
    private var b: B?

    func setFirst(_ value: A) -> (A, B)? {
        a = value
        guard let b else { return nil }
        return (value, b)
    }

    func setSecond(_ value: B) -> (A, B)? {
        b = value
        guard let a else { return nil }
        return (a, value)
    }
}
