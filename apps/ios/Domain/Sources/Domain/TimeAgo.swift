import Foundation

/// "just now" / "5m ago" / "3h ago" / "2d ago" / a date, ported from
/// apps/web/app/notifications/page.tsx's `timeAgo`.
///
/// Returns a SHAPE, not a string. Web's version builds English inline
/// (`` `${m}m ago` ``) and falls back to `toLocaleDateString()`, which mixes a
/// hardcoded language with a localised one in the same function. The unit and
/// the number are the logic; naming them is the view's job on a platform that
/// has a locale.
///
/// `now` is a parameter rather than a clock read, which is what makes it
/// testable — the same reason `buildTrend` takes `todayIso`.
///
/// Mirrors apps/android/domain/.../notifications/TimeAgo.kt.
public enum TimeAgo: Equatable, Sendable {
    /// Under a minute.
    case justNow
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// A week or more ago — the caller formats the ISO string with the device
    /// locale. Also what an unparseable timestamp returns, so a bad row renders
    /// as itself rather than as "just now", which would be a lie.
    case on(String)
}

public func timeAgo(_ iso: String, now nowIso: String) -> TimeAgo {
    guard let then = parseIsoInstant(iso), let now = parseIsoInstant(nowIso) else {
        return .on(iso)
    }

    // `Math.max(0, ...)` in the TS source: a timestamp in the future reads as
    // "just now" rather than as a negative age. Kept.
    let seconds = Int64(Swift.max(0, (now - then)))
    if seconds < 60 { return .justNow }
    let minutes = seconds / 60
    if minutes < 60 { return .minutes(Int(minutes)) }
    let hours = minutes / 60
    if hours < 24 { return .hours(Int(hours)) }
    let days = hours / 24
    if days < 7 { return .days(Int(days)) }
    return .on(iso)
}

/// Seconds since the epoch for an ISO-8601 timestamp, with or without
/// fractional seconds.
///
/// A fresh formatter per call, not a cached global — the same Swift 6
/// "ISO8601DateFormatter may have shared mutable state" rule already documented
/// in SplitsInsights.swift's `parseIsoMillis`.
private func parseIsoInstant(_ iso: String) -> TimeInterval? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: iso) { return date.timeIntervalSince1970 }
    return ISO8601DateFormatter().date(from: iso)?.timeIntervalSince1970
}
