package com.sanvya.app.domain.insights

import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.fromMajor
import com.sanvya.app.domain.money.toMajor
import java.time.DayOfWeek
import java.time.LocalDate
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.roundToLong

// Ported from apps/web/src/insights/{types,generators}.ts (86 + 422 lines)
// for the Insights feed (task #28). Pure -- no I/O, no Android/locale
// dependencies (currency formatting is injected via GenContext.fmt, matching
// this codebase's established "domain never formats currency, screens do"
// convention -- see Money.kt, which has no `format()` either). Every
// threshold/priority/cap below is load-bearing, copied from generators.ts,
// not invented.

// ---- shared visual/card contract (types.ts) ----

data class SeriesPoint(val label: String, val value: Double, val color: String? = null)

enum class InsightTheme { POSITIVE, WARNING, NEUTRAL, CELEBRATORY }

sealed class VisualSpec {
    data class Bars(val series: List<SeriesPoint>, val unit: String? = null, val horizontal: Boolean = false) : VisualSpec()
    data class Area(val series: List<SeriesPoint>) : VisualSpec()
    data class Donut(val series: List<SeriesPoint>, val centerLabel: String? = null, val centerSub: String? = null) : VisualSpec()
    data class Gauge(val value: Double, val max: Double, val warnAt: Double? = null, val dangerAt: Double? = null, val unit: String? = null, val centerLabel: String? = null) : VisualSpec()
    data class Progress(val value: Double, val target: Double? = null, val centerLabel: String? = null) : VisualSpec()
}

data class InsightMetric(val display: String, val raw: Double? = null, val deltaPct: Int? = null, val direction: String? = null)
data class InsightCta(val label: String, val target: String)

data class InsightCard(
    val id: String,
    val type: String,
    val theme: InsightTheme,
    val generatedAt: String,
    val periodStart: String,
    val periodEnd: String,
    val priority: Int,
    val headline: String,
    val subhead: String? = null,
    val bullets: List<String>,
    val metric: InsightMetric? = null,
    val visual: VisualSpec?,
    val cta: InsightCta? = null,
    val cadenceKey: String,
    val cadenceFrequency: String,
)

/** Fixed multi-series palette -- theme-invariant, matches web's literal hex
 * array (not a CSS var, so it doesn't flip with dark mode either). */
val INSIGHT_PALETTE = listOf("#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647")

// ---- aggregate inputs (generators.ts's GenContext) ----

data class DayAgg(val day: String, val income: Long, val expense: Long)
data class MonthAgg(val ym: String, val income: Long, val expense: Long)
data class CatAgg(val name: String, val expense: Long)
data class BudgetAgg(val name: String, val limit: Long, val spent: Long)
data class TopExpense(val label: String, val amount: Long)
data class SubAgg(val name: String, val monthly: Long)
data class GoalAgg(val name: String, val target: Long, val saved: Long, val emergency: Boolean)
data class TxnDayCount(val day: String, val count: Int)
data class PaceAgg(val thisSoFar: Double, val lastSameSoFar: Double, val lastFull: Double, val dayOfMonth: Int, val daysInMonth: Int, val cumulative: List<SeriesPoint>)
data class NoSpendAgg(val noSpendDays: Int, val daysElapsed: Int, val spendDays: Int)
data class AvgDailyAgg(val thisAvg: Double, val lastAvg: Double)
data class CatSpike(val name: String, val thisMonth: Double, val avgPrior: Double)
data class DividendAgg(val holdings: Int, val trailing12: Long, val upcoming12: Long, val total: Long, val buckets: List<SeriesPoint>)
data class ProjectionAgg(val holdings: Int, val currentValue: Double, val endValue: Double, val contributed: Double, val years: Int, val growthPct: Int, val series: List<SeriesPoint>)

data class GenContext(
    val currency: String,
    val now: LocalDate,
    val nowIso: String,
    /** Formats minor units in [currency] -- injected so this file stays
     * locale/Android-free; the ViewModel passes its own formatMoney(). */
    val fmt: (Long) -> String,
    val days: List<DayAgg>,
    val months: List<MonthAgg>,
    val cats: List<CatAgg>,
    val labels: List<CatAgg>,
    val budgets: List<BudgetAgg>,
    val streak: Int,
    val txnDays7: List<TxnDayCount>,
    val topExpenses: List<TopExpense>,
    val weekday: List<SeriesPoint>,
    val weekdayTop: String,
    val subs: List<SubAgg>,
    val subsTotal: Long,
    val goals: List<GoalAgg>,
    val pace: PaceAgg,
    val noSpend: NoSpendAgg,
    val avgDaily: AvgDailyAgg,
    val catSpike: CatSpike?,
    val dividends: DividendAgg? = null,
    val projection: ProjectionAgg? = null,
    val mindfulnessTxns: List<TransactionForInsight>? = null,
)

