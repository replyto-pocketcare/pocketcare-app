package com.sanvya.app.data.repository

/**
 * Read facade over budgets (P2.5). Mirrors
 * packages/data/src/powersync-repositories.ts's PowerSyncBudgetRepository
 * exactly: list() projects a fixed column subset; spentThisPeriod() sums
 * expenses in the budget's window (a custom start/end range if set, else the
 * recurring period via the already-ported periodBounds domain function --
 * P1.3), scoped by whichever of the budget's category/label junctions are
 * populated (OR'd together; no categories/labels selected means "all
 * expenses" in that window/currency).
 *
 * Table columns confirmed against PocketCareSchema.kt (budgets,
 * budget_categories, budget_labels) and supabase/migrations/0001_init.sql.
 */

import com.powersync.PowerSyncDatabase
import com.powersync.db.getLong
import com.powersync.db.getString
import com.powersync.db.getStringOptional
import com.sanvya.app.domain.budget.periodBounds
import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.money
import kotlinx.coroutines.flow.Flow
import java.time.LocalDate
import java.time.ZoneOffset

data class BudgetLike(
    val id: String,
    val name: String?,
    val period: String,
    val startDate: String?,
    val endDate: String?,
    val limitAmount: Long,
    val currency: String,
    val thresholdPct: Int,
    val alertTimeUtc: String? = null,
)

/** ISO instant string at UTC midnight of [date] -- matches JS's
 * `new Date(...).toISOString()` format (always millisecond-precision),
 * which is what the real spec compares occurred_at against. */
private fun isoMidnight(date: LocalDate): String =
    "${date}T00:00:00.000Z"

class BudgetRepository(private val db: PowerSyncDatabase) {

    private val budgetMapper: (com.powersync.db.SqlCursor) -> BudgetLike = { cursor ->
        BudgetLike(
            id = cursor.getString("id"),
            name = cursor.getStringOptional("name"),
            period = cursor.getString("period"),
            startDate = cursor.getStringOptional("start_date"),
            endDate = cursor.getStringOptional("end_date"),
            limitAmount = cursor.getLong("limit_amount"),
            currency = cursor.getString("currency"),
            thresholdPct = cursor.getLong("threshold_pct").toInt(),
            alertTimeUtc = cursor.getStringOptional("alert_time_utc"),
        )
    }

    suspend fun list(): List<BudgetLike> = db.getAll(
        sql = """
            SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct, alert_time_utc
            FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC
            """.trimIndent(),
        mapper = budgetMapper,
    )

    /** Live version of [list] -- re-emits on any local write to `budgets`,
     * regardless of which ViewModel/repository instance performed it.
     * Added 2026-08-06 to fix a list-staleness bug: the list screen used to
     * only refresh via an explicit `reload()` call, which the separate Add/
     * Edit Budget screen's own BudgetsViewModel instance never triggered on
     * this one -- see AUDIT_HISTORY.md's 2026-08-06 entry. */
    fun watchBudgets(): Flow<List<BudgetLike>> = db.watch(
        sql = """
            SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct, alert_time_utc
            FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC
            """.trimIndent(),
        mapper = budgetMapper,
    )

    // ---- writes ----
    // Matches apps/web/app/budgets/page.tsx's addBudget()/saveEdit()/
    // writeBudgetScope()/resolveLabelIds() exactly -- same shape as iOS's
    // BudgetRepository.swift, mirrored field-for-field. Category/label scope
    // is delete-then-reinsert of both junction tables per write (PowerSync's
    // incremental per-row upload queue means this can't be a single
    // cross-table constraint -- CLAUDE.md golden rule: "never write a
    // cross-row constraint on a synced table").

    /** Creates a budget row. [startDate]/[endDate] are both non-null for a
     * custom-dated budget, both null for a recurring one -- matches web's
     * `timeMode === "custom" ? start || null : null` exactly (never a mix). */
    suspend fun create(
        userId: String,
        name: String?,
        period: String,
        startDate: String?,
        endDate: String?,
        limitAmount: Long,
        currency: String,
        thresholdPct: Int,
        alertTimeUtc: String,
    ): String {
        val id = newId()
        val ts = nowIso()
        db.execute(
            sql = """
                INSERT INTO budgets
                (id,user_id,name,period,start_date,end_date,limit_amount,currency,threshold_pct,alert_time_utc,rollover,created_at,updated_at)
                VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)
                """.trimIndent(),
            parameters = listOf(id, userId, name, period, startDate, endDate, limitAmount, currency, thresholdPct, alertTimeUtc, 0L, ts, ts),
        )
        return id
    }

    /** Updates a budget's editable fields. Matches web's saveEdit(): name,
     * limit_amount, period, threshold_pct, alert_time_utc only -- currency,
     * start_date/end_date are NOT editable after creation (period must not
     * be changed by callers for a custom-dated budget, matching web's
     * hidden-period-chips-in-edit-mode guard). */
    suspend fun update(
        id: String,
        name: String?,
        limitAmount: Long,
        period: String,
        thresholdPct: Int,
        alertTimeUtc: String,
    ) {
        val ts = nowIso()
        db.execute(
            sql = """
                UPDATE budgets SET name = ?, limit_amount = ?, period = ?, threshold_pct = ?, alert_time_utc = ?, updated_at = ?
                WHERE id = ?
                """.trimIndent(),
            parameters = listOf(name, limitAmount, period, thresholdPct, alertTimeUtc, ts, id),
        )
    }

    suspend fun delete(id: String) = softDelete(db, "budgets", id)

    suspend fun categoryIds(budgetId: String): List<String> = db.getAll(
        sql = "SELECT category_id FROM budget_categories WHERE budget_id = ?",
        parameters = listOf(budgetId),
        mapper = { cursor -> cursor.getString("category_id") },
    )

