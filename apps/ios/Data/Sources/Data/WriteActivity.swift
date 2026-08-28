import Combine
import Foundation

/// How many synced-row writes are in flight.
///
/// Swift mirror of the counter inside `apps/web/src/ui/GlobalLoader.tsx`, which
/// `write.ts` wraps every INSERT/UPDATE in via `withLoading()`. The shell reads
/// it and shows a small spinner in the corner while anything is being written.
///
/// **This is deliberately global mutable state, and that is worth saying out
/// loud.** Web's is a module-level `let count = 0` with a `Set` of listeners. A
/// per-screen loading flag would be the cleaner design, but it is not the design
/// being ported: the whole point of web's indicator is that it fires for writes
/// the current screen did not start -- a background auto-post, a sync repair, a
/// settlement confirmed from a notification -- and a per-screen flag cannot see
/// those. A single counter in the layer that performs every write can.
///
/// `@MainActor` is what makes it safe under strict concurrency: the counter is
/// only ever touched on one actor, so the two mutations below cannot race no
/// matter which thread the write itself ran on.
///
/// `ObservableObject` rather than `@Observable`: this package's macOS floor is
/// 13 (see Package.swift — Domain and Data are testable with a plain
/// `swift test`, no simulator, and that is worth keeping), and the Observation
/// macro needs 14. Combine's is the same contract for one `@Published` Int, and
/// it is the pattern the app already uses for its other shared singletons
/// (`Prefs`, `NavPrefs`, `ConnectivityMonitor`).
///
/// Mirrors Android's WriteActivity.kt.
@MainActor
public final class WriteActivity: ObservableObject {
    public static let shared = WriteActivity()

    /// Writes currently in flight. Zero means idle.
    @Published public private(set) var inFlight = 0

    public var busy: Bool { inFlight > 0 }

    private init() {}

    public func begin() { inFlight += 1 }

    /// `max(0,)` mirrors web's `Math.max(0, count - 1)`. It should be
    /// unreachable; it is here because a stuck-at-negative counter would
    /// silently disable the indicator for the rest of the session.
    public func end() { inFlight = max(0, inFlight - 1) }
}

/// Run [block] with the counter raised, lowering it however it ends.
///
/// Both exits lower it, not just the success path: a failed write still has to
/// clear the spinner, or one thrown error leaves it turning forever.
public func withLoading<T>(_ block: () async throws -> T) async throws -> T {
    await WriteActivity.shared.begin()
    do {
        let result = try await block()
        await WriteActivity.shared.end()
        return result
    } catch {
        await WriteActivity.shared.end()
        throw error
    }
}