// ---- helpers ----

private fun fmtL(ctx: GenContext, minor: Double): String = ctx.fmt(minor.roundToLong())
// Minor -> major for chart values and metric.raw. Takes ctx because the
// divisor is not 100 everywhere: JPY has no minor units, KWD has three. The
// old signatures could not have been correct -- they had no currency to ask.
private fun major(ctx: GenContext, minor: Long): Double = toMajor(Money(minor, ctx.currency))
private fun majorD(ctx: GenContext, minor: Double): Double = major(ctx, minor.roundToLong())

/** The inverse, for the one place a major-unit average has to go back. */
private fun minorOf(ctx: GenContext, majorValue: Double): Long =
    fromMajor(majorValue, ctx.currency).amount
private fun pctOf(a: Double, b: Double): Int = if (b == 0.0) (if (a > 0) 100 else 0) else (((a - b) / abs(b)) * 100).roundToInt()
private val WD_LABELS = arrayOf("Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat") // Calendar.DAY_OF_WEEK order
private fun weekdayLabel(iso: String): String {
    val dow = LocalDate.parse(iso.take(10)).dayOfWeek // MONDAY=1..SUNDAY=7
    val sundayFirst = if (dow == DayOfWeek.SUNDAY) 0 else dow.value
    return WD_LABELS[sundayFirst]
}
private val MON_LABELS = arrayOf("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")
private fun monShort(ym: String): String = MON_LABELS[ym.substring(5, 7).toInt() - 1]
private fun trunc(s: String, n: Int = 22): String = if (s.length > n) s.take(n - 1) + "…" else s

// ---- generators (each: GenContext -> List<InsightCard>; order matches generators.ts) ----

fun genWeeklySummary(ctx: GenContext): List<InsightCard> {
    val last7 = ctx.days.takeLast(7)
    if (last7.size < 3) return emptyList()
    val prev7 = ctx.days.dropLast(7).takeLast(7)
    val inc = last7.sumOf { it.income }; val exp = last7.sumOf { it.expense }; val net = inc - exp
    val prevNet = prev7.sumOf { it.income } - prev7.sumOf { it.expense }
    val series = last7.map { SeriesPoint(weekdayLabel(it.day), major(ctx, it.income - it.expense)) }
    return listOf(InsightCard(
        id = "weekly:${last7.first().day}", type = "weekly_summary", theme = if (net >= 0) InsightTheme.POSITIVE else InsightTheme.WARNING,
        generatedAt = ctx.nowIso, periodStart = last7.first().day, periodEnd = last7.last().day, priority = 92,
        headline = if (net >= 0) "You saved ${ctx.fmt(net)} this week" else "You spent ${ctx.fmt(-net)} more than you earned",
        subhead = "Last 7 days",
        bullets = listOfNotNull(
            "Money in: ${ctx.fmt(inc)}", "Money out: ${ctx.fmt(exp)}",
            if (prev7.isNotEmpty()) "${if (net >= prevNet) "Up" else "Down"} ${ctx.fmt(abs(net - prevNet))} vs the week before" else "Your first week of tracking",
        ),
        metric = InsightMetric(display = ctx.fmt(net), raw = major(ctx, net), deltaPct = if (prev7.isNotEmpty() && prevNet != 0L) pctOf(net.toDouble(), prevNet.toDouble()) else null, direction = if (net >= prevNet) "up" else "down"),
        visual = VisualSpec.Area(series), cadenceKey = "weekly_summary", cadenceFrequency = "weekly",
    ))
}