    suspend fun labelNames(budgetId: String): List<String> = db.getAll(
        sql = "SELECT l.name AS name FROM budget_labels bl JOIN labels l ON l.id = bl.label_id WHERE bl.budget_id = ?",
        parameters = listOf(budgetId),
        mapper = { cursor -> cursor.getString("name") },
    )

    /** Rewrites a budget's category/label scope via the junction tables --
     * delete-then-reinsert, matching web's writeBudgetScope() exactly.
     * [labelNames] are find-or-created by name (case-insensitive dedupe),
     * matching web's resolveLabelIds(). */
    suspend fun writeScope(userId: String, budgetId: String, categoryIds: List<String>, labelNames: List<String>) {
        db.execute("DELETE FROM budget_categories WHERE budget_id = ?", listOf(budgetId))
        db.execute("DELETE FROM budget_labels WHERE budget_id = ?", listOf(budgetId))
        for (cid in categoryIds.toSet()) {
            db.execute(
                "INSERT INTO budget_categories (id,user_id,budget_id,category_id) VALUES (?,?,?,?)",
                listOf(newId(), userId, budgetId, cid),
            )
        }
        val labelIds = resolveLabelIds(userId, labelNames)
        for (lid in labelIds) {
            db.execute(
                "INSERT INTO budget_labels (id,user_id,budget_id,label_id) VALUES (?,?,?,?)",
                listOf(newId(), userId, budgetId, lid),
            )
        }
    }

    /** Find-or-create label rows by name, returning their ids -- matches
     * web's resolveLabelIds() exactly (case-insensitive dedupe within the
     * call, trims whitespace, skips blanks). */
    private suspend fun resolveLabelIds(userId: String, names: List<String>): List<String> {
        val ids = mutableListOf<String>()
        val seen = mutableSetOf<String>()
        for (raw in names) {
            val name = raw.trim()
            if (name.isEmpty() || seen.contains(name.lowercase())) continue
            seen.add(name.lowercase())
            val found = db.getOptional(
                sql = "SELECT id FROM labels WHERE user_id = ? AND name = ? AND deleted_at IS NULL",
                parameters = listOf(userId, name),
                mapper = { cursor -> cursor.getString("id") },
            )
            if (found != null) {
                ids.add(found)
            } else {
                val id = newId()
                val ts = nowIso()
                db.execute(
                    "INSERT INTO labels (id,user_id,name,color,created_at,updated_at) VALUES (?,?,?,?,?,?)",
                    listOf(id, userId, name, null, ts, ts),
                )
                ids.add(id)
            }
        }
        return ids
    }

    /** Sum of expenses in the budget's window, honoring its category/label
     * scope. [asOf] is a calendar day (already UTC-truncated by the caller,
     * matching this port's established periodBounds() convention -- see
     * Budget.kt's own header comment). */
    suspend fun spentThisPeriod(budget: BudgetLike, asOf: LocalDate = LocalDate.now(ZoneOffset.UTC)): Money {
        val start: LocalDate
        val endExclusive: LocalDate
        if (budget.startDate != null && budget.endDate != null) {
            start = LocalDate.parse(budget.startDate)
            // Make end inclusive of the whole end day.
            endExclusive = LocalDate.parse(budget.endDate).plusDays(1)
        } else {
            val window = periodBounds(budget.period, asOf)
            start = window.start
            endExclusive = window.endExclusive
        }

        val where = mutableListOf("t.type = 'expense'", "t.deleted_at IS NULL", "t.occurred_at >= ?", "t.occurred_at < ?", "t.currency = ?")
        val params = mutableListOf<Any?>(isoMidnight(start), isoMidnight(endExclusive), budget.currency)

        val catIds = db.getAll(
            sql = "SELECT category_id FROM budget_categories WHERE budget_id = ?",
            parameters = listOf(budget.id),
            mapper = { cursor -> cursor.getString("category_id") },
        )
        val labelIds = db.getAll(
            sql = "SELECT label_id FROM budget_labels WHERE budget_id = ?",
            parameters = listOf(budget.id),
            mapper = { cursor -> cursor.getString("label_id") },
        )

        val ors = mutableListOf<String>()
        if (catIds.isNotEmpty()) {
            ors += "t.category_id IN (${catIds.joinToString(",") { "?" }})"
            // .addAll(), not += : `params += catIds` is ambiguous between
            // MutableCollection's plusAssign(element) (treating the whole
            // List<String> as ONE Any? element, since List<out E> is
            // covariant so List<String> conforms to Any?) and
            // plusAssign(elements: Iterable<T>) (spreading it) -- real
            // ./gradlew compile error confirmed the compiler resolves this
            // ambiguity by falling back to the non-mutating `plus` operator
            // and trying to reassign the `val`, which fails outright
            // ("'val' cannot be reassigned"). addAll() has no such
            // ambiguity: it's a single, unambiguous member function.
            params.addAll(catIds)
        }
        if (labelIds.isNotEmpty()) {
            ors += "EXISTS (SELECT 1 FROM transaction_labels tl WHERE tl.transaction_id = t.id AND tl.label_id IN (${labelIds.joinToString(",") { "?" }}))"
            params.addAll(labelIds)
        }
        if (ors.isNotEmpty()) where += "(${ors.joinToString(" OR ")})"

        val total = db.get(
            sql = "SELECT COALESCE(SUM(t.amount), 0) AS total FROM transactions t WHERE ${where.joinToString(" AND ")}",
            parameters = params,
            mapper = { cursor -> cursor.getLong("total") },
        )
        return money(total, budget.currency)
    }
}
