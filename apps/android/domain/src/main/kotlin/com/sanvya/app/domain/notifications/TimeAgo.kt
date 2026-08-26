package com.sanvya.app.domain.notifications

import java.time.Instant

/**
 * "just now" / "5m ago" / "3h ago" / "2d ago" / a date, ported from
 * apps/web/app/notifications/page.tsx's `timeAgo`.
 *
 * Returns a SHAPE, not a string. Web's version builds English inline
 * (`` `${m}m ago` ``) and falls back to `toLocaleDateString()`, which mixes a
 * hardcoded language with a localised one in the same function. The unit and
 * the number are the logic; naming them is the view's job on a platform that
 * has a locale.
 *
 * `now` is a parameter rather than a clock read, which is what makes it
 * testable -- the same reason `buildTrend` takes `todayIso`.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/TimeAgo.swift.
 */
sealed interface TimeAgo {
    /** Under a minute. */
    data object JustNow : TimeAgo
    data class Minutes(val value: Int) : TimeAgo
    data class Hours(val value: Int) : TimeAgo
    data class Days(val value: Int) : TimeAgo

    /**
     * A week or more ago -- the caller formats [iso] with the device locale.
     * Also what an unparseable timestamp returns, so a bad row renders as
     * itself rather than as "just now", which would be a lie.
     */
    data class On(val iso: String) : TimeAgo
}

fun timeAgo(iso: String, nowIso: String): TimeAgo {
    val then = runCatching { Instant.parse(iso) }.getOrNull() ?: return TimeAgo.On(iso)
    val now = runCatching { Instant.parse(nowIso) }.getOrNull() ?: return TimeAgo.On(iso)

    // `Math.max(0, ...)` in the TS source: a timestamp in the future reads as
    // "just now" rather than as a negative age. Kept.
    val seconds = maxOf(0L, (now.toEpochMilli() - then.toEpochMilli()) / 1000)
    if (seconds < 60) return TimeAgo.JustNow
    val minutes = seconds / 60
    if (minutes < 60) return TimeAgo.Minutes(minutes.toInt())
    val hours = minutes / 60
    if (hours < 24) return TimeAgo.Hours(hours.toInt())
    val days = hours / 24
    if (days < 7) return TimeAgo.Days(days.toInt())
    return TimeAgo.On(iso)
}
