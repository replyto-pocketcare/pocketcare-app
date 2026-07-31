package care.pocket.domain.splitsinsights

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import kotlin.math.max
import kotlin.math.min

// Ported from packages/core/splits-insights/src/index.ts (P1.4a). Correctness
// is judged against tools/golden-vectors/vectors/splits-insights.json, not a
// fresh reading of the TS -- see docs/plans/native-mobile-apps.md section 5
// and CLAUDE.md golden rule 8 ("web is the spec"). Unlike every domain ported
// so far, this one's exported vectors never wrap results with amt()/mny() --
// every field here (net, youCovered, lent, value, ...) is a PLAIN JSON
// number, confirmed by reading the actual generated splits-insights.json,
// not assumed from the earlier domains' string-money convention.

private val DATE_ONLY = Regex("^\\d{4}-\\d{2}-\\d{2}$")

/**
 * Epoch millis for an ISO string that's either date-only ("2026-01-01",
 * which JS's `new Date(...)` treats as UTC midnight per the ECMA-262 Date
 * Time String Format) or a full instant ("2026-01-01T00:00:00Z"). Every
 * vector in this domain uses one of these two exact forms, never a
 * timezone-relative one, so no other case needs handling.
 */
private fun parseIsoMillis(iso: String): Long =
    if (DATE_ONLY.matches(iso)) {
        LocalDate.parse(iso).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli()
    } else {
        Instant.parse(iso).toEpochMilli()
    }

private const val DAY_MS = 86_400_000.0

internal fun daysBetween(fromIso: String, toIso: String): Double =
    (parseIsoMillis(toIso) - parseIsoMillis(fromIso)) / DAY_MS

data class DebtLike(val at: String, val amount: Long)
data class PaymentLike(val at: String, val amount: Long)

data class AverageSettleResult(val avgDays: Double?, val clearedCount: Int)

private class QueuedDebt(val at: String, var left: Long)

/**
 * FIFO age-of-debt at settlement -- see the TS source's own doc comment for
 * the "why" (weighted by chunk size; a prepayment before any debt exists is
 * ignored, not counted as negative-age).
 */
fun averageSettleDays(debts: List<DebtLike>, payments: List<PaymentLike>): AverageSettleResult {
    val queue = debts.filter { it.amount > 0 }.sortedBy { it.at }.map { QueuedDebt(it.at, it.amount) }
    val pays = payments.filter { it.amount > 0 }.sortedBy { it.at }

    var weighted = 0.0
    var weight = 0.0
    var cleared = 0
    var head = 0

    for (pay in pays) {
        var remaining = pay.amount
        while (remaining > 0 && head < queue.size) {
            val debt = queue[head]
            // Debts incurred after this payment can't have been cleared by it.
            if (debt.at > pay.at) break
            val chunk = min(remaining, debt.left)
            val age = max(0.0, daysBetween(debt.at, pay.at))
            weighted += age * chunk
            weight += chunk
            debt.left -= chunk
            remaining -= chunk
            if (debt.left == 0L) {
                cleared++
                head++
            }
        }
    }

    return AverageSettleResult(if (weight > 0) weighted / weight else null, cleared)
}

data class FriendEdge(val friendId: String, val groupId: String, val at: String, val amount: Long)
data class FriendSettlement(val friendId: String, val at: String, val amount: Long)
data class Contribution(val userId: String, val paid: Long, val share: Long)

data class FriendStats(
    val friendId: String,
    var net: Long = 0,
    var youCovered: Long = 0,
    var theyCovered: Long = 0,
    var lent: Long = 0,
    var borrowed: Long = 0,
    var groups: Int = 0,
    var groupsOwing: Int = 0,
    var groupsOwed: Int = 0,
    var expenses: Int = 0,
    var avgSettleDays: Double? = null,
    var settledDebts: Int = 0,
)

