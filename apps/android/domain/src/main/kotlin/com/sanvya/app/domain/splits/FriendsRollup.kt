package com.sanvya.app.domain.splits

/**
 * Who owes whom, across the whole ledger rather than per group.
 *
 * Ported from the three `useMemo`s at the top of `apps/web/app/friends/page.tsx`.
 * It is here rather than in a screen because it is the answer to the question
 * the Friends page exists to ask, and because both ports were getting it wrong
 * in the same way: they read `overview.direct` ALONE, so somebody who owed you
 * from a trip simply did not appear. `GroupOverview.perUser` was computed,
 * returned, and never read.
 *
 * Mirrors iOS's FriendsRollup.swift.
 */

/** One person's net position with you. Positive means they owe you. */
data class PersonNet(val userId: String, val net: Long)

/**
 * Every 1:1 balance -- each group's per-user rollup plus the direct ones --
 * summed into one net per person.
 *
 * ORDER IS FIRST-APPEARANCE, not sorted: web accumulates into a `Map` and
 * spreads it, and a JS Map iterates in insertion order. The two callers below
 * sort; anything that does not, inherits this order, so it has to be the same
 * order on both platforms.
 *
 * Zero nets are dropped, as web does: a settled person is not a debt.
 */
fun friendNets(groupPerUser: List<List<PersonNet>>, direct: List<PersonNet>): List<PersonNet> {
    val totals = LinkedHashMap<String, Long>()
    for (group in groupPerUser) {
        for (b in group) totals[b.userId] = (totals[b.userId] ?: 0L) + b.net
    }
    for (d in direct) totals[d.userId] = (totals[d.userId] ?: 0L) + d.net
    return totals.entries.filter { it.value != 0L }.map { PersonNet(it.key, it.value) }
}

/** They owe you -- largest first. */
fun owedToYou(nets: List<PersonNet>): List<PersonNet> =
    nets.filter { it.net > 0 }.sortedByDescending { it.net }

/**
 * You owe them -- largest DEBT first.
 *
 * Web sorts ascending on a negative number, which puts the biggest debt at the
 * top. Sorting by absolute value descending would read the same here and be
 * wrong the moment a zero slipped through, so this keeps web's comparison.
 */
fun youOwe(nets: List<PersonNet>): List<PersonNet> =
    nets.filter { it.net < 0 }.sortedBy { it.net }

/**
 * Everyone you share a group with, INCLUDING the people you are square with.
 *
 * The two lists above drop a settled person by construction. A "Friends"
 * directory that only lists debts is a debt list; web's own comment says so,
 * and this is the function that makes it a directory.
 *
 * Sorted by the SIZE of the balance, then by name -- so the people you have
 * something outstanding with float to the top and the rest stay alphabetical.
 */
fun everyoneYouShareWith(
    groupMemberIds: List<List<String>>,
    direct: List<PersonNet>,
    nets: List<PersonNet>,
    names: Map<String, String>,
): List<PersonNet> {
    val netByUser = nets.associate { it.userId to it.net }
    val ids = LinkedHashSet<String>()
    for (group in groupMemberIds) ids.addAll(group)
    for (d in direct) ids.add(d.userId)
    return ids
        .map { PersonNet(it, netByUser[it] ?: 0L) }
        .sortedWith(
            compareByDescending<PersonNet> { kotlin.math.abs(it.net) }
                .thenBy { names[it.userId] ?: it.userId },
        )
}