fun genBudgetWarnings(ctx: GenContext): List<InsightCard> = ctx.budgets
    .filter { it.limit > 0 && it.spent.toDouble() / it.limit.toDouble() >= 0.8 }
    .sortedByDescending { it.spent.toDouble() / it.limit.toDouble() }
    .take(2)
    .map { b ->
        val ratio = b.spent.toDouble() / b.limit.toDouble(); val over = b.spent > b.limit
        InsightCard(
            id = "budget:${b.name}:${ctx.now.year}-${ctx.now.monthValue - 1}", type = "budget_warning", theme = InsightTheme.WARNING,
            generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = if (over) 100 else 96,
            headline = if (over) "${b.name} budget is over by ${ctx.fmt(b.spent - b.limit)}" else "${b.name} budget is ${(ratio * 100).roundToInt()}% used",
            subhead = if (over) "Over budget" else "Almost there",
            bullets = listOf("Spent ${ctx.fmt(b.spent)} of ${ctx.fmt(b.limit)}", if (over) "Consider easing off this category" else "${ctx.fmt(b.limit - b.spent)} left this period"),
            metric = InsightMetric(display = "${(ratio * 100).roundToInt()}%", raw = (ratio * 100).roundToInt().toDouble()),
            visual = VisualSpec.Gauge(value = major(ctx, b.spent), max = major(ctx, b.limit), warnAt = major(ctx, b.limit) * 0.8, dangerAt = major(ctx, b.limit), centerLabel = "${(ratio * 100).roundToInt()}%"),
            cta = InsightCta("Review budgets", "/budgets"), cadenceKey = "budget_warning:${b.name}", cadenceFrequency = "daily",
        )
    }

fun genSavingsAchievement(ctx: GenContext): List<InsightCard> {
    val m = ctx.months; if (m.isEmpty()) return emptyList()
    val cur = m.last(); val net = cur.income - cur.expense
    if (net <= 0 || cur.income <= 0) return emptyList()
    val rate = ((net.toDouble() / cur.income.toDouble()) * 100).roundToInt()
    val prev = if (m.size > 1) m[m.size - 2] else null; val prevNet = prev?.let { it.income - it.expense } ?: 0L
    return listOf(InsightCard(
        id = "savings:${cur.ym}", type = "savings_achievement", theme = InsightTheme.CELEBRATORY,
        generatedAt = ctx.nowIso, periodStart = "${cur.ym}-01", periodEnd = "${cur.ym}-01", priority = 84,
        headline = "You saved ${ctx.fmt(net)} in ${monShort(cur.ym)}", subhead = "That's a $rate% savings rate",
        bullets = listOf("Kept $rate% of what you earned", if (prev != null && net > prevNet) "Beat last month by ${ctx.fmt(net - prevNet)}" else "Every bit compounds"),
        metric = InsightMetric(display = "$rate%", raw = rate.toDouble(), direction = "up"),
        visual = VisualSpec.Progress(value = major(ctx, net), target = major(ctx, cur.income), centerLabel = "$rate%"),
        cadenceKey = "savings_achievement", cadenceFrequency = "monthly",
    ))
}

fun genSpendingTrend(ctx: GenContext): List<InsightCard> {
    val m = ctx.months.takeLast(6); if (m.size < 4) return emptyList()
    val half = m.size / 2
    fun avg(arr: List<MonthAgg>) = if (arr.isEmpty()) 0.0 else arr.sumOf { it.expense } / arr.size.toDouble()
    val recent = avg(m.drop(half)); val older = avg(m.take(half)); val down = recent <= older; val delta = pctOf(recent, older)
    val series = m.map { SeriesPoint(monShort(it.ym), major(ctx, it.expense)) }
    return listOf(InsightCard(
        id = "trend:${m.last().ym}", type = "spending_trend", theme = if (down) InsightTheme.POSITIVE else InsightTheme.WARNING,
        generatedAt = ctx.nowIso, periodStart = "${m.first().ym}-01", periodEnd = "${m.last().ym}-01", priority = 72,
        headline = if (down) "Your spending is trending down" else "Your spending is creeping up", subhead = "Over the last ${m.size} months",
        bullets = listOf("Recent months average ${fmtL(ctx, recent)}", "${if (down) "Down" else "Up"} ${abs(delta)}% vs earlier months"),
        metric = InsightMetric(display = "${if (delta > 0) "+" else ""}$delta%", raw = delta.toDouble(), direction = if (down) "down" else "up"),
        visual = VisualSpec.Area(series), cadenceKey = "spending_trend", cadenceFrequency = "weekly",
    ))
}

