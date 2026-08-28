package com.sanvya.app.domain.splits

import com.sanvya.app.domain.js.jsNumber
import com.sanvya.app.domain.js.jsRound
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.receipts.splitByWeights
import com.sanvya.app.domain.receipts.splitEqual

/**
 * The split editor on Add transaction, as arithmetic.
 *
 * Ported from the `splitPlan` useMemo in `apps/web/app/transactions/new/page.tsx`
 * -- the single largest block of web behaviour that was missing from both native
 * ports, and the one that cascades: without it there is no "paid for someone
 * else", no auto-split trip, no `?split=` entry, and Edit's SplitBanner has
 * nothing to explain.
 *
 * It is here rather than in two screens because it is entirely rules and the
 * rules decide money. What each person owes, whether the numbers add up, and
 * whether Save is allowed at all are computed once and pinned by vectors.
 *
 * **One deliberate divergence from web, and it is the ×100 again.** Web's
 * `toMinor` is `Math.round(Number(v) * 100)`, the same hardcoded constant the
 * de-hardcoding programme is removing everywhere else. Here it is worse than
 * cosmetic: an exact-mode split of a ¥3000 dinner would read every typed share
 * as a hundredth of itself and refuse to balance, so the user could not save at
 * all. This uses `fromMajor(major, currency)`. For INR, USD and EUR the two are
 * byte-identical; for JPY they differ, and a vector pins the difference.
 *
 * Mirrors iOS's SplitPlan.swift.
 */

/** Web's `SplitMode`. The strings are the values written to the database. */
object SplitModes {
    const val EQUAL = "equal"
    const val EXACT = "exact"
    const val PERCENT = "percent"
}

/** One participant, as `createSplitExpense` wants them. */
data class SplitParticipantPlan(
    val userId: String,
    /** Percent in percent mode, minor units in exact mode, null when equal. */
    val value: Double?,
)

/** One payer, as `createSplitExpense` wants them. */
data class SplitPayerPlan(
    val userId: String,
    val paidMinor: Long,
    /** True for the current user -- only their leg carries an account. */
    val isMe: Boolean,
)

/** Everything the editor state implies. */
data class SplitPlan(
    /** Per-participant share, in [memberIds] order. */
    val shares: List<Long>,
    val sharesSum: Long,
    /** The typed percentages, summed. Only meaningful in percent mode. */
    val percentSum: Double,
    val paidSum: Long,
    /** Whether Save may proceed. */
    val valid: Boolean,
    val participants: List<SplitParticipantPlan>,
    /** Payers with a non-zero amount. Web drops the zero legs before writing. */
    val payers: List<SplitPayerPlan>,
)

/**
 * Compute the plan.
 *
 * [shareText] and [paidText] are the RAW field contents, keyed by user id,
 * because that is what the user typed and rounding them earlier would hide a
 * disagreement the editor is supposed to surface.
 */
@Suppress("LongParameterList")
fun splitPlan(
    groupId: String,
    mode: String,
    memberIds: List<String>,
    me: String,
    totalMinor: Long,
    currency: String,
    shareText: Map<String, String>,
    multiPayer: Boolean,
    paidText: Map<String, String>,
    hasAccount: Boolean,
): SplitPlan {
    // Web's `Number(v) || 0` -- an unparseable field is zero, not a refusal.
    fun number(key: String, source: Map<String, String>): Double {
        val v = jsNumber(source[key].orEmpty())
        return if (v.isNaN()) 0.0 else v
    }
    fun minor(key: String, source: Map<String, String>): Long =
        fromMajor(number(key, source), currency).amount

    val n = memberIds.size
    val shares = when (mode) {
        SplitModes.PERCENT -> splitByWeights(totalMinor, memberIds.map { number(it, shareText) })
        SplitModes.EXACT -> memberIds.map { minor(it, shareText) }
        else -> splitEqual(totalMinor, n)
    }
    val sharesSum = shares.sum()
    val percentSum = memberIds.sumOf { number(it, shareText) }

    val payerList = if (multiPayer) {
        memberIds.map { SplitPayerPlan(it, minor(it, paidText), it == me) }
    } else {
        // Single payer: the whole amount is mine. Web writes exactly this, and
        // it is why the account is required below.
        listOf(SplitPayerPlan(me, totalMinor, true))
    }
    val paidSum = payerList.sumOf { it.paidMinor }
    val myPaid = payerList.filter { it.isMe }.sumOf { it.paidMinor }

    val modeBalances = when (mode) {
        SplitModes.EXACT -> sharesSum == totalMinor
        // `Math.round` on the SUM, not on each share: three people at 33.33%
        // sum to 99.99 and are accepted, which is the whole reason the rounding
        // is here rather than a strict equality.
        SplitModes.PERCENT -> jsRound(percentSum) == 100.0
        else -> true
    }

    val valid = groupId.isNotEmpty() &&
        n >= 2 &&
        totalMinor > 0 &&
        memberIds.contains(me) &&
        modeBalances &&
        (!multiPayer || paidSum == totalMinor) &&
        // An account is needed only when MY money moved. A split where someone
        // else paid every rupee records what I owe and touches no account of
        // mine, so demanding one would block a legitimate entry.
        (myPaid <= 0 || hasAccount)

    return SplitPlan(
        shares = shares,
        sharesSum = sharesSum,
        percentSum = percentSum,
        paidSum = paidSum,
        valid = valid,
        participants = memberIds.map { key ->
            SplitParticipantPlan(
                userId = key,
                value = when (mode) {
                    SplitModes.PERCENT -> number(key, shareText)
                    SplitModes.EXACT -> minor(key, shareText).toDouble()
                    else -> null
                },
            )
        },
        payers = payerList.filter { it.paidMinor > 0 },
    )
}

/**
 * Whether the split editor is actually in play.
 *
 * Web's `splitActive`: expense only, toggle on, a group chosen, and at least two
 * people. Anything less and the transaction is written as an ordinary one --
 * which is why this is a separate question from [SplitPlan.valid], and why a
 * half-filled editor does not block Save.
 */
fun splitActive(type: String, splitOn: Boolean, groupId: String, memberCount: Int): Boolean =
    type == "expense" && splitOn && groupId.isNotEmpty() && memberCount >= 2

/**
 * Whether "I paid for someone else" is in play.
 *
 * Web's `forOtherActive`, and the ordering matters: it is mutually exclusive
 * with the split toggle, so turning the split on wins. It is modelled as a 1:1
 * split where their share is 100% and mine is 0.
 */
fun forOtherActive(
    type: String,
    splitOn: Boolean,
    forOtherOn: Boolean,
    otherUserId: String,
    totalMinor: Long,
): Boolean = type == "expense" && !splitOn && forOtherOn && otherUserId.isNotEmpty() && totalMinor > 0

/**
 * The group an auto-split trip would preselect for a given date.
 *
 * Web looks for a group with `auto_split = 1` whose date range contains the
 * transaction's day; its own open end is `"9999-12-31"`, which is a sentinel
 * rather than a real date and is reproduced as one. Returns the FIRST match, as
 * `Array.find` does -- with two overlapping trips the earlier row wins, which
 * is arbitrary but is what the browser does.
 */
data class AutoSplitCandidate(val id: String, val startDate: String?, val endDate: String?, val autoSplit: Boolean)

fun autoSplitGroupFor(groups: List<AutoSplitCandidate>, dateIso: String): String? {
    val day = dateIso.take(10)
    return groups.firstOrNull { g ->
        g.autoSplit && g.startDate != null && day >= g.startDate && day <= (g.endDate ?: "9999-12-31")
    }?.id
}
