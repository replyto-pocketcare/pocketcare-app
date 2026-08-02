package com.sanvya.app.data.repository

import com.powersync.PowerSyncDatabase
import com.powersync.db.SqlCursor
import com.powersync.db.getBooleanOptional
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import kotlinx.coroutines.flow.Flow

data class Goal(
    val id: String,
    val userId: String,
    val name: String,
    val targetAmount: Long,
    val currency: String,
    val priority: Long,
    val isEmergencyFund: Boolean,
    val targetDate: String?
)

data class GoalAllocation(
    val id: String,
    val userId: String,
    val goalId: String,
    val sourceAccountId: String,
    val amountBlocked: Long
)

class GoalsRepository(private val db: PowerSyncDatabase) {

    private fun goalMapper(cursor: SqlCursor): Goal = Goal(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        name = cursor.getString("name"),
        targetAmount = cursor.getLong("target_amount"),
        currency = cursor.getString("currency"),
        priority = cursor.getLong("priority"),
        isEmergencyFund = cursor.getBooleanOptional("is_emergency_fund") ?: false,
        targetDate = cursor.getStringOptional("target_date")
    )

    private fun allocationMapper(cursor: SqlCursor): GoalAllocation = GoalAllocation(
        id = cursor.getString("id"),
        userId = cursor.getString("user_id"),
        goalId = cursor.getString("goal_id"),
        sourceAccountId = cursor.getString("source_account_id"),
        amountBlocked = cursor.getLong("amount_blocked")
    )

    fun watchGoals(userId: String): Flow<List<Goal>> = db.watch(
        sql = "SELECT * FROM goals WHERE deleted_at IS NULL AND user_id = ? ORDER BY priority ASC, created_at DESC",
        parameters = listOf(userId),
        mapper = ::goalMapper
    )

    fun watchGoalAllocations(goalId: String): Flow<List<GoalAllocation>> = db.watch(
        sql = "SELECT * FROM goal_allocations WHERE deleted_at IS NULL AND goal_id = ?",
        parameters = listOf(goalId),
        mapper = ::allocationMapper
    )
}
