package com.sanvya.app.domain.splits

/**
 * Split display-collapse. Ported from apps/web/src/splits/collapse.ts.
 *
 * A single split expense writes up to three private ledger rows for you --
 * `own_share` (real account), `lend` (transfer to the virtual "Owed to me"
 * account when you overpaid) and `borrow` (expense on the virtual "I owe"
 * account when you underpaid). Those rows are REQUIRED for correct balances
 * and are never removed. But in transaction *lists* they read as 2-3 separate
 * rows for one real-world event, which is confusing -- so every posting of the
 * same expense collapses into ONE row, badged "Split".
 *
 * The row shows the **total you paid** (own_share + lend); if you paid nothing,
 * it falls back to your share so the row isn't a meaningless zero.
 *
 * Web keeps this in a React hook, so the query lives in `:data` and only the
 * arithmetic lives here -- which is also what makes it vector-testable.
 * Mirrors apps/ios/Domain/Sources/Domain/SplitsCollapse.swift.
 */

/** One `expense_postings` row joined to its transaction -- web's `Row`. */
data class SplitPosting(
    val transactionId: String,
    val expenseId: String,
    val role: String,
    val amountMinor: Long,
    val currency: String,
    val groupId: String?,
)

data class SplitInfo(
    val expenseId: String,
    val groupId: String?,
    /** Amount shown on the collapsed row -- total you actually paid. */
    val displayPaid: Long,
    /** Your share of the expense (what it cost you). */
    val yourShare: Long,
    /** You overpaid and are owed this back. */
    val owedToYou: Long,
    /** You underpaid and owe this. */
    val youOwe: Long,
    val currency: String,
)

/**
 * Transaction id -> its split expense info. Only split postings appear; a
 * transaction absent from the map is an ordinary row.
 *
 * The currency and group id come from the FIRST posting seen for an expense,
 * which is web's behaviour (its aggregate seeds them once and never revisits).
 * Postings of one expense are written together and always share both.
 */
fun splitInfoByTransaction(rows: List<SplitPosting>): Map<String, SplitInfo> {
    data class Agg(
        var own: Long = 0,
        var lend: Long = 0,
        var borrow: Long = 0,
        val currency: String,
        val groupId: String?,
        val txIds: MutableList<String> = mutableListOf(),
    )

    // LinkedHashMap: insertion order, so the output map's iteration order
    // follows the input's. Nothing depends on it today, but a vector compares
    // serialised JSON and a HashMap would make that comparison arbitrary.
    val byExpense = LinkedHashMap<String, Agg>()
    for (r in rows) {
        val agg = byExpense.getOrPut(r.expenseId) { Agg(currency = r.currency, groupId = r.groupId) }
        when (r.role) {
            "own_share" -> agg.own += r.amountMinor
            "lend" -> agg.lend += r.amountMinor
            "borrow" -> agg.borrow += r.amountMinor
        }
        agg.txIds.add(r.transactionId)
    }

    val out = LinkedHashMap<String, SplitInfo>()
    for ((expenseId, a) in byExpense) {
        val paid = a.own + a.lend
        val info = SplitInfo(
            expenseId = expenseId,
            groupId = a.groupId,
            displayPaid = if (paid > 0) paid else a.borrow,
            yourShare = a.own + a.borrow,
            owedToYou = a.lend,
            youOwe = a.borrow,
            currency = a.currency,
        )
        for (txId in a.txIds) out[txId] = info
    }
    return out
}

/**
 * The ids that survive collapse, in order: the first posting seen for each
 * split expense is kept, its siblings dropped. Non-split ids pass through.
 *
 * Ids rather than web's generic `<T extends { id: string }>`: the caller
 * already has the rows and can look each one up, and a generic here would be
 * one more thing the golden vectors could not exercise directly.
 */
fun collapseSplitRowIds(orderedIds: List<String>, infoByTx: Map<String, SplitInfo>): List<String> {
    val seen = mutableSetOf<String>()
    val out = mutableListOf<String>()
    for (id in orderedIds) {
        val info = infoByTx[id]
        if (info == null) {
            out.add(id)
            continue
        }
        if (!seen.add(info.expenseId)) continue // sibling of an already-shown split
        out.add(id)
    }
    return out
}