fun genCategoryBreakdown(ctx: GenContext): List<InsightCard> {
    val top = ctx.cats.filter { it.expense > 0 }.take(6); if (top.size < 2) return emptyList()
    val total = top.sumOf { it.expense }; val lead = top.first()
    return listOf(InsightCard(
        id = "cats:${ctx.now.year}-${ctx.now.monthValue - 1}", type = "category_breakdown", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 62,
        headline = "Where your money went", subhead = "This month, by category",
        bullets = listOf("${lead.name} led at ${ctx.fmt(lead.expense)}", "${((lead.expense.toDouble() / total.toDouble()) * 100).roundToInt()}% of your tracked spending"),
        metric = InsightMetric(display = ctx.fmt(total), raw = major(ctx, total)),
        visual = VisualSpec.Donut(series = top.map { SeriesPoint(it.name, major(ctx, it.expense)) }, centerLabel = ctx.fmt(total), centerSub = "this month"),
        cadenceKey = "category_breakdown", cadenceFrequency = "weekly",
    ))
}

fun genStreak(ctx: GenContext): List<InsightCard> {
    if (ctx.streak < 3) return emptyList()
    return listOf(InsightCard(
        id = "streak:${ctx.now}", type = "streak", theme = InsightTheme.CELEBRATORY,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 55,
        headline = "${ctx.streak}-day logging streak", subhead = "Consistency pays off",
        bullets = listOf("You've logged transactions ${ctx.streak} days running", "The best budgets are the ones you actually keep"),
        metric = InsightMetric(display = "${ctx.streak}", raw = ctx.streak.toDouble(), direction = "up"),
        visual = VisualSpec.Bars(series = ctx.txnDays7.map { SeriesPoint(weekdayLabel(it.day), it.count.toDouble()) }, unit = "txns"),
        cadenceKey = "streak", cadenceFrequency = "daily",
    ))
}

fun genBiggestExpense(ctx: GenContext): List<InsightCard> {
    val top = ctx.topExpenses.filter { it.amount > 0 }.take(5); if (top.isEmpty()) return emptyList()
    val lead = top.first()
    return listOf(InsightCard(
        id = "bigexp:${ctx.now.year}-${ctx.now.monthValue - 1}", type = "biggest_expense", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 68,
        headline = "Your biggest expense was ${ctx.fmt(lead.amount)}", subhead = lead.label.ifBlank { "This month" },
        bullets = top.take(3).map { "${it.label}: ${ctx.fmt(it.amount)}" },
        metric = InsightMetric(display = ctx.fmt(lead.amount), raw = major(ctx, lead.amount)),
        visual = VisualSpec.Bars(series = top.map { SeriesPoint(trunc(it.label, 16), major(ctx, it.amount)) }, horizontal = true),
        cadenceKey = "biggest_expense", cadenceFrequency = "weekly",
    ))
}

fun genWeekdayPattern(ctx: GenContext): List<InsightCard> {
    val nonzero = ctx.weekday.filter { it.value > 0 }; if (nonzero.size < 3) return emptyList()
    val top = ctx.weekday.maxByOrNull { it.value } ?: return emptyList()
    return listOf(InsightCard(
        id = "weekday:${ctx.now.year}-${ctx.now.monthValue}", type = "weekday_pattern", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 50,
        headline = "${ctx.weekdayTop} is your priciest day", subhead = "Average spend by weekday · last 60 days",
        bullets = listOf("You spend most on ${ctx.weekdayTop}s", "Around ${ctx.fmt(minorOf(ctx, top.value))} on an average ${ctx.weekdayTop}"),
        visual = VisualSpec.Bars(series = ctx.weekday), cadenceKey = "weekday_pattern", cadenceFrequency = "weekly",
    ))
}

fun genLabelBreakdown(ctx: GenContext): List<InsightCard> {
    val top = ctx.labels.filter { it.expense > 0 }.take(6); if (top.size < 2) return emptyList()
    val total = top.sumOf { it.expense }; val lead = top.first()
    return listOf(InsightCard(
        id = "labels:${ctx.now.year}-${ctx.now.monthValue - 1}", type = "label_breakdown", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 54,
        headline = "Spending by label", subhead = "This month, across your tags",
        bullets = listOf("${lead.name} topped your labels at ${ctx.fmt(lead.expense)}", "${top.size} labels tracked this month"),
        metric = InsightMetric(display = ctx.fmt(total), raw = major(ctx, total)),
        visual = VisualSpec.Donut(series = top.map { SeriesPoint(it.name, major(ctx, it.expense)) }, centerLabel = ctx.fmt(total), centerSub = "labelled"),
        cadenceKey = "label_breakdown", cadenceFrequency = "weekly",
    ))
}

