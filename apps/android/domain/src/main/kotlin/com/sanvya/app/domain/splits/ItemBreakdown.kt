package com.sanvya.app.domain.splits

/**
 * The per-item view of an itemised bill. Ported from the render-time arithmetic
 * in apps/web/src/splits/ItemBreakdown.tsx.
 *
 * Read-only by design, exactly as web is: editing a split after the fact means
 * rewriting ledger postings, which is the edit-transaction flow's job. This
 * answers "why do I owe this much?", which is the question people actually ask
 * after a group dinner -- and the one nobody could ask on either phone, because
 * `expense_items` had no UI at all.
 *
 * The balances are NOT computed from these numbers. `expense_participants` is
 * still the only thing any balance reads; item shares are a BREAKDOWN that
 * already rolled up into it when the bill was written (see
 * `createSplitExpenseItemized`). Nothing here can move what anybody owes.
 *
 * Web keeps this inside a React component, so only the arithmetic lives here --
 * which is also what makes it vector-testable.
 * Mirrors apps/ios/Domain/Sources/Domain/ItemBreakdown.swift.
 */

/** One `expense_items` row, reduced to what the arithmetic reads. */
data class ItemBreakdownItem(
    val id: String,
    val amount: Long,
)

/** One `expense_item_shares` row: what [userId] is on the hook for on [itemId]. */
data class ItemBreakdownShare(
    val itemId: String,
    val userId: String,
    val shareAmount: Long,
)

/** A single person's slice of one line, for the row's caption. */
data class ItemBreakdownLineShare(val userId: String, val amount: Long)

data class ItemBreakdownLine(
    val itemId: String,
    /** The number shown on the right: one person's slice when filtered, the whole line when not. */
    val amount: Long,
    /**
     * Who is on this line, zero slices dropped. EMPTY while a person filter is
     * on -- web hides the caption then, because "Ana ₹120 · Bo ₹80" under a row
     * that already says "Ana" is noise.
     */
    val shares: List<ItemBreakdownLineShare>,
)

data class ItemBreakdownView(
    /** Everyone with a slice of anything, for the filter chips. */
    val everyone: List<String>,
    val lines: List<ItemBreakdownLine>,
    /** The sum of what is actually shown -- the filtered person's total, or the bill's. */
    val total: Long,
)

/**
 * [items] in `sort` order and [shares] in query order, both as the repository
 * read them, plus the person the chips have selected (null or "" = everyone).
 *
 * Ordering is load-bearing and is taken from the ROW ORDER, not re-sorted: web
 * builds two nested JS Maps out of the same rows and reads their insertion
 * order straight back out for the chip row and every caption. A hash-ordered
 * map here would give the two clients different chip orders for the same bill.
 */
fun itemBreakdown(
    items: List<ItemBreakdownItem>,
    shares: List<ItemBreakdownShare>,
    filterUserId: String?,
): ItemBreakdownView {
    val byItem = LinkedHashMap<String, LinkedHashMap<String, Long>>()
    for (share in shares) {
        byItem.getOrPut(share.itemId) { LinkedHashMap() }[share.userId] = share.shareAmount
    }

    val everyone = LinkedHashSet<String>()
    for (perUser in byItem.values) everyone.addAll(perUser.keys)

    // Web's filter state is a String whose empty value means "everyone", so an
    // empty id has to mean the same here -- otherwise the "Everyone" chip would
    // filter for a user whose id is "" and show nothing.
    val filter = filterUserId?.takeIf { it.isNotEmpty() }

    // A line where the filtered person owes nothing is not their line at all.
    val visible = if (filter == null) items else items.filter { (byItem[it.id]?.get(filter) ?: 0L) != 0L }

    val lines = visible.map { item ->
        val perUser = byItem[item.id]
        ItemBreakdownLine(
            itemId = item.id,
            amount = if (filter == null) item.amount else (perUser?.get(filter) ?: 0L),
            shares = if (filter == null) {
                (perUser ?: emptyMap()).entries
                    .filter { it.value != 0L }
                    .map { ItemBreakdownLineShare(it.key, it.value) }
            } else {
                emptyList()
            },
        )
    }

    return ItemBreakdownView(
        everyone = everyone.toList(),
        lines = lines,
        total = lines.sumOf { it.amount },
    )
}