/** Per-friend rollup. Friends with no shared history are omitted. */
fun computeFriendStats(
    edges: List<FriendEdge>,
    settlements: List<FriendSettlement>,
    contributions: Map<String, List<Contribution>>? = null,
): List<FriendStats> {
    // LinkedHashMap, not HashMap: iteration order must match JS's Map
    // insertion order, since the returned list's order is part of the
    // contract pickFriendInsights et al build on.
    val byFriend = LinkedHashMap<String, FriendStats>()
    val perGroup = HashMap<String, LinkedHashMap<String, Long>>()

    fun ensure(friendId: String): FriendStats = byFriend.getOrPut(friendId) {
        perGroup[friendId] = LinkedHashMap()
        FriendStats(friendId)
    }

    for (e in edges) {
        val s = ensure(e.friendId)
        s.net += e.amount
        s.expenses += 1
        if (e.amount > 0) s.youCovered += e.amount else if (e.amount < 0) s.theyCovered += -e.amount
        val g = perGroup.getValue(e.friendId)
        g[e.groupId] = (g[e.groupId] ?: 0L) + e.amount
    }

    for (st in settlements) {
        val s = ensure(st.friendId)
        // They paid you -> reduces what they owe. You paid them -> reduces what you owe.
        s.net -= st.amount
    }

    for ((friendId, s) in byFriend) {
        val g = perGroup.getValue(friendId)
        s.groups = g.size
        for (net in g.values) {
            if (net > 0) s.groupsOwing += 1 else if (net < 0) s.groupsOwed += 1
        }

        val debts = edges.filter { it.friendId == friendId && it.amount > 0 }.map { DebtLike(it.at, it.amount) }
        val pays = settlements.filter { it.friendId == friendId && it.amount > 0 }.map { PaymentLike(it.at, it.amount) }
        val result = averageSettleDays(debts, pays)
        s.avgSettleDays = result.avgDays
        s.settledDebts = result.clearedCount

        for (c in contributions?.get(friendId) ?: emptyList()) {
            val delta = c.paid - c.share
            if (delta > 0) s.lent += delta else if (delta < 0) s.borrowed += -delta
        }
    }

    return byFriend.values.toList()
}

data class FriendInsight(val key: String, val friendId: String, val value: Double, val evidence: Int)

/** Minimum evidence before a ranking is asserted at all. */
object Thresholds {
    const val CONSISTENT_GROUPS = 2
    const val SETTLED_DEBTS = 2
    const val MIN_AMOUNT = 100
}

private fun <T> best(xs: List<T>, score: (T) -> Double): T? {
    var top: T? = null
    var topScore = Double.NEGATIVE_INFINITY
    for (x in xs) {
        val s = score(x)
        if (s > topScore) {
            topScore = s
            top = x
        }
    }
    return top
}

/**
 * Pick the headline insights. Returns only what the data actually supports --
 * an empty list is a valid, honest answer for a thin ledger.
 */
fun pickFriendInsights(stats: List<FriendStats>): List<FriendInsight> {
    val out = mutableListOf<FriendInsight>()
    fun push(key: String, s: FriendStats?, value: Double, evidence: Int) {
        if (s != null && value >= Thresholds.MIN_AMOUNT) out.add(FriendInsight(key, s.friendId, value, evidence))
    }

    val lender = best(stats.filter { it.lent > 0 }) { it.lent.toDouble() }
    push("biggest_lender", lender, (lender?.lent ?: 0L).toDouble(), lender?.expenses ?: 0)

    val owesYou = best(stats.filter { it.net > 0 }) { it.net.toDouble() }
    push("owes_you_most", owesYou, (owesYou?.net ?: 0L).toDouble(), owesYou?.expenses ?: 0)

    val youOwe = best(stats.filter { it.net < 0 }) { -it.net.toDouble() }
    push("you_owe_most", youOwe, if (youOwe != null) -youOwe.net.toDouble() else 0.0, youOwe?.expenses ?: 0)

    // "Always" means exactly that: every shared group lands the same way,
    // across at least CONSISTENT_GROUPS of them. One-sided by construction.
    val alwaysOwes = best(stats.filter { it.groupsOwing >= Thresholds.CONSISTENT_GROUPS && it.groupsOwed == 0 }) { it.groupsOwing.toDouble() }
    if (alwaysOwes != null) {
        out.add(FriendInsight("always_owes", alwaysOwes.friendId, alwaysOwes.groupsOwing.toDouble(), alwaysOwes.groups))
    }

    val alwaysOwed = best(stats.filter { it.groupsOwed >= Thresholds.CONSISTENT_GROUPS && it.groupsOwing == 0 }) { it.groupsOwed.toDouble() }
    if (alwaysOwed != null) {
        out.add(FriendInsight("always_owed", alwaysOwed.friendId, alwaysOwed.groupsOwed.toDouble(), alwaysOwed.groups))
    }

    val settlers = stats.filter { it.avgSettleDays != null && it.settledDebts >= Thresholds.SETTLED_DEBTS }
    if (settlers.size >= 2) {
        val fastest = best(settlers) { -(it.avgSettleDays!!) }
        val slowest = best(settlers) { it.avgSettleDays!! }
        // Only worth saying when they're actually different people.
        if (fastest != null && slowest != null && fastest.friendId != slowest.friendId) {
            out.add(FriendInsight("fastest_settler", fastest.friendId, fastest.avgSettleDays!!, fastest.settledDebts))
            out.add(FriendInsight("slowest_settler", slowest.friendId, slowest.avgSettleDays!!, slowest.settledDebts))
        }
    }

    return out
}
