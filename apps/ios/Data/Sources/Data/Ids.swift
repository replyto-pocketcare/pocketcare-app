import Foundation

/// Canonical string form of an identifier.
///
/// **Swift's `UUID.uuidString` is UPPERCASE. Nothing else in this product is.**
/// `crypto.randomUUID()` on web and `java.util.UUID.toString()` on Android both
/// produce the lowercase canonical form, and so does Postgres when it renders a
/// `uuid` column. iOS was the only writer producing `A1B2…`.
///
/// That is not cosmetic, because of where these strings live:
///
/// - PowerSync's local mirror stores `id` and `user_id` as **TEXT**, and SQLite
///   compares TEXT case-**sensitively**. `WHERE user_id = ?` with an uppercase
///   id does not match a row that arrived from the server in lowercase.
/// - Postgres `uuid` columns normalise on write. So an iOS-created row syncs up
///   as uppercase, is stored canonically, and **comes back down lowercase** —
///   the local row's own id changes case underneath anything still holding the
///   uppercase one.
///
/// The two together mean an iOS-written row could be found before its first
/// sync and not after, and that a parent created on iOS would not match a child
/// that referenced it via the server's lowercased copy.
///
/// Every identifier that is persisted or compared goes through here. View-local
/// `Identifiable` keys that never reach the database (a draft line item in a
/// form) do not need to, and are left alone.
public extension UUID {
    var canonicalString: String { uuidString.lowercased() }
}
