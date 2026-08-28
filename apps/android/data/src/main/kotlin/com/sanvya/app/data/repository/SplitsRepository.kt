package com.sanvya.app.data.repository

/**
 * Read/write facade for shared expenses between people/groups (P2.5):
 * split_groups, split_group_members, expenses, expense_participants,
 * settlements, connections. Mirrors apps/web/src/splits/write.ts and
 * apps/web/src/splits/hooks.ts exactly -- there is NO dedicated repository
 * class for this domain in packages/data (confirmed by reading both files
 * there in full); the web app instead builds directly on the generic
 * insertRow/updateRow helpers plus raw useQuery SQL, so THIS file's
 * query/write shapes are the actual spec (CLAUDE.md golden rule 8), not a
 * design of convenience.
 *
 * Balance math is never recomputed here: every derived balance goes through
 * the already-ported com.sanvya.app.domain.splitsmath.pairwiseEdges (P1.4a) and
 * com.sanvya.app.domain.splitsinsights (also P1.4a), exactly mirroring
 * hooks.ts's own computeBalances()/useFriendInsights().
 *
 * The itemized-bill write path (apps/web/src/splits/writeItemized.ts) landed
 * 2026-08-27 -- see createSplitExpenseItemized below. It writes
 * expense_items/expense_item_shares as a BREAKDOWN and still rolls up into
 * expense_participants, so none of the balance math above knows it exists.
 *
 * Deliberately OUT of scope for this pass (documented, not an oversight):
 * - createInvite/acceptInvite (apps/web/src/splits/write.ts) -- these call
 *   Supabase Edge Functions over HTTP, not the local PowerSync DB. That's
 *   networking/auth-adjacent infrastructure, not a SQLite repository
 *   concern, and belongs with P2.4 (auth) or a future networking layer.
 *
 * Table columns confirmed against PocketCareSchema.kt (P2.1) and
 * supabase/migrations (0011 base + 0040/0041 additions), not assumed.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getBooleanOptional
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.receipts.LineAssignment
import com.sanvya.app.domain.receipts.ReceiptDraft
import com.sanvya.app.domain.receipts.allocateReceipt
import com.sanvya.app.domain.receipts.isCharge
import com.sanvya.app.domain.receipts.reconcile
import com.sanvya.app.domain.receipts.splitByWeights
import com.sanvya.app.domain.receipts.splitEqual
import com.sanvya.app.domain.splitsinsights.Contribution
import com.sanvya.app.domain.splitsinsights.FriendEdge
import com.sanvya.app.domain.splitsinsights.FriendInsight
import com.sanvya.app.domain.splitsinsights.FriendSettlement
import com.sanvya.app.domain.splitsinsights.FriendStats
import com.sanvya.app.domain.splitsinsights.computeFriendStats
import com.sanvya.app.domain.splitsinsights.pickFriendInsights
import com.sanvya.app.domain.splitsmath.Party
import com.sanvya.app.domain.splitsmath.pairwiseEdges
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.combine

data class SplitGroup(
    val id: String,
    val createdBy: String,
    val name: String,
    val kind: String,
    val isDirect: Boolean,
    val startDate: String?,
    val endDate: String?,
    val autoSplit: Boolean,
    val defaultMode: String,
    val currency: String,
)

data class GroupExpense(
    val id: String,
    val description: String?,
    val amount: Long,
    val currency: String,
    val occurredAt: String,
    val hasItems: Boolean,
)

/** Disputed settlements are already excluded at the query level -- matches
 * every settlements read in hooks.ts; missing that filter silently
 * corrupts a balance. */
data class GroupSettlement(
    val id: String,
    val fromUser: String,
    val toUser: String,
    val amount: Long,
    val currency: String?,
    val at: String,
    val status: String?,
)

data class UserProfile(val id: String, val name: String, val email: String?)

/** + = they owe you. */
data class FriendBalance(val userId: String, val net: Long)

data class ParticipantInput(val userId: String, val value: Double? = null)
data class PayerInput(val userId: String, val paid: Long, val accountId: String? = null)

/** [mode] is one of "equal" | "exact" | "percent" -- kept as a raw String
 * (not an enum) matching this port's established convention for DB `type`-
 * shaped columns elsewhere (transactions.type, accounts.type, ...). */
/**
 * Per-line participants and mode, plus who paid. Mirrors web's
 * `ItemizedSplitInput` in `src/splits/writeItemized.ts`.
 */
data class ItemizedSplitInput(
    val groupId: String,
    val draft: ReceiptDraft,
    /** Keyed by `ReceiptLine.id`. */
    val assignments: List<LineAssignment>,
    /** Who actually paid, and from which account. Usually just you. */
    val payers: List<PayerInput>,
    val categoryId: String? = null,
    val note: String? = null,
    val occurredAt: String,
)

class ItemizedSplitException(message: String) : Exception(message)

data class SplitExpenseInput(
    val groupId: String,
    val mode: String,
    val total: Money,
    val participants: List<ParticipantInput>,
    val payers: List<PayerInput>,
    val categoryId: String? = null,
    val description: String? = null,
    val note: String? = null,
    val occurredAt: String,
)

data class PendingSettlement(
    val id: String,
    val fromUser: String,
    val toUser: String,
    val amount: Long,
    val currency: String,
    val groupId: String,
    val status: String,
    val upiRef: String?,
    val createdAt: String,
)

