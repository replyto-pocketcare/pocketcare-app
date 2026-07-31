package care.pocket.data.repository

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
import care.pocket.domain.budget.periodBounds
import care.pocket.domain.money.Money
import care.pocket.domain.money.money
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
)

/** ISO instant string at UTC midnight of [date] -- matches JS's
 * `new Date(...).toISOString()` format (always millisecond-precision),
 * which is what the real spec compares occurred_at against. */
private fun isoMidnight(date: LocalDate): String =
    "${date}T00:00:00.000Z"

class BudgetRepository(private val db: PowerSyncDatabase) {

    suspend fun list(): List<BudgetLike> = db.getAll(
        sql = "SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL",
        mapper = { cursor ->
            BudgetLike(
                id = cursor.getString("id"),
                name = cursor.getStringOptional("name"),
                period = cursor.getString("period"),
                startDate = cursor.getStringOptional("start_date"),
                endDate = cursor.getStringOptional("end_date"),
                limitAmount = cursor.getLong("limit_amount"),
                currency = cursor.getString("currency"),
                thresholdPct = cursor.getLong("threshold_pct").toInt(),
            )
        },
    )

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
