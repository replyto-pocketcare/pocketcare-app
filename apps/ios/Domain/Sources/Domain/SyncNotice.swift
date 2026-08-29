import Foundation

/// What, if anything, the in-flow sync strip should say.
///
/// A port of `syncMessage()` in apps/web/src/sync.ts. Web's version returns the
/// COPY; this returns the DECISION and the screen looks the words up, because
/// the native clients are translated and web is not (its two strings are English
/// literals — recorded in docs/mobile/PARITY_AUDIT.md under the web defects).
///
/// The three outcomes, and why each one exists:
///
///  * ``none`` — the common case. Online and fine, OR online with a transient
///    network/websocket blip. PowerSync retries those on its own, and a strip
///    that appears every time a phone changes cell tower is a strip people learn
///    to ignore. Raw errors never reach the UI at all.
///  * ``offline`` — truly offline. A calm note, not a warning: nothing is wrong,
///    the writes are on the device and will go up later.
///  * ``trouble`` — online, and something that is NOT a network problem failed
///    (a schema error, a rejected write). This is the only case that offers an
///    action, because it is the only one the user could plausibly act on.
///
/// Mirrors apps/android/domain/.../syncstatus/SyncNotice.kt.
public enum SyncNotice: String, Equatable, Sendable {
    case none
    case offline
    case trouble
}

/// Substrings that mean "the network wobbled", matched case-insensitively.
///
/// Web spells this as one alternation regex; a token list is the same thing and
/// survives being read by someone who does not want to parse a regex to find out
/// whether their error is going to be swallowed. Keep the two in step — adding a
/// token here without adding it to `sync.ts` makes the ports disagree about when
/// to stay quiet.
private let transientSyncTokens: [String] = [
    "websocket",
    "network",
    "failed to fetch",
    "load failed",
    "connection",
    "timeout",
    "offline",
    "econn",
    "etimedout",
]

/// True when `error` reads as a connection wobble rather than a real failure.
///
/// Blank is not transient and not a failure either — it is "no error", and the
/// caller has already handled that case. Exposed (and vector-pinned) separately
/// because it is the half that decides whether a user ever sees the strip, and a
/// silent classifier is worth being able to test on its own.
public func isTransientSyncError(_ error: String?) -> Bool {
    guard let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    let lowered = error.lowercased()
    return transientSyncTokens.contains { lowered.contains($0) }
}

/// The strip's state for a given connectivity + error pair.
///
/// `online` first, exactly as web orders it: being offline explains every error
/// underneath it, so saying "we are having trouble syncing" to someone on a train
/// with no signal would be both alarming and wrong.
public func syncNotice(online: Bool, error: String?) -> SyncNotice {
    if !online { return .offline }
    guard let error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .none }
    return isTransientSyncError(error) ? .none : .trouble
}