data class GroupOverview(
    val group: SplitGroup,
    /** Other members, excludes the caller, in join order. */
    val memberIds: List<String>,
    val peopleCount: Int,
    val net: Long,
    val perUser: List<FriendBalance>,
)

data class SplitOverview(
    val netPosition: Long,
    val owed: Long,
    val owe: Long,
    val groups: List<GroupOverview>,
    val direct: List<FriendBalance>,
)

data class PersonLine(val id: String, val kind: String, val description: String, val date: String, val net: Long)

private data class Part(val expenseId: String, val groupId: String, val userId: String, val paidAmount: Long, val shareAmount: Long)
private data class Sett(val groupId: String, val fromUser: String, val toUser: String, val amount: Long)
private data class SettRow(val id: String, val fromUser: String, val toUser: String, val amount: Long, val at: String)

private fun groupMapper(cursor: com.powersync.db.SqlCursor): SplitGroup = SplitGroup(
    id = cursor.getString("id"),
    createdBy = cursor.getString("created_by"),
    name = cursor.getString("name"),
    kind = cursor.getString("kind"),
    isDirect = cursor.getBooleanOptional("is_direct") ?: false,
    startDate = cursor.getStringOptional("start_date"),
    endDate = cursor.getStringOptional("end_date"),
    autoSplit = cursor.getBooleanOptional("auto_split") ?: false,
    defaultMode = cursor.getString("default_mode"),
    currency = cursor.getString("currency"),
)

private fun expenseMapper(cursor: com.powersync.db.SqlCursor): GroupExpense = GroupExpense(
    id = cursor.getString("id"),
    description = cursor.getStringOptional("description"),
    amount = cursor.getLong("amount"),
    currency = cursor.getString("currency"),
    occurredAt = cursor.getString("occurred_at"),
    hasItems = cursor.getBooleanOptional("has_items") ?: false,
)

private fun settlementMapper(cursor: com.powersync.db.SqlCursor): GroupSettlement = GroupSettlement(
    id = cursor.getString("id"),
    fromUser = cursor.getString("from_user"),
    toUser = cursor.getString("to_user"),
    amount = cursor.getLong("amount"),
    currency = cursor.getStringOptional("currency"),
    at = cursor.getString("at"),
    status = cursor.getStringOptional("status"),
)

/** Mirrors hooks.ts's computeBalances(): folds every expense's participants
 * through pairwiseEdges (per-expense, so multi-payer math stays correct),
 * then nets settlements on top. Never recomputed differently in two places
 * in this file -- every balance read (friend/group/overview) routes
 * through this one function, matching the TS source's own single-
 * implementation discipline. */
private fun computeBalances(parts: List<Part>, settlements: List<Sett>, me: String): List<FriendBalance> {
    val byExpense = LinkedHashMap<String, MutableList<Party>>()
    for (p in parts) {
        byExpense.getOrPut(p.expenseId) { mutableListOf() }.add(Party(p.userId, p.shareAmount, p.paidAmount))
    }
    val net = LinkedHashMap<String, Long>()
    for ((_, parties) in byExpense) {
        for (e in pairwiseEdges(parties, me)) net[e.userId] = (net[e.userId] ?: 0L) + e.amount
    }
    for (s in settlements) {
        if (s.toUser == me) net[s.fromUser] = (net[s.fromUser] ?: 0L) - s.amount
        else if (s.fromUser == me) net[s.toUser] = (net[s.toUser] ?: 0L) + s.amount
    }
    return net.entries.map { (userId, n) -> FriendBalance(userId, n) }
}

private fun computeShares(mode: String, total: Money, participants: List<ParticipantInput>): List<Long> {
    val n = participants.size
    return when (mode) {
        "equal" -> splitEqual(total.amount, n)
        "percent" -> splitByWeights(total.amount, participants.map { it.value ?: 0.0 })
        else -> participants.map { maxOf(0L, Math.round(it.value ?: 0.0)) }
    }
}

