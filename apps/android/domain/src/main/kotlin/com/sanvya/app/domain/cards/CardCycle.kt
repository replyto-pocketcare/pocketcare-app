package com.sanvya.app.domain.cards

import com.sanvya.app.domain.js.jsNumber
import java.time.LocalDate

/**
 * When a newly-entered credit-card statement balance is actually payable.
 *
 * Ported from the `cardDueDate` helper at the top of
 * `apps/web/app/accounts/new/page.tsx`. It is three lines of month arithmetic
 * with two off-by-one traps in it, it decides a date the user is told to pay
 * money on, and it was duplicated nowhere -- which is exactly the shape of
 * thing that belongs in Domain under vectors rather than inside a screen.
 *
 * The rule: a statement closes on [statementDay]. If the card is entered on or
 * before that day the balance belongs to the CURRENT cycle; enter it after and
 * the statement has already closed, so it rolls to the next one. The due day
 * may itself fall in the month after the statement -- a card that closes on the
 * 25th and is due on the 5th is due in the FOLLOWING month, which is the second
 * `+ 1` below.
 *
 * Mirrors iOS's CardCycle.swift.
 */

/** Web's `{ dueOn, thisCycle }`, with the date as a plain `yyyy-MM-dd`. */
data class CardDue(
    val dueOn: String,
    /**
     * False when the balance rolled into the next statement. Web uses it only
     * to choose which of two preview sentences to show -- the amount is stored
     * either way, and the rolled case is expressed by the DATE, not by a zero.
     */
    val thisCycle: Boolean,
)

/**
 * Web's `Math.min(28, Math.max(1, Number(v) || fallback))`.
 *
 * 28 rather than 31 so the day exists in February; the clamp is web's and the
 * ceiling is not negotiable, because a due date of 31 February is not a date.
 * An unparseable field falls back rather than refusing -- `Number("") || 1` is
 * 1, and web relies on that for the empty box.
 */
fun clampCardDay(raw: String, fallback: Int): Int {
    val n = jsNumber(raw)
    val v = if (n.isNaN() || n == 0.0) fallback.toDouble() else n
    return v.toInt().coerceIn(1, 28)
}

/**
 * The due date for a balance entered on [createdIso] (a `yyyy-MM-dd` day).
 *
 * **One deliberate divergence from web, and it is a real bug there.** Web
 * builds `new Date(year, dueMonth, dueDay)` -- LOCAL midnight -- and then
 * stores `.toISOString().slice(0, 10)`, which is UTC. Every user east of
 * Greenwich therefore gets a due date one day EARLY: in IST, local midnight on
 * the 20th is 18:30 UTC on the 19th. This computes the calendar date and keeps
 * it, so the day the user was shown is the day that is stored. A vector pins
 * the difference.
 */
fun cardDueDate(createdIso: String, statementDay: Int, dueDay: Int): CardDue {
    val created = LocalDate.parse(createdIso.take(10))
    // Rolled to the next statement? Web compares the day of month, inclusive.
    val billMonthOffset = if (created.dayOfMonth <= statementDay) 0L else 1L
    // A due day BEFORE the statement day lands in the month after it.
    val dueMonthOffset = billMonthOffset + if (dueDay >= statementDay) 0L else 1L
    // `plusMonths` on the first of the month, then set the day: adding months
    // to a 29th-31st would clamp to a short month and silently move the date.
    val month = created.withDayOfMonth(1).plusMonths(dueMonthOffset)
    return CardDue(
        dueOn = month.withDayOfMonth(dueDay).toString(),
        thisCycle = billMonthOffset == 0L,
    )
}