fun genSubscriptions(ctx: GenContext): List<InsightCard> {
    val subs = ctx.subs.filter { it.monthly > 0 }; if (subs.isEmpty()) return emptyList()
    val top = subs.sortedByDescending { it.monthly }.take(6)
    return listOf(InsightCard(
        id = "subs:${ctx.now.year}-${ctx.now.monthValue}", type = "subscriptions_load", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 64,
        headline = "${ctx.fmt(ctx.subsTotal)}/mo on subscriptions", subhead = "${subs.size} active subscription${if (subs.size == 1) "" else "s"}",
        bullets = listOf("Biggest: ${top.first().name} at ${ctx.fmt(top.first().monthly)}/mo", "That's ${ctx.fmt(ctx.subsTotal * 12)} a year"),
        metric = InsightMetric(display = ctx.fmt(ctx.subsTotal), raw = major(ctx, ctx.subsTotal)),
        visual = VisualSpec.Donut(series = top.map { SeriesPoint(it.name, major(ctx, it.monthly)) }, centerLabel = ctx.fmt(ctx.subsTotal), centerSub = "per month"),
        cta = InsightCta("Manage subscriptions", "/subscriptions"), cadenceKey = "subscriptions_load", cadenceFrequency = "monthly",
    ))
}

fun genMonthPace(ctx: GenContext): List<InsightCard> {
    val p = ctx.pace; if (p.dayOfMonth < 3 || p.lastSameSoFar <= 0) return emptyList()
    val projected = (p.thisSoFar / p.dayOfMonth) * p.daysInMonth
    val faster = p.thisSoFar > p.lastSameSoFar
    return listOf(InsightCard(
        id = "pace:${ctx.now.year}-${ctx.now.monthValue}", type = "month_pace", theme = if (faster) InsightTheme.WARNING else InsightTheme.POSITIVE,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 74,
        headline = if (faster) "You're spending faster than last month" else "You're pacing under last month",
        subhead = "Day ${p.dayOfMonth} of ${p.daysInMonth}",
        bullets = listOf(
            "Spent ${fmtL(ctx, p.thisSoFar)} so far (was ${fmtL(ctx, p.lastSameSoFar)} by now last month)",
            "On track for about ${fmtL(ctx, projected)} vs ${fmtL(ctx, p.lastFull)} last month",
        ),
        metric = InsightMetric(display = fmtL(ctx, projected), raw = majorD(ctx, projected), direction = if (faster) "up" else "down"),
        visual = VisualSpec.Area(p.cumulative), cadenceKey = "month_pace", cadenceFrequency = "daily",
    ))
}

fun genNoSpendDays(ctx: GenContext): List<InsightCard> {
    val n = ctx.noSpend; if (n.daysElapsed < 5) return emptyList()
    return listOf(InsightCard(
        id = "nospend:${ctx.now.year}-${ctx.now.monthValue}", type = "no_spend_days", theme = InsightTheme.POSITIVE,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 48,
        headline = "${n.noSpendDays} no-spend day${if (n.noSpendDays == 1) "" else "s"} this month", subhead = "Out of ${n.daysElapsed} days so far",
        bullets = listOf("You didn't spend on ${n.noSpendDays} of ${n.daysElapsed} days", "No-spend days are an easy savings win"),
        metric = InsightMetric(display = "${n.noSpendDays}", raw = n.noSpendDays.toDouble()),
        visual = VisualSpec.Donut(
            series = listOf(SeriesPoint("No-spend", n.noSpendDays.toDouble(), "positive"), SeriesPoint("Spent", n.spendDays.toDouble(), "border")),
            centerLabel = "${n.noSpendDays}", centerSub = "no-spend days",
        ),
        cadenceKey = "no_spend_days", cadenceFrequency = "weekly",
    ))
}

