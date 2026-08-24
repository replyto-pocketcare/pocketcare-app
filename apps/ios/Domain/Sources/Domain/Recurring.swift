import Foundation

/// How often a recurring commitment falls due.
///
/// Stored as free text in `recurring_items.frequency`, so the parse is
/// deliberately forgiving — but the fallback is `.yearly`, not an error,
/// because that is what web does: `engine.ts`'s `advance()` ends in a bare
/// `else d.setFullYear(...)`, so any unrecognised value already behaves as
/// yearly on the live client. Throwing here instead would make native reject
/// rows web happily posts.
public enum RecurringFrequency: String, Sendable, CaseIterable {
    case daily
    case weekly
    case monthly
    case yearly

    /// Web's fall-through, made explicit. Unknown → `.yearly`.
    public static func fromDb(_ value: String?) -> RecurringFrequency {
        guard let key = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let match = RecurringFrequency(rawValue: key) else { return .yearly }
        return match
    }
}

// Sendable explicitly. A public type gets no inference, and every other error
// type in Domain (MoneyError, CurrencyMismatchError) declares it -- `any Error`
// is special-cased today so nothing diagnoses the omission, which is exactly
// how it would go unnoticed until something did.
public enum RecurringError: Error, Sendable, CustomStringConvertible {
    case badDate(String)

    public var description: String {
        switch self {
        case .badDate(let s): "advance(): not a YYYY-MM-DD date: \(s)"
        }
    }
}

/// The next due date after `dateIso`, `n` intervals on.
///
/// Pinned by `tools/golden-vectors/vectors/recurring-advance.json`, which is
/// the authority — not a fresh reading of `engine.ts`. Mirrors
/// `apps/android/domain/.../recurring/Recurring.kt`.
///
/// ## Why this does not simply mirror the JS
///
/// Web's implementation is `d.setMonth(d.getMonth() + n)`, and `setMonth`
/// **overflows** rather than clamping: Jan 31 + 1 month is March 3, not
/// February 28. Worse, it is not self-correcting — the next run advances from
/// March 3, so the item skips February entirely and then sticks on the 3rd of
/// every month forever. It affects any commitment due on the 29th, 30th or
/// 31st. Akhilesh confirmed 2026-08-23 that clamping is intended and that web
/// will be corrected; the vectors were re-pinned to clamping then.
///
/// ## Clamping alone is still not the whole fix
///
/// `Jan 31 → Feb 28 → Mar 28` — clamping loses the "31st" intent permanently,
/// because each step reads the day off the *previous* result. The real fix is
/// to remember the day the user chose and clamp from that every time, which is
/// what `anchorDay` is for.
///
/// - Parameter anchorDay: the day-of-month the user originally chose (1–31).
///   When nil, the day is read off `dateIso`, reproducing today's behaviour
///   exactly. Nothing passes it yet: `recurring_items` has no `anchor_day`
///   column (see PARITY_AUDIT §6c for the migration plan). It exists now so the
///   engine is already shaped for the column when it lands, rather than needing
///   its call sites rewritten. Ignored for daily and weekly, which have no
///   day-of-month.
public func advance(
    _ dateIso: String,
    _ frequency: RecurringFrequency,
    _ n: Int,
    anchorDay: Int? = nil
) throws -> String {
    guard let ymd = parseYmd(dateIso) else { throw RecurringError.badDate(dateIso) }

    switch frequency {
    // Plain day arithmetic, via a UTC calendar so a device timezone can never
    // shift a date-only value across a boundary. Going through isoOf() first
    // clamps a stored impossible date (2026-02-30) to a real one — web gets
    // `Invalid Date` there and produces garbage, and refusing to parse would
    // strand the item forever.
    case .daily: return addDays(ymd, n)
    case .weekly: return addDays(ymd, 7 * n)
    case .monthly: return isoOf(ymd.y, ymd.m + n, anchorDay ?? ymd.d)
    case .yearly: return isoOf(ymd.y + n, ymd.m, anchorDay ?? ymd.d)
    }
}

/// Convenience for callers holding the raw column value.
public func advance(
    _ dateIso: String,
    _ frequency: String?,
    _ n: Int,
    anchorDay: Int? = nil
) throws -> String {
    try advance(dateIso, RecurringFrequency.fromDb(frequency), n, anchorDay: anchorDay)
}

/// Adds whole days to a civil date, in UTC.
///
/// A UTC calendar rather than the device's: this is a date-only value, and a
/// local calendar can shift one across a day boundary depending on where the
/// phone happens to be. `isoOf` is used to normalise on the way in and out, so
/// a stored impossible date (2026-02-30) clamps to a real one instead of
/// failing — web gets `Invalid Date` there and produces garbage, and refusing
/// to parse would strand the item forever.
private func addDays(_ ymd: FinanceYmd, _ days: Int) -> String {
    let clamped = isoOf(ymd.y, ymd.m, ymd.d)
    guard let safe = parseYmd(clamped) else { return clamped }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!

    var start = DateComponents()
    start.year = safe.y
    start.month = safe.m + 1
    start.day = safe.d

    guard let base = calendar.date(from: start),
          let moved = calendar.date(byAdding: .day, value: days, to: base) else {
        return clamped
    }

    let out = calendar.dateComponents([.year, .month, .day], from: moved)
    guard let y = out.year, let m = out.month, let d = out.day else { return clamped }
    return isoOf(y, m - 1, d)
}
