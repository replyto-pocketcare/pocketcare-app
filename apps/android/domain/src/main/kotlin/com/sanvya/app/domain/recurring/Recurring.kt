package com.sanvya.app.domain.recurring

import com.sanvya.app.domain.finance.Ymd
import com.sanvya.app.domain.finance.isoOf
import com.sanvya.app.domain.finance.parseYmd
import java.time.LocalDate

/**
 * How often a recurring commitment falls due.
 *
 * Stored as free text in `recurring_items.frequency`, so the parse is
 * deliberately forgiving — but the fallback is [YEARLY], not an error, because
 * that is what web does: `engine.ts`'s `advance()` ends in a bare `else
 * d.setFullYear(...)`, so any unrecognised value already behaves as yearly on
 * the live client. Throwing here instead would make native reject rows web
 * happily posts.
 */
enum class RecurringFrequency(val dbValue: String) {
    DAILY("daily"),
    WEEKLY("weekly"),
    MONTHLY("monthly"),
    YEARLY("yearly");

    companion object {
        /** Web's fall-through, made explicit. Unknown → [YEARLY]. */
        fun fromDb(value: String?): RecurringFrequency {
            val key = value?.trim()?.lowercase()
            return entries.firstOrNull { it.dbValue == key } ?: YEARLY
        }
    }
}

/**
 * The next due date after [dateIso], [n] intervals on.
 *
 * Pinned by `tools/golden-vectors/vectors/recurring-advance.json`, which is the
 * authority — not a fresh reading of `engine.ts`.
 *
 * ## Why this does not simply mirror the JS
 *
 * Web's implementation is:
 *
 * ```js
 * const d = new Date(dateStr + "T00:00:00");
 * if (freq === "monthly") d.setMonth(d.getMonth() + n);
 * ```
 *
 * `setMonth` **overflows** rather than clamping: Jan 31 + 1 month is March 3,
 * not February 28. Worse, it is not self-correcting — the next run advances
 * from March 3, so the item skips February entirely and then sticks on the 3rd
 * of every month forever. It affects any commitment due on the 29th, 30th or
 * 31st. Akhilesh confirmed 2026-08-23 that clamping is the intended behaviour
 * and that web will be corrected; the vectors were re-pinned to clamping then.
 *
 * ## Clamping alone is still not the whole fix
 *
 * `Jan 31 → Feb 28 → Mar 28` — clamping loses the "31st" intent permanently,
 * because each step reads the day off the *previous* result. The real fix is to
 * remember the day the user chose and clamp from that every time, which is what
 * [anchorDay] is for.
 *
 * @param anchorDay the day-of-month the user originally chose (1–31). When
 *   null, the day is read off [dateIso], reproducing today's behaviour exactly.
 *   Nothing passes it yet: `recurring_items` has no `anchor_day` column (see
 *   PARITY_AUDIT §6c for the migration plan). It exists now so the engine is
 *   already shaped for the column when it lands, rather than needing its call
 *   sites rewritten. Ignored for daily and weekly, which have no day-of-month.
 */
fun advance(
    dateIso: String,
    frequency: RecurringFrequency,
    n: Int,
    anchorDay: Int? = null,
): String {
    val ymd = parseYmd(dateIso)
        ?: throw IllegalArgumentException("advance(): not a YYYY-MM-DD date: $dateIso")

    return when (frequency) {
        // Plain day arithmetic. Going through isoOf() first clamps a stored
        // impossible date (2026-02-30) to a real one, which LocalDate.of would
        // otherwise reject outright — web gets `Invalid Date` and produces
        // garbage; refusing to parse would strand the item forever.
        RecurringFrequency.DAILY -> ymd.toLocalDate().plusDays(n.toLong()).toString()
        RecurringFrequency.WEEKLY -> ymd.toLocalDate().plusWeeks(n.toLong()).toString()
        RecurringFrequency.MONTHLY -> isoOf(ymd.y, ymd.m + n, anchorDay ?: ymd.d)
        RecurringFrequency.YEARLY -> isoOf(ymd.y + n, ymd.m, anchorDay ?: ymd.d)
    }
}

/** Convenience for callers holding the raw column value. */
fun advance(dateIso: String, frequency: String?, n: Int, anchorDay: Int? = null): String =
    advance(dateIso, RecurringFrequency.fromDb(frequency), n, anchorDay)

private fun Ymd.toLocalDate(): LocalDate = LocalDate.parse(isoOf(y, m, d))
