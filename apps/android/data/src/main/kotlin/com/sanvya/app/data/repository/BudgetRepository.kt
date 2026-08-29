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

/**
 * One expense counted against a budget, joined for display -- web's `BudgetTxn`
 * (packages/data/src/index.ts).
 */
data class BudgetTxn(
    val id: String,
    val occurredAt: String,
    val amount: Long,
    val currency: String,
    val description: String?,
    val note: String?,
    val categoryName: String?,
    val accountName: String?,
)

/** Per-day expense totals for a budget's window, plus the window itself. */
data class DailySpend(
    /** `YYYY-MM-DD` to minor units. Days with no spend are absent. */
    val totals: Map<String, Long>,
    val startIso: String,
    /** INCLUSIVE last day of the window. */
    val endIso: String,
)

/** The shared WHERE clause plus its bound parameters and the window it covers. */
private data class ScopedQuery(
    val where: String,
    val params: List<Any?>,
    val startIso: String,
    val endIso: String,
)

/**
 * SQL predicate excluding money you FRONTED for other people from your own
 * spending -- web's `notFrontedForOthers("t")`, verbatim.
 *
 * A top-level constant rather than three copies inline: the whole point of
 * web's version is that the same string backs every aggregate, so they cannot
 * drift apart -- which is precisely how a budget total and its drill-down would
 * come to disagree.
 */