fun genGoalProgress(ctx: GenContext): List<InsightCard> {
    val eligible = ctx.goals.filter { it.target > 0 }; if (eligible.isEmpty()) return emptyList()
    val unfinished = eligible.filter { it.saved < it.target }.sortedByDescending { it.saved.toDouble() / it.target.toDouble() }
    val g = unfinished.firstOrNull() ?: eligible.find { it.emergency } ?: eligible.first()
    val ratio = min(1.0, g.saved.toDouble() / g.target.toDouble()); val doneP = (ratio * 100).roundToInt()
    return listOf(InsightCard(
        id = "goal:${g.name}", type = "goal_progress", theme = if (doneP >= 100) InsightTheme.CELEBRATORY else InsightTheme.POSITIVE,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 60,
        headline = if (doneP >= 100) "${g.name} is fully funded!" else "${g.name} is $doneP% funded", subhead = "Goal progress",
        bullets = listOf("${ctx.fmt(g.saved)} of ${ctx.fmt(g.target)} set aside", if (doneP >= 100) "Time to set your next goal" else "${ctx.fmt(g.target - g.saved)} to go"),
        metric = InsightMetric(display = "$doneP%", raw = doneP.toDouble(), direction = "up"),
        visual = VisualSpec.Gauge(value = major(ctx, g.saved), max = major(ctx, g.target), centerLabel = "$doneP%"),
        cta = InsightCta("View goals", "/goals"), cadenceKey = "goal_progress:${g.name}", cadenceFrequency = "weekly",
    ))
}

fun genCategorySpike(ctx: GenContext): List<InsightCard> {
    val s = ctx.catSpike ?: return emptyList()
    val up = pctOf(s.thisMonth, s.avgPrior)
    return listOf(InsightCard(
        id = "spike:${s.name}:${ctx.now.year}-${ctx.now.monthValue}", type = "category_spike", theme = InsightTheme.WARNING,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 78,
        headline = "${s.name} spending jumped $up%", subhead = "vs your recent average",
        bullets = listOf("${fmtL(ctx, s.thisMonth)} this month", "Usually around ${fmtL(ctx, s.avgPrior)}"),
        metric = InsightMetric(display = "+$up%", raw = up.toDouble(), direction = "up"),
        visual = VisualSpec.Bars(series = listOf(SeriesPoint("Usual", majorD(ctx, s.avgPrior), "forest"), SeriesPoint("This mo", majorD(ctx, s.thisMonth), "warning"))),
        cta = InsightCta("See transactions", "/transactions"), cadenceKey = "category_spike", cadenceFrequency = "weekly",
    ))
}

fun genAvgDaily(ctx: GenContext): List<InsightCard> {
    val p = ctx.pace; if (p.dayOfMonth < 3) return emptyList()
    val (thisAvg, lastAvg) = ctx.avgDaily.let { it.thisAvg to it.lastAvg }; if (thisAvg <= 0 && lastAvg <= 0) return emptyList()
    val lower = thisAvg <= lastAvg
    return listOf(InsightCard(
        id = "avgday:${ctx.now.year}-${ctx.now.monthValue}", type = "avg_daily_spend", theme = if (lower) InsightTheme.POSITIVE else InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 52,
        headline = "You're averaging ${fmtL(ctx, thisAvg)}/day", subhead = if (lastAvg > 0) "${if (lower) "Down from" else "Up from"} ${fmtL(ctx, lastAvg)}/day last month" else "So far this month",
        bullets = listOf("${fmtL(ctx, thisAvg)} per day this month", if (lastAvg > 0) "${fmtL(ctx, lastAvg)} per day last month" else "Keep it steady"),
        metric = InsightMetric(display = fmtL(ctx, thisAvg), raw = majorD(ctx, thisAvg), direction = if (lower) "down" else "up"),
        visual = VisualSpec.Bars(series = listOf(SeriesPoint("Last mo", majorD(ctx, lastAvg), "forest"), SeriesPoint("This mo", majorD(ctx, thisAvg), "accent"))),
        cadenceKey = "avg_daily_spend", cadenceFrequency = "weekly",
    ))
}

