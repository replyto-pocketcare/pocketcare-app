package com.sanvya.app.ui

import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * Locale-aware labels for the ISO date strings the database stores.
 *
 * Was private inside `dashboard/TileViews.kt` until the notification inbox
 * needed the same formatting -- a second copy is the re-inlining the audit's
 * component inventory exists to prevent. Mirrors iOS's `DateLabels.swift`.
 *
 * Both build the words with the DEVICE's locale. Web hardcodes English month
 * names in `buildTrend` and mixes in a localised `toLocaleDateString()`
 * elsewhere; neither is something to copy into two otherwise translated apps.
 */

/** "12 Aug" -- web's `toLocaleDateString(undefined, { month: "short", day: "numeric" })`. */
fun dayMonthLabel(iso: String): String = isoLabel(iso, "d MMM")

/**
 * Formats the date part of an ISO string, or returns it unchanged if it is not
 * one. `take(10)` because a stored timestamp may carry a time component --
 * which also means the date is read as the civil date the database wrote, not
 * re-derived in the device's zone.
 */
fun isoLabel(iso: String, pattern: String): String {
    val date = runCatching { LocalDate.parse(iso.take(10)) }.getOrNull() ?: return iso
    return date.format(DateTimeFormatter.ofPattern(pattern))
}