private const val NOT_FRONTED_FOR_OTHERS =
    "t.id NOT IN (SELECT transaction_id FROM expense_postings " +
        "WHERE role = 'lend' AND transaction_id IS NOT NULL AND deleted_at IS NULL)"

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

    /** All (budget_id, category_id) pairs across every budget, reactive --
     * added 2026-08-06 for Insights' genBudgetWarnings/its own budgets
     * aggregation (task #28), which needs every budget's scoped categories
     * up front rather than one categoryIds(id) call per budget. */
    fun watchBudgetCategories(): Flow<List<Pair<String, String>>> = db.watch(
        sql = "SELECT budget_id, category_id FROM budget_categories",
        mapper = { cursor -> cursor.getString("budget_id") to cursor.getString("category_id") },
    )

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

    /**
     * The WHERE clause every "what counts against this budget" read shares.
     *
     * Mirrors packages/data/src/powersync-repositories.ts's private
     * `scopeClause` exactly, and exists for the reason its own comment gives:
     * a second hand-written query for the drill-down list or the chart would
     * be a standing invitation for the two to disagree, and a list that does
     * not add up to the figure above it is worse than no list at all -- it
     * makes the user doubt the number rather than the screen.
     *
     * [asOf] is a calendar day (already UTC-truncated by the caller, matching
     * this port's established periodBounds() convention -- see Budget.kt's own
     * header comment).
     */
    private suspend fun scopeClause(budget: BudgetLike, asOf: LocalDate): ScopedQuery {
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

        val where = mutableListOf(
            "t.type = 'expense'",
            "t.deleted_at IS NULL",
            // Money FRONTED for other people is not your spending. A split
            // books the part you covered for others as an ordinary expense on
            // your account, which is right for the ledger and wrong for every
            // "what did I spend" aggregate -- buying a friend a phone on your
            // card would blow the month's budget. Web excludes it here
            // (packages/data's `notFrontedForOthers`); this port did not, so
            // the same budget read differently in the browser and on the
            // phone. Same SQL LedgerRepository's own expense aggregates use.
            NOT_FRONTED_FOR_OTHERS,
            "t.occurred_at >= ?",
            "t.occurred_at < ?",
            "t.currency = ?",
        )
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
        // No categories/labels selected -> overall (all expenses in the window).
        if (ors.isNotEmpty()) where += "(${ors.joinToString(" OR ")})"

        return ScopedQuery(
            where = where.joinToString(" AND "),
            params = params,
            startIso = start.toString(),
            // INCLUSIVE, for the chart's axis: the query boundary is exclusive
            // because SQLite compares timestamps, but a chart draws days.
            endIso = endExclusive.minusDays(1).toString(),
        )
    }

    /** Sum of expenses in the budget's window, honoring its category/label
     * scope. */
    suspend fun spentThisPeriod(budget: BudgetLike, asOf: LocalDate = LocalDate.now(ZoneOffset.UTC)): Money {
        val scope = scopeClause(budget, asOf)
        val total = db.get(
            sql = "SELECT COALESCE(SUM(t.amount), 0) AS total FROM transactions t WHERE ${scope.where}",
            parameters = scope.params,
            mapper = { cursor -> cursor.getLong("total") },
        )
        return money(total, budget.currency)
    }

    /**
     * The individual expenses behind [spentThisPeriod], newest first -- same
     * scope, same window, so the rows always sum to the total.
     *
     * Mirrors web's `transactionsThisPeriod`, which backs apps/web/src/budgets/
     * SpentBreakdown.tsx. Added here 2026-08-29: tapping the "spent" figure
     * opened nothing on either native app.
     */
    suspend fun transactionsThisPeriod(
        budget: BudgetLike,
        asOf: LocalDate = LocalDate.now(ZoneOffset.UTC),
    ): List<BudgetTxn> {
        val scope = scopeClause(budget, asOf)
        return db.getAll(
            sql = """
                SELECT t.id AS id, t.occurred_at AS occurred_at, t.amount AS amount, t.currency AS currency,
                       t.description AS description, t.note AS note,
                       c.name AS category_name, a.name AS account_name
                  FROM transactions t
                  LEFT JOIN categories c ON c.id = t.category_id
                  LEFT JOIN accounts a ON a.id = t.account_id
                 WHERE ${scope.where}
                 ORDER BY t.occurred_at DESC, t.created_at DESC
                """.trimIndent(),
            parameters = scope.params,
            mapper = { cursor ->
                BudgetTxn(
                    id = cursor.getString("id"),
                    occurredAt = cursor.getString("occurred_at"),
                    amount = cursor.getLong("amount"),
                    currency = cursor.getString("currency"),
                    description = cursor.getStringOptional("description"),
                    note = cursor.getStringOptional("note"),
                    categoryName = cursor.getStringOptional("category_name"),
                    accountName = cursor.getStringOptional("account_name"),
                )
            },
        )
    }

    /**
     * Per-day totals for the budget's window, keyed `YYYY-MM-DD` -- the input
     * to domain's `cumulativeSpendSeries`, which draws the spend-vs-limit
     * curve.
     *
     * Deliberately the SAME scope clause as [spentThisPeriod], where web's own
     * chart runs a looser hand-written query of its own (no currency filter, no
     * fronted-for-others exclusion, scope re-implemented in JS over the rows).
     * Web's chart can therefore finish above the "spent" figure printed
     * directly beneath it. That is a defect, not a design, and reproducing it
     * would mean shipping a chart that visibly contradicts its own card.
     *
     * Also returns the window it used, so the caller never has to re-derive the
     * axis from a second copy of the period arithmetic.
     */
    suspend fun dailySpendThisPeriod(
        budget: BudgetLike,
        asOf: LocalDate = LocalDate.now(ZoneOffset.UTC),
    ): DailySpend {
        val scope = scopeClause(budget, asOf)
        val rows = db.getAll(
            sql = """
                SELECT date(t.occurred_at) AS d, COALESCE(SUM(t.amount), 0) AS total
                  FROM transactions t
                 WHERE ${scope.where}
                 GROUP BY date(t.occurred_at)
                """.trimIndent(),
            parameters = scope.params,
            mapper = { cursor -> cursor.getString("d") to cursor.getLong("total") },
        )
        return DailySpend(totals = rows.toMap(), startIso = scope.startIso, endIso = scope.endIso)
    }
}