class SplitsRepository(
    private val db: PowerSyncDatabase,
    private val ledger: LedgerRepository,
) {
    // ---- reads (reactive) ----

    fun watchGroups(includeDirect: Boolean = false): Flow<List<SplitGroup>> {
        val extra = if (includeDirect) "" else "AND IFNULL(is_direct,0)=0"
        return db.watch(
            sql = """SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
                FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 $extra ORDER BY created_at DESC""",
            mapper = ::groupMapper,
        )
    }

    fun watchGroupMemberIds(groupId: String): Flow<List<String>> = db.watch(
        sql = "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL ORDER BY created_at",
        parameters = listOf(groupId),
        mapper = { cursor -> cursor.getString("user_id") },
    )

    /**
     * Every membership row, grouped by group.
     *
     * Web queries the whole table once (`SELECT group_id, user_id FROM
     * split_group_members`) because the Add-transaction split editor has to
     * answer "who is in the group the user just picked" without a round trip
     * per group. The table is small -- one row per person per group -- and one
     * watch is cheaper than a watch that restarts on every picker change.
     */
    fun watchAllGroupMembers(): Flow<Map<String, List<String>>> = db.watch(
        sql = """SELECT group_id, user_id FROM split_group_members
            WHERE deleted_at IS NULL ORDER BY created_at""",
        mapper = { cursor -> cursor.getString("group_id") to cursor.getString("user_id") },
    ).map { rows ->
        // Insertion order preserved: web renders members in `created_at` order
        // and a re-sort here would give the two clients different chip orders.
        val out = LinkedHashMap<String, MutableList<String>>()
        for ((groupId, userId) in rows) out.getOrPut(groupId) { mutableListOf() }.add(userId)
        out
    }

    fun watchGroupExpenses(groupId: String): Flow<List<GroupExpense>> = db.watch(
        sql = "SELECT id, description, amount, currency, occurred_at, has_items FROM expenses WHERE group_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC",
        parameters = listOf(groupId),
        mapper = ::expenseMapper,
    )

    fun watchGroupSettlements(groupId: String): Flow<List<GroupSettlement>> = db.watch(
        sql = """SELECT id, from_user, to_user, amount, currency, COALESCE(settled_at, created_at) AS at, status
            FROM settlements WHERE group_id = ? AND deleted_at IS NULL AND IFNULL(status,'confirmed') <> 'disputed' ORDER BY at DESC""",
        parameters = listOf(groupId),
        mapper = ::settlementMapper,
    )

    /** Users connected to [userId] (accepted invites / shared groups). */
    fun watchConnections(userId: String): Flow<List<UserProfile>> = db.watch(
        sql = """SELECT p.id AS id, p.display_name AS display_name, p.email AS email
            FROM connections c JOIN profiles p ON p.id = (CASE WHEN c.user_a = ? THEN c.user_b ELSE c.user_a END)
            WHERE c.deleted_at IS NULL AND (c.user_a = ? OR c.user_b = ?)""",
        parameters = listOf(userId, userId, userId),
        mapper = { cursor ->
            val name = cursor.getStringOptional("display_name")
            val email = cursor.getStringOptional("email")
            UserProfile(cursor.getString("id"), if (!name.isNullOrEmpty()) name else (email?.substringBefore("@") ?: "Someone"), email)
        },
    )

    private fun watchAllParticipants(): Flow<List<Part>> = db.watch(
        sql = """SELECT expense_id, group_id, user_id, paid_amount, share_amount FROM expense_participants
            WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM expenses WHERE deleted_at IS NULL)""",
        mapper = { cursor -> Part(cursor.getString("expense_id"), cursor.getString("group_id"), cursor.getString("user_id"), cursor.getLong("paid_amount"), cursor.getLong("share_amount")) },
    )

    private fun watchAllSettlements(): Flow<List<Sett>> = db.watch(
        sql = "SELECT group_id, from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
        mapper = { cursor -> Sett(cursor.getString("group_id"), cursor.getString("from_user"), cursor.getString("to_user"), cursor.getLong("amount")) },
    )

    /** Global per-user balances across all of [userId]'s groups (reactive). */
    fun watchFriendBalances(userId: String): Flow<List<FriendBalance>> =
        combine(watchAllParticipants(), watchAllSettlements()) { parts, setts -> computeBalances(parts, setts, userId) }

    /** Per-user balances within one group (reactive). */
    fun watchGroupBalances(groupId: String, userId: String): Flow<List<FriendBalance>> {
        val parts: Flow<List<Part>> = db.watch(
            sql = "SELECT expense_id, group_id, user_id, paid_amount, share_amount FROM expense_participants WHERE group_id = ? AND deleted_at IS NULL",
            parameters = listOf(groupId),
            mapper = { cursor -> Part(cursor.getString("expense_id"), cursor.getString("group_id"), cursor.getString("user_id"), cursor.getLong("paid_amount"), cursor.getLong("share_amount")) },
        )
        val setts: Flow<List<Sett>> = db.watch(
            sql = "SELECT group_id, from_user, to_user, amount FROM settlements WHERE group_id = ? AND deleted_at IS NULL AND status <> 'disputed'",
            parameters = listOf(groupId),
            mapper = { cursor -> Sett(cursor.getString("group_id"), cursor.getString("from_user"), cursor.getString("to_user"), cursor.getLong("amount")) },
        )
        return combine(parts, setts) { p, s -> computeBalances(p, s, userId) }
    }

    /** Single group by id, one-shot -- added P3.9 (Splits screen, task #30)
     * for the group-detail screen; every other read in this class composes
     * the full list, which the detail screen doesn't need. */
    suspend fun getGroup(groupId: String): SplitGroup? = db.getOptional(
        sql = """SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
            FROM split_groups WHERE id = ? AND deleted_at IS NULL""",
        parameters = listOf(groupId),
        mapper = ::groupMapper,
    )

    // ---- reads (one-shot; these compose 3-4 queries into derived screen
    // data -- kept one-shot on BOTH platforms, not just iOS, since the
    // combine-of-N-queries wiring would otherwise roughly triple this
    // file's size for a Phase-2 Done-when that doesn't require live
    // reactivity here; see LedgerRepository's REACTIVITY NOTE for the
    // platform-asymmetry precedent this deliberately does NOT repeat) ----

    /** Everything the Splits ledger needs, computed in one pass. Matches
     * useSplitOverview() exactly, including folding direct (1:1) groups
     * into aggregate per-person balances rather than listing them as groups. */
    suspend fun splitOverview(userId: String): SplitOverview {
        val groups = db.getAll(
            sql = """SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
                FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 ORDER BY created_at DESC""",
            mapper = ::groupMapper,
        )
        val members = db.getAll(
            sql = "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL ORDER BY created_at",
            mapper = { cursor -> cursor.getString("group_id") to cursor.getString("user_id") },
        )
        val parts = db.getAll(
            sql = "SELECT group_id, expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            mapper = { cursor -> Part(cursor.getString("expense_id"), cursor.getString("group_id"), cursor.getString("user_id"), cursor.getLong("paid_amount"), cursor.getLong("share_amount")) },
        )
        val setts = db.getAll(
            sql = "SELECT group_id, from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            mapper = { cursor -> Sett(cursor.getString("group_id"), cursor.getString("from_user"), cursor.getString("to_user"), cursor.getLong("amount")) },
        )

        val partsByGroup = parts.groupBy { it.groupId }
        val settsByGroup = setts.groupBy { it.groupId }
        val membersByGroup = LinkedHashMap<String, MutableList<String>>()
        for ((groupId, uid) in members) membersByGroup.getOrPut(groupId) { mutableListOf() }.add(uid)

        val groupViews = mutableListOf<GroupOverview>()
        val direct = LinkedHashMap<String, Long>()
        var owed = 0L
        var owe = 0L

        for (g in groups) {
            val perUser = computeBalances(partsByGroup[g.id] ?: emptyList(), settsByGroup[g.id] ?: emptyList(), userId)
            val net = perUser.fold(0L) { acc, b -> acc + b.net }
            val allMembers = membersByGroup[g.id] ?: emptyList()
            val others = allMembers.filter { it != userId }
            owed += perUser.fold(0L) { acc, b -> acc + maxOf(0L, b.net) }
            owe += perUser.fold(0L) { acc, b -> acc + maxOf(0L, -b.net) }

            if (g.isDirect) {
                for (b in perUser) direct[b.userId] = (direct[b.userId] ?: 0L) + b.net
            } else {
                groupViews.add(
                    GroupOverview(
                        group = g,
                        memberIds = others,
                        peopleCount = if (allMembers.isNotEmpty()) allMembers.size else others.size + 1,
                        net = net,
                        perUser = perUser.filter { it.net != 0L },
                    ),
                )
            }
        }

        val directList = direct.entries.filter { it.value != 0L }.map { (userId2, net) -> FriendBalance(userId2, net) }
        return SplitOverview(netPosition = owed - owe, owed = owed, owe = owe, groups = groupViews, direct = directList)
    }

    /** Per-friend rollup + headline insights across every group [userId] shares.
     * Matches useFriendInsights() exactly: pairwise edges built here (the
     * balance maths), behavioural analysis delegated to the already-ported
     * splitsinsights domain (pure, P1.4a). */
    suspend fun friendInsights(userId: String): Pair<List<FriendStats>, List<FriendInsight>> {
        val parts = db.getAll(
            sql = "SELECT group_id, expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            mapper = { cursor -> Part(cursor.getString("expense_id"), cursor.getString("group_id"), cursor.getString("user_id"), cursor.getLong("paid_amount"), cursor.getLong("share_amount")) },
        )
        val exps = db.getAll(
            sql = "SELECT id, occurred_at FROM expenses WHERE deleted_at IS NULL",
            mapper = { cursor -> cursor.getString("id") to cursor.getString("occurred_at") },
        )
        val setts = db.getAll(
            sql = "SELECT from_user, to_user, amount, settled_at, created_at FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            mapper = { cursor ->
                Triple(cursor.getString("from_user"), cursor.getString("to_user"), cursor.getLong("amount")) to
                    (cursor.getStringOptional("settled_at") ?: cursor.getString("created_at"))
            },
        )

        val whenOf = exps.toMap()
        val byExpense = LinkedHashMap<String, Pair<String, MutableList<Party>>>()
        val contributions = LinkedHashMap<String, MutableList<Contribution>>()
        for (p in parts) {
            val slot = byExpense.getOrPut(p.expenseId) { p.groupId to mutableListOf() }
            slot.second.add(Party(p.userId, p.shareAmount, p.paidAmount))
            if (p.userId != userId) {
                contributions.getOrPut(p.userId) { mutableListOf() }.add(Contribution(p.userId, p.paidAmount, p.shareAmount))
            }
        }

        val edges = mutableListOf<FriendEdge>()
        for ((expenseId, groupAndParties) in byExpense) {
            val (groupId, parties) = groupAndParties
            val at = whenOf[expenseId] ?: continue
            for (e in pairwiseEdges(parties, userId)) {
                if (e.amount != 0L) edges.add(FriendEdge(e.userId, groupId, at, e.amount))
            }
        }

        val settlements = mutableListOf<FriendSettlement>()
        for ((triple, at) in setts) {
            val (fromUser, toUser, amount) = triple
            if (toUser == userId) settlements.add(FriendSettlement(fromUser, at, amount))
            else if (fromUser == userId) settlements.add(FriendSettlement(toUser, at, -amount))
        }

        val stats = computeFriendStats(edges, settlements, contributions)
        return stats to pickFriendInsights(stats)
    }

    /** The itemised ledger between [userId] and [otherId] across every group:
     * each shared expense's pairwise edge plus settlements, newest first,
     * with a running total. Matches usePersonLedger() exactly. */
    suspend fun personLedger(userId: String, otherId: String): Pair<List<PersonLine>, Long> {
        if (otherId.isEmpty() || userId.isEmpty()) return emptyList<PersonLine>() to 0L
        val parts = db.getAll(
            sql = "SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
            mapper = { cursor -> Triple(cursor.getString("expense_id"), cursor.getString("user_id"), cursor.getLong("paid_amount")) to cursor.getLong("share_amount") },
        )
        val exps = db.getAll(
            sql = "SELECT id, description, occurred_at FROM expenses WHERE deleted_at IS NULL",
            mapper = { cursor -> cursor.getString("id") to (cursor.getStringOptional("description") to cursor.getString("occurred_at")) },
        )
        val setts = db.getAll(
            sql = "SELECT id, from_user, to_user, amount, settled_at, created_at FROM settlements WHERE deleted_at IS NULL AND status <> 'disputed'",
            mapper = { cursor ->
                SettRow(
                    id = cursor.getString("id"),
                    fromUser = cursor.getString("from_user"),
                    toUser = cursor.getString("to_user"),
                    amount = cursor.getLong("amount"),
                    at = cursor.getStringOptional("settled_at") ?: cursor.getString("created_at"),
                )
            },
        )

        val byExpense = LinkedHashMap<String, MutableList<Party>>()
        for ((idUserPaid, share) in parts) {
            val (expenseId, uid, paid) = idUserPaid
            byExpense.getOrPut(expenseId) { mutableListOf() }.add(Party(uid, share, paid))
        }
        val meta = exps.toMap()
        val lines = mutableListOf<PersonLine>()
        var total = 0L

        for ((expenseId, parties) in byExpense) {
            val ids = parties.map { it.userId }
            if (userId !in ids || otherId !in ids) continue
            val edge = pairwiseEdges(parties, userId).find { it.userId == otherId } ?: continue
            if (edge.amount == 0L) continue
            val m = meta[expenseId]
            lines.add(PersonLine(expenseId, "expense", m?.first?.takeIf { it.isNotEmpty() } ?: "Expense", m?.second ?: "", edge.amount))
            total += edge.amount
        }
        for (row in setts) {
            val net = when {
                row.toUser == userId && row.fromUser == otherId -> -row.amount
                row.fromUser == userId && row.toUser == otherId -> row.amount
                else -> continue
            }
            lines.add(PersonLine(row.id, "settlement", if (net < 0) "They paid you back" else "You paid them back", row.at, net))
            total += net
        }

        val sorted = lines.sortedByDescending { it.date }
        return sorted to total
    }

    // ---- writes ----

    /** Get (or lazily create) the hidden virtual account that tracks money
     * others owe [userId] ("receivable") or [userId] owes others ("payable"),
     * per currency. Excluded from account pickers and net worth. NOTE: unlike
     * LedgerRepository.createAccount's fixed column list (matching the real
     * PowerSyncAccountRepository.create() spec), this writes kind/
     * include_in_net_worth directly -- because the real ensureVirtualAccount
     * uses the GENERIC insertRow helper, not the repository's create(), and
     * that generic helper writes whatever keys it's given. Two different
     * account-creation code paths for two different purposes, faithfully
     * mirrored as two different column sets here. */
    suspend fun ensureVirtualAccount(userId: String, kind: String, currency: String): String {
        val existing = db.getOptional(
            sql = "SELECT id FROM accounts WHERE user_id = ? AND kind = ? AND currency = ? AND deleted_at IS NULL LIMIT 1",
            parameters = listOf(userId, kind, currency),
            mapper = { cursor -> cursor.getString("id") },
        )
        if (existing != null) return existing
        val id = newId()
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO accounts (id,user_id,name,type,currency,icon,color,is_archived,include_in_net_worth,allow_negative,kind,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(
                id, userId,
                if (kind == "receivable") "Owed to me" else "I owe",
                "cash", currency, null,
                if (kind == "receivable") "#5f7a52" else "#a8503a",
                0L, 0L, 0L, kind, ts, ts,
            ),
        )
        return id
    }

    /** Create a group/trip. Adds [userId] as owner; other members added directly. */
    suspend fun createGroup(
        userId: String,
        name: String,
        kind: String,
        currency: String,
        startDate: String? = null,
        endDate: String? = null,
        autoSplit: Boolean = false,
        isDirect: Boolean = false,
        memberUserIds: List<String> = emptyList(),
    ): String {
        val groupId = newId()
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO split_groups (id,created_by,name,kind,is_direct,start_date,end_date,auto_split,default_mode,currency,archived,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(groupId, userId, name.trim(), kind, if (isDirect) 1L else 0L, startDate, endDate, if (autoSplit) 1L else 0L, "equal", currency, 0L, ts, ts),
        )
        db.execute(
            sql = "INSERT INTO split_group_members (id,group_id,user_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?)",
            parameters = listOf(newId(), groupId, userId, "owner", ts, ts),
        )
        for (uid in memberUserIds) {
            if (uid != userId) {
                db.execute(
                    sql = "INSERT INTO split_group_members (id,group_id,user_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                    parameters = listOf(newId(), groupId, uid, "member", ts, ts),
                )
            }
        }
        return groupId
    }

    /** Find (or create) the hidden 2-person group for a 1:1 split. */
    suspend fun getOrCreateDirectGroup(userId: String, otherUserId: String, otherName: String, currency: String): String {
        val existing = db.getOptional(
            sql = """SELECT g.id AS id FROM split_groups g
                WHERE g.is_direct = 1 AND g.deleted_at IS NULL
                  AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL) = 2
                  AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL AND m.user_id IN (?, ?)) = 2
                LIMIT 1""",
            parameters = listOf(userId, otherUserId),
            mapper = { cursor -> cursor.getString("id") },
        )
        if (existing != null) return existing
        return createGroup(
            userId = userId,
            name = otherName.ifEmpty { "Direct" },
            kind = "group",
            currency = currency,
            isDirect = true,
            memberUserIds = listOf(otherUserId),
        )
    }

    /** Your private ledger projection of your share of a shared expense:
     * expense on your account for the part you covered for yourself, a
     * hidden Payable expense for any underpayment, or an expense on your
     * account for any overpayment you covered for others (net worth is
     * unchanged either way; who-owes-whom lives in expense_participants,
     * not here). Matches projectPersonal() exactly. */
    private suspend fun projectPersonal(
        userId: String,
        currency: String,
        myShare: Long,
        myPaid: Long,
        myAccountId: String?,
        expenseId: String,
        categoryId: String?,
        description: String?,
        note: String?,
        occurredAt: String,
    ) {
        val paidToOwn = minOf(myPaid, myShare)
        val underpay = maxOf(0L, myShare - myPaid)
        val overpay = maxOf(0L, myPaid - myShare)

        suspend fun post(txId: String, role: String) {
            db.execute(
                sql = "INSERT INTO expense_postings (id,user_id,expense_id,transaction_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                parameters = listOf(newId(), userId, expenseId, txId, role, nowIso(), nowIso()),
            )
        }

        if (paidToOwn > 0 && myAccountId != null) {
            val tx = ledger.createTransaction(userId = userId, accountId = myAccountId, type = "expense", amount = money(paidToOwn, currency), occurredAt = occurredAt, categoryId = categoryId, note = note, description = description)
            post(tx.id, "own_share")
        }
        if (underpay > 0) {
            val payable = ensureVirtualAccount(userId, "payable", currency)
            val tx = ledger.createTransaction(userId = userId, accountId = payable, type = "expense", amount = money(underpay, currency), occurredAt = occurredAt, categoryId = categoryId, note = note, description = description)
            post(tx.id, "borrow")
        }
        if (overpay > 0 && myAccountId != null) {
            val tx = ledger.createTransaction(userId = userId, accountId = myAccountId, type = "expense", amount = money(overpay, currency), occurredAt = occurredAt, categoryId = categoryId, note = note, description = description)
            post(tx.id, "lend")
        }
    }

    /** Create a shared expense in a group, then project [userId]'s own share
     * into their private ledger. Matches createSplitExpense() exactly. */
    suspend fun createSplitExpense(userId: String, input: SplitExpenseInput): String {
        val currency = input.total.currency
        val shares = computeShares(input.mode, input.total, input.participants)
        val shareByUser = LinkedHashMap<String, Long>()
        input.participants.forEachIndexed { i, p -> shareByUser[p.userId] = (shareByUser[p.userId] ?: 0L) + (shares.getOrElse(i) { 0L }) }
        val paidByUser = LinkedHashMap<String, Long>()
        for (p in input.payers) paidByUser[p.userId] = (paidByUser[p.userId] ?: 0L) + p.paid

        val expenseId = newId()
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO expenses (id,group_id,created_by,description,amount,currency,occurred_at,split_mode,version,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(expenseId, input.groupId, userId, input.description, input.total.amount, currency, input.occurredAt, input.mode, 1L, ts, ts),
        )
        val users = LinkedHashSet<String>().apply {
            addAll(shareByUser.keys)
            addAll(paidByUser.keys)
        }
        for (uid in users) {
            db.execute(
                sql = """INSERT INTO expense_participants (id,expense_id,group_id,user_id,paid_amount,share_amount,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?)""",
                parameters = listOf(newId(), expenseId, input.groupId, uid, paidByUser[uid] ?: 0L, shareByUser[uid] ?: 0L, ts, ts),
            )
        }

        val myShare = shareByUser[userId] ?: 0L
        val myPaid = paidByUser[userId] ?: 0L
        val myAccountId = input.payers.find { it.userId == userId }?.accountId
        projectPersonal(userId, currency, myShare, myPaid, myAccountId, expenseId, input.categoryId, input.description, input.note, input.occurredAt)

        return expenseId
    }

    // ---- itemized splits ----

    /**
     * Create a shared, itemized expense and project [userId]'s own share into
     * their private ledger.
     *
     * **The critical design point, carried over from web verbatim: this does
     * NOT introduce a second balance model.** Per-item shares are allocated,
     * rolled up per person, and written into `expense_participants` — the same
     * table [createSplitExpense] writes and the same table every balance,
     * settle-up and friend-graph query already reads. `expense_items` /
     * `expense_item_shares` are the BREAKDOWN, kept so the split can be
     * explained and re-opened later. Nothing in the balance math needs to know
     * itemized splits exist.
     *
     * Mirrors [createSplitExpense]'s contract exactly, so callers see no
     * difference beyond `expenses.has_items = 1`.
     */
    suspend fun createSplitExpenseItemized(userId: String, input: ItemizedSplitInput): String {
        val draft = input.draft
        val currency = draft.currency

        // Refuse to write a bill that doesn't add up. The UI blocks this too,
        // but a corrupted expense is unrecoverable from, so it is worth
        // checking twice.
        val rec = reconcile(draft)
        if (!rec.ok) {
            throw ItemizedSplitException(
                "Receipt doesn't reconcile: lines total ${rec.computed}, receipt says ${rec.stated ?: "nothing"}",
            )
        }

        // Allocation throws if any line is unassigned or an exact split is off,
        // so a partial write can never begin.
        val allocation = allocateReceipt(draft.lines, input.assignments)

        val paidByUser = LinkedHashMap<String, Long>()
        for (p in input.payers) paidByUser[p.userId] = (paidByUser[p.userId] ?: 0L) + p.paid
        val totalPaid = paidByUser.values.sum()
        if (totalPaid != allocation.total) {
            throw ItemizedSplitException("Payments total $totalPaid but the bill is ${allocation.total}")
        }

        val expenseId = newId()
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO expenses (id,group_id,created_by,description,amount,currency,occurred_at,split_mode,has_items,version,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(
                expenseId, input.groupId, userId, draft.merchant, allocation.total, currency,
                input.occurredAt, "itemized", 1L, 1L, ts, ts,
            ),
        )

        val byLineId = input.assignments.associateBy { it.lineId }

        // Write ALL items first, then all shares -- never interleaved.
        //
        // The sync connector coalesces only *consecutive* same-table ops into
        // one request. Interleaving item/share inserts defeats that entirely and
        // turns a 40-row bill into ~40 round-trips. Grouping them keeps it to
        // two. Web's comment says the same; it is not a style preference.
        val itemIdByLine = LinkedHashMap<String, String>()
        draft.lines.forEachIndexed { sort, line ->
            val mode = byLineId[line.id]?.mode ?: "equal"
            // Only charges may be proportional (DB check constraint).
            val splitMode = if (mode == "proportional" && !isCharge(line.kind)) "equal" else mode
            val itemId = newId()
            db.execute(
                sql = """INSERT INTO expense_items (id,expense_id,group_id,kind,description,quantity,unit,unit_price,amount,split_mode,sort,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)""",
                parameters = listOf(
                    itemId, expenseId, input.groupId, line.kind, line.description, line.quantity,
                    line.unit, line.unitPrice, line.amount, splitMode, sort.toLong(), ts, ts,
                ),
            )
            itemIdByLine[line.id] = itemId
        }

        for (line in draft.lines) {
            val itemId = itemIdByLine[line.id] ?: continue
            val weightByUser = (byLineId[line.id]?.shares ?: emptyList())
                .associate { it.userId to Math.round(it.weight ?: 0.0) }
            for (share in allocation.perLine[line.id] ?: emptyList()) {
                db.execute(
                    sql = """INSERT INTO expense_item_shares (id,item_id,expense_id,group_id,user_id,weight,share_amount,created_at,updated_at)
                        VALUES (?,?,?,?,?,?,?,?,?)""",
                    parameters = listOf(
                        newId(), itemId, expenseId, input.groupId, share.userId,
                        weightByUser[share.userId] ?: 0L, share.amount, ts, ts,
                    ),
                )
            }
        }

        // ---- the roll-up that keeps every existing balance query working ----
        // Allocation order first, then payers, so the participant rows land in a
        // stable order rather than a hash map's.
        val users = LinkedHashSet<String>()
        for (line in draft.lines) {
            allocation.perLine[line.id]?.forEach { users.add(it.userId) }
        }
        users.addAll(paidByUser.keys)
        for (uid in users) {
            db.execute(
                sql = """INSERT INTO expense_participants (id,expense_id,group_id,user_id,paid_amount,share_amount,created_at,updated_at)
                    VALUES (?,?,?,?,?,?,?,?)""",
                parameters = listOf(
                    newId(), expenseId, input.groupId, uid,
                    paidByUser[uid] ?: 0L, allocation.byUser[uid] ?: 0L, ts, ts,
                ),
            )
        }

        // ---- your private projection ----
        // Your own-share transaction carries the lines YOU are on, so the
        // personal breakdown matches what you actually ate.
        val myLines = draft.lines.mapNotNull { line ->
            val amount = (allocation.perLine[line.id] ?: emptyList())
                .find { it.userId == userId }?.amount ?: 0L
            if (amount == 0L) {
                null
            } else {
                val label = line.description.ifEmpty { line.kind.replace("_", " ") }
                TransactionItemInput(label, money(amount, currency))
            }
        }

        projectPersonalItemized(
            userId = userId,
            currency = currency,
            myShare = allocation.byUser[userId] ?: 0L,
            myPaid = paidByUser[userId] ?: 0L,
            myAccountId = input.payers.find { it.userId == userId }?.accountId,
            expenseId = expenseId,
            categoryId = input.categoryId,
            description = draft.merchant,
            note = input.note,
            occurredAt = input.occurredAt,
            myLines = myLines,
        )

        return expenseId
    }

    /**
     * Private ledger projection. Deliberately identical in shape and roles
     * (`own_share` / `borrow` / `lend`) to [projectPersonal] — the only
     * difference is the item breakdown riding along with the own-share leg.
     */
    private suspend fun projectPersonalItemized(
        userId: String,
        currency: String,
        myShare: Long,
        myPaid: Long,
        myAccountId: String?,
        expenseId: String,
        categoryId: String?,
        description: String?,
        note: String?,
        occurredAt: String,
        myLines: List<TransactionItemInput>,
    ) {
        val paidToOwn = minOf(myPaid, myShare)
        val underpay = maxOf(0L, myShare - myPaid)
        val overpay = maxOf(0L, myPaid - myShare)

        suspend fun post(txId: String, role: String) {
            db.execute(
                sql = "INSERT INTO expense_postings (id,user_id,expense_id,transaction_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
                parameters = listOf(newId(), userId, expenseId, txId, role, nowIso(), nowIso()),
            )
        }

        if (paidToOwn > 0 && myAccountId != null) {
            // Breakdown items must sum EXACTLY to the transaction amount, so
            // they can only ride along when this leg is your whole share.
            val itemsMatch = myLines.sumOf { it.amount.amount } == paidToOwn
            val tx = ledger.createTransaction(
                userId = userId, accountId = myAccountId, type = "expense", amount = money(paidToOwn, currency),
                occurredAt = occurredAt, categoryId = categoryId, note = note, description = description,
                items = if (itemsMatch) myLines else null,
            )
            post(tx.id, "own_share")
        }
        if (underpay > 0) {
            val payable = ensureVirtualAccount(userId, "payable", currency)
            val tx = ledger.createTransaction(
                userId = userId, accountId = payable, type = "expense", amount = money(underpay, currency),
                occurredAt = occurredAt, categoryId = categoryId, note = note, description = description,
            )
            post(tx.id, "borrow")
        }
        if (overpay > 0 && myAccountId != null) {
            val tx = ledger.createTransaction(
                userId = userId, accountId = myAccountId, type = "expense", amount = money(overpay, currency),
                occurredAt = occurredAt, categoryId = categoryId, note = note, description = description,
            )
            post(tx.id, "lend")
        }
    }

    /** The ledger transfer for whichever side is acting. Shared by settleUp
     * and confirmSettlement. Matches postSettlementLeg() exactly. */
    private suspend fun postSettlementLeg(userId: String, settlementId: String, amount: Long, direction: String, accountId: String?, currency: String) {
        if (accountId == null || amount <= 0) return
        val txId: String
        if (direction == "received") {
            val recv = ensureVirtualAccount(userId, "receivable", currency)
            val tx = ledger.createTransaction(userId = userId, accountId = recv, type = "transfer", amount = money(amount, currency), occurredAt = nowIso(), note = "Settlement received", toAccountId = accountId)
            txId = tx.id
        } else {
            val pay = ensureVirtualAccount(userId, "payable", currency)
            val tx = ledger.createTransaction(userId = userId, accountId = accountId, type = "transfer", amount = money(amount, currency), occurredAt = nowIso(), note = "Settlement paid", toAccountId = pay)
            txId = tx.id
        }
        db.execute(
            sql = "INSERT INTO expense_postings (id,user_id,settlement_id,transaction_id,role,created_at,updated_at) VALUES (?,?,?,?,?,?,?)",
            parameters = listOf(newId(), userId, settlementId, txId, "settlement", nowIso(), nowIso()),
        )
    }

    /** Record a settlement. [status] defaults to "confirmed" (manual mark-
     * settled: two people agreeing in person, nothing to confirm); pass
     * "pending" for a UPI-handoff flow with no delivery callback. Either
     * way, the ACTING party's ledger leg posts immediately. Matches
     * settleUp() exactly. [direction] is "received" | "paid". */
    suspend fun settleUp(
        userId: String,
        otherUserId: String,
        groupId: String,
        amount: Long,
        direction: String,
        accountId: String?,
        currency: String,
        note: String? = null,
        status: String = "confirmed",
        method: String? = null,
        upiRef: String? = null,
    ): String {
        val fromUser = if (direction == "received") otherUserId else userId
        val toUser = if (direction == "received") userId else otherUserId
        val settlementId = newId()
        val ts = nowIso()
        db.execute(
            sql = """INSERT INTO settlements (id,group_id,from_user,to_user,amount,currency,method,note,settled_at,created_by,status,confirmed_at,confirmed_by,upi_ref,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            parameters = listOf(
                settlementId, groupId, fromUser, toUser, amount, currency,
                method ?: (if (accountId != null) "account" else "none"),
                note, ts, userId, status,
                if (status == "confirmed") ts else null,
                if (status == "confirmed") userId else null,
                upiRef, ts, ts,
            ),
        )
        postSettlementLeg(userId, settlementId, amount, direction, accountId, currency)
        return settlementId
    }

    /** The payee confirms the money arrived: flip to "confirmed" and post
     * THEIR leg (the payer's already posted when they paid). Matches
     * confirmSettlement() exactly. */
    suspend fun confirmSettlement(userId: String, settlement: PendingSettlement, accountId: String?) {
        val ts = nowIso()
        db.execute(
            sql = "UPDATE settlements SET status = ?, confirmed_at = ?, confirmed_by = ?, updated_at = ? WHERE id = ?",
            parameters = listOf("confirmed", ts, userId, ts, settlement.id),
        )
        postSettlementLeg(userId, settlement.id, settlement.amount, "received", accountId, settlement.currency)
    }

    /** The payee says it never arrived. The ledger is append-only, so this
     * does NOT unwind the payer's original transfer -- it marks the
     * settlement "disputed" (removed from balance netting) and leaves the
     * posted cash movement standing. Matches disputeSettlement() exactly. */
    suspend fun disputeSettlement(userId: String, settlementId: String, note: String? = null) {
        val ts = nowIso()
        db.execute(
            sql = "UPDATE settlements SET status = ?, confirmed_at = ?, confirmed_by = ?, note = ?, updated_at = ? WHERE id = ?",
            parameters = listOf("disputed", ts, userId, note ?: "Recipient reported it didn't arrive", ts, settlementId),
        )
    }
}