fun genDividends(ctx: GenContext): List<InsightCard> {
    val d = ctx.dividends ?: return emptyList()
    if (d.holdings == 0) return emptyList()
    if (d.total <= 0) return emptyList()
    val series = d.buckets.filter { it.value != 0.0 }.takeLast(8); if (series.isEmpty()) return emptyList()
    val headlineAmt = if (d.trailing12 > 0) d.trailing12 else d.total
    return listOf(InsightCard(
        id = "dividends:${ctx.now.year}-${ctx.now.monthValue}", type = "dividend_income", theme = InsightTheme.POSITIVE,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 66,
        headline = if (d.trailing12 > 0) "${ctx.fmt(d.trailing12)} in dividends this year" else "${ctx.fmt(d.total)} in dividends so far",
        subhead = "From ${d.holdings} holding${if (d.holdings == 1) "" else "s"}",
        bullets = listOf("Last 12 months: ${ctx.fmt(d.trailing12)}", if (d.upcoming12 > 0) "Next 12 months (est.): ${ctx.fmt(d.upcoming12)}" else "All-time: ${ctx.fmt(d.total)}"),
        metric = InsightMetric(display = ctx.fmt(headlineAmt), raw = major(ctx, headlineAmt)),
        visual = VisualSpec.Bars(series = series),
        cta = InsightCta("See dividends", "/investments"), cadenceKey = "dividend_income", cadenceFrequency = "monthly",
    ))
}

fun genProjection(ctx: GenContext): List<InsightCard> {
    val p = ctx.projection ?: return emptyList()
    if (p.holdings == 0) return emptyList()
    if (p.currentValue <= 0) return emptyList()
    val growthPortion = max(0.0, p.endValue - p.contributed)
    return listOf(InsightCard(
        id = "projection:${ctx.now.year}-${ctx.now.monthValue}", type = "portfolio_projection", theme = InsightTheme.NEUTRAL,
        generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = 59,
        headline = "Your portfolio could reach ${fmtL(ctx, p.endValue)}", subhead = "In ${p.years} years at ${p.growthPct}% a year",
        bullets = listOf("${fmtL(ctx, p.currentValue)} invested today", "About ${fmtL(ctx, growthPortion)} of that would be growth", "A projection on default assumptions, not a forecast"),
        metric = InsightMetric(display = fmtL(ctx, p.endValue), raw = majorD(ctx, p.endValue), direction = "up"),
        visual = VisualSpec.Area(p.series),
        cta = InsightCta("Adjust assumptions", "/investments"), cadenceKey = "portfolio_projection", cadenceFrequency = "monthly",
    ))
}

fun genMindfulness(ctx: GenContext): List<InsightCard> {
    val txns = ctx.mindfulnessTxns ?: return emptyList()
    val t1 = computeTier1Insights(txns, ctx.currency, ctx.fmt); val t2 = computeTier2Insights(txns)
    return (t1 + t2).map { i ->
        InsightCard(
            id = "mindfulness:${i.id}:${ctx.now}", type = "mindfulness",
            theme = when (i.severity) { "warn" -> InsightTheme.WARNING; "success" -> InsightTheme.POSITIVE; else -> InsightTheme.NEUTRAL },
            generatedAt = ctx.nowIso, periodStart = "", periodEnd = "", priority = if (i.type == "tier2") 80 else 45,
            headline = i.title, subhead = if (i.type == "tier2") "Need vs Greed" else "Spending Insight",
            bullets = listOf(i.body), visual = null, cadenceKey = "mindfulness:${i.id}", cadenceFrequency = "weekly",
        )
    }
}

private val GENERATORS: List<(GenContext) -> List<InsightCard>> = listOf(
    ::genBudgetWarnings, ::genCategorySpike, ::genMonthPace, ::genWeeklySummary, ::genSpendingTrend,
    ::genBiggestExpense, ::genSubscriptions, ::genCategoryBreakdown, ::genGoalProgress, ::genSavingsAchievement,
    ::genStreak, ::genLabelBreakdown, ::genAvgDaily, ::genWeekdayPattern, ::genNoSpendDays,
    ::genDividends, ::genProjection, ::genMindfulness,
)

/** Run every generator, then rank + dedupe by cadence key, capped to [limit]. */
fun composeStack(ctx: GenContext, limit: Int = 12): List<InsightCard> {
    val all = GENERATORS.flatMap { it(ctx) }
    val byKey = LinkedHashMap<String, InsightCard>()
    for (c in all) {
        val existing = byKey[c.cadenceKey]
        if (existing == null || c.priority > existing.priority) byKey[c.cadenceKey] = c
    }
    return byKey.values.sortedByDescending { it.priority }.take(limit)
}
