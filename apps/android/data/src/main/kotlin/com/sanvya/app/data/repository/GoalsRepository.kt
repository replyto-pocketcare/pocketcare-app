package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

/**
 * Read/write facade over goals + goal_allocations, matching
 * apps/web/app/goals/page.tsx per docs/mobile/screen-specs/goals.md.
 * Was list()-free (only per-goal `watchGoalAllocations`, called in an N+1
 * loop by the old placeholder GoalsViewModel using `.firstOrNull()` --
 * meaning it never actually re-observed allocation changes) before this
 * pass (2026-08-06, task #25), then briefly used one-shot suspend reads +
 * explicit ViewModel-driven reload() (matching BudgetRepository's own
 * convention). That reload()-only approach turned out to be the root
 * cause of a real bug found 2026-08-06: since Add/Edit Goal are separate
 * nav routes with their own GoalsViewModel instance, a save there never
 * called reload() on the LIST screen's own (different) instance, so new/
 * edited goals didn't appear until the whole "goals" route was torn down
 * and recreated (e.g. by navigating elsewhere and back). Fixed by adding
 * real `watchGoals`/`watchAllocations` (db.watch, same pattern as
 * InvestmentsRepository/LoansRepository) so the list is driven by a live
 * query against the actual table instead of a manually-triggered snapshot
 * -- see AUDIT_HISTORY.md's 2026-08-06 "list staleness" entry.
 */
data class Goal(
    val id: String,
    val userId: String,
    val name: String,
    val targetAmount: Long,
    val currency: String,
    val priority: Long,
    val isEmergencyFund: Boolean,
    val alertTimeUtc: String?,
)

data class GoalAllocation(
    val id: String,
    val userId: String,
    val goalId: String,
    val sourceAccountId: String,
    val amountBlocked: Long,
)

private fun goalMapper(cursor: SqlCursor): Goal = Goal(
    id = cursor.getString("id"),
    userId = cursor.getString("user_id"),
    name = cursor.getString("name"),
    targetAmount = cursor.getLong("target_amount"),
    currency = cursor.getString("currency"),
    priority = cursor.getLong("priority"),
    isEmergencyFund = cursor.getBooleanOptional("is_emergency_fund") ?: false,
    alertTimeUtc = cursor.getStringOptional("alert_time_utc"),
)

private fun allocationMapper(cursor: SqlCursor): GoalAllocation = GoalAllocation(
    id = cursor.getString("id"),
    userId = cursor.getString("user_id"),
    goalId = cursor.getString("goal_id"),
    sourceAccountId = cursor.getString("source_account_id"),
    amountBlocked = cursor.getLong("amount_blocked"),
)

class GoalsRepository(private val db: PowerSyncDatabase) {

    /** Matches web's `ORDER BY is_emergency_fund DESC, priority` (EF goal
     * always first). */
    suspend fun list(userId: String): List<Goal> = db.getAll(
        sql = "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY is_emergency_fund DESC, priority",
        parameters = listOf(userId),
        mapper = ::goalMapper,
    )

    /** All of the user's allocations in one query -- web does the same
     * (a single `goal_allocations` query, `saved(goalId)` filters+reduces
     * client-side), avoiding the old N+1-per-goal pattern. */
    suspend fun listAllocations(userId: String): List<GoalAllocation> = db.getAll(
        sql = "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND user_id = ?",
        parameters = listOf(userId),
        mapper = ::allocationMapper,
    )

    /** Live version of [list] -- re-emits on any local write to `goals`,
     * regardless of which ViewModel/repository instance performed it
     * (single db.watch() subscription against the real table, not a
     * cached snapshot). Added 2026-08-06 to fix list staleness. */
    fun watchGoals(userId: String): Flow<List<Goal>> = db.watch(
        sql = "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY is_emergency_fund DESC, priority",
        parameters = listOf(userId),
        mapper = ::goalMapper,
    )

    /** Live version of [listAllocations]. Added 2026-08-06 to fix list
     * staleness (see [watchGoals]). */
    fun watchAllocations(userId: String): Flow<List<GoalAllocation>> = db.watch(
        sql = "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND user_id = ?",
        parameters = listOf(userId),
        mapper = ::allocationMapper,
    )

    /** Matches web's addGoal(): priority = caller-supplied (current goal
     * count, append-to-end). */
    suspend fun create(
        userId: String,
        name: String,
        targetAmount: Long,
        currency: String,
        isEmergencyFund: Boolean,
        priority: Long,
        alertTimeUtc: String,
    ): String {
        val id = newId()
        val ts = nowIso()
        db.execute(
            sql = """
                INSERT INTO goals
                (id,user_id,name,target_amount,currency,is_emergency_fund,priority,alert_time_utc,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
            parameters = listOf(id, userId, name, targetAmount, currency, if (isEmergencyFund) 1L else 0L, priority, alertTimeUtc, ts, ts),
        )
        return id
    }

    /** Matches web's saveEdit(): name, target_amount, alert_time_utc only
     * -- currency, is_emergency_fund, and priority are not editable after
     * creation. */
    suspend fun update(id: String, name: String, targetAmount: Long, alertTimeUtc: String) {
        val ts = nowIso()
        db.execute(
            sql = "UPDATE goals SET name = ?, target_amount = ?, alert_time_utc = ?, updated_at = ? WHERE id = ?",
            parameters = listOf(name, targetAmount, alertTimeUtc, ts, id),
        )
    }

    /** Soft-deletes the goal row only -- matches web's `softDelete("goals",
     * goal.id)` exactly, no cascade to its allocations (see screen spec's
     * "Deferred"/data section for why that's an accepted, pre-existing
     * asymmetry, not something to fix here). */
    suspend fun delete(id: String) = softDelete(db, "goals", id)

    /** Matches web's allocate(): caller is responsible for capping
     * [amountBlocked] at the goal's remaining amount before calling this
     * (mirrors web's own client-side `Math.min(..., remaining)` cap). */
    suspend fun createAllocation(userId: String, goalId: String, sourceAccountId: String, amountBlocked: Long) {
        val ts = nowIso()
        db.execute(
            sql = """
                INSERT INTO goal_allocations
                (id,user_id,goal_id,source_account_id,amount_blocked,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?)
                """.trimIndent(),
            parameters = listOf(newId(), userId, goalId, sourceAccountId, amountBlocked, ts, ts),
        )
    }
}
