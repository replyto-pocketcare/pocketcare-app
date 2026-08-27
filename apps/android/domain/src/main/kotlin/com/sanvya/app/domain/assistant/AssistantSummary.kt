package com.sanvya.app.domain.assistant

/**
 * The financial snapshot the assistant is given — and the only financial data
 * that ever leaves the device.
 *
 * Ported from `apps/web/src/assistant/summary.ts`. Web's header makes the claim
 * and this type is what enforces it: **aggregates only, never raw
 * transactions.** No merchant names, no dates of individual spends, no
 * counterparties. Amounts are MAJOR units here rather than minor, because the
 * model reads them and "6400" is a worse prompt than "6400.00" is a better one.
 *
 * Building this is repository work; SHAPING it for the prompt is not, and that
 * half is here under vectors — because the prompt is an input to the model, and
 * a phone that sent a differently-shaped prompt would get different answers to
 * the same question.
 *
 * Mirrors iOS's AssistantSummary.swift.
 */

data class SummaryAccount(
    val id: String,
    val name: String,
    val type: String,
    val currency: String,
    /** Major units. */
    val balance: Double,
)

data class SummaryGoal(val name: String, val target: Double, val saved: Double, val currency: String)

data class SummaryUpcoming(val name: String, val date: String, val amount: Double, val currency: String)

data class SummarySplits(val owed: Double, val owe: Double, val groups: Int)

data class SummaryMonth(val ym: String, val income: Double, val expense: Double)

data class SummaryCategory(val name: String, val amount: Double)

data class FinancialSummary(
    val baseCurrency: String,
    /** YYYY-MM-DD. Carried for the caller; deliberately NOT sent in the prompt. */
    val today: String,
    val accounts: List<SummaryAccount> = emptyList(),
    val liquidSavings: Double = 0.0,
    val avgMonthlyIncome: Double = 0.0,
    val avgMonthlyExpense: Double = 0.0,
    val monthlySurplus: Double = 0.0,
    val fixedMonthlyObligations: Double = 0.0,
    val goals: List<SummaryGoal> = emptyList(),
    val upcoming: List<SummaryUpcoming> = emptyList(),
    val splits: SummarySplits = SummarySplits(0.0, 0.0, 0),
    /** Last 6 calendar months of income vs expense, major units. */
    val monthlyCashflow: List<SummaryMonth> = emptyList(),
    /** Top expense categories over the last ~3 months, major units. */
    val topCategories: List<SummaryCategory> = emptyList(),
)

/** Web's own caps. Every one of them is a token budget, not a display choice. */
internal const val SUMMARY_MAX_ACCOUNTS = 12
internal const val SUMMARY_MAX_GOALS = 12
internal const val SUMMARY_MAX_UPCOMING = 8

/**
 * `JSON.stringify` on a number that is an exact multiple of one hundredth.
 *
 * The general JS algorithm is shortest-round-trip and is a genuinely hard thing
 * to reimplement twice identically. It is also unnecessary here: EVERY number in
 * this prompt comes from web's `major()`, which is `Math.round(minor) / 100`, or
 * from `monthlySurplus`, which is `+(x).toFixed(2)`. Both are an integer number
 * of hundredths, and for those the formatting is three cases.
 *
 * The narrow contract is the point. `Double.toString()` gives `1234.0` on
 * Kotlin, Swift's gives `1234.0` too, and JS gives `1234` — a general
 * "close enough" formatter would put a different prompt in front of the model
 * on each platform and nothing would ever fail loudly.
 */
internal fun jsonHundredths(v: Double): String {
    // `Math.round` semantics -- half UP -- though the input should already be
    // integral and this is only absorbing float noise.
    val cents = kotlin.math.floor(v * 100 + 0.5).toLong()
    if (cents == 0L) return "0"
    val negative = cents < 0
    val abs = kotlin.math.abs(cents)
    val whole = abs / 100
    val frac = abs % 100
    val body = when {
        frac == 0L -> "$whole"
        frac % 10 == 0L -> "$whole.${frac / 10}"
        else -> "$whole." + frac.toString().padStart(2, '0')
    }
    return if (negative) "-$body" else body
}

/**
 * `JSON.stringify` on a string.
 *
 * Non-ASCII is left ALONE, which is what JSON.stringify does — escaping it
 * would be valid JSON and a different prompt, and merchant names in this app are
 * routinely Devanagari.
 */
internal fun jsonQuote(s: String): String {
    val sb = StringBuilder(s.length + 2)
    sb.append('"')
    for (c in s) {
        when {
            c == '"' -> sb.append("\\\"")
            c == '\\' -> sb.append("\\\\")
            c == '\n' -> sb.append("\\n")
            c == '\r' -> sb.append("\\r")
            c == '\t' -> sb.append("\\t")
            c == '\b' -> sb.append("\\b")
            c == '\u000C' -> sb.append("\\f")
            c < ' ' -> sb.append("\\u").append("%04x".format(c.code))
            else -> sb.append(c)
        }
    }
    sb.append('"')
    return sb.toString()
}

private fun obj(vararg fields: String) = fields.joinToString(",", "{", "}")
private fun field(key: String, value: String) = "${jsonQuote(key)}:$value"
private fun <T> arr(items: List<T>, render: (T) -> String) = items.joinToString(",", "[", "]", transform = render)

/**
 * Compact, token-light JSON of the summary — the exact string web sends.
 *
 * Empty sections are dropped and lists are capped, both to save tokens. Two
 * details are easy to lose and are load-bearing:
 *
 * * **`today` is not sent.** It is on the type for the caller's use; the prompt
 *   carries the date separately.
 * * **`upcoming` drops its currency.** Web's projection is `{n, date, amt}` and
 *   nothing else, so a renewal in a second currency is sent as a bare number.
 *   That is web's behaviour, reproduced rather than fixed — a phone that sent an
 *   extra field would be answering a different prompt.
 */
fun summaryForPrompt(s: FinancialSummary): String {
    val out = mutableListOf(
        field("baseCurrency", jsonQuote(s.baseCurrency)),
        field("liquidSavings", jsonHundredths(s.liquidSavings)),
        field("avgMonthlyIncome", jsonHundredths(s.avgMonthlyIncome)),
        field("avgMonthlyExpense", jsonHundredths(s.avgMonthlyExpense)),
        field("monthlySurplus", jsonHundredths(s.monthlySurplus)),
        field("fixedMonthlyObligations", jsonHundredths(s.fixedMonthlyObligations)),
        field(
            "accounts",
            arr(s.accounts.take(SUMMARY_MAX_ACCOUNTS)) { a ->
                obj(
                    field("id", jsonQuote(a.id)),
                    field("n", jsonQuote(a.name)),
                    field("t", jsonQuote(a.type)),
                    field("c", jsonQuote(a.currency)),
                    field("bal", jsonHundredths(a.balance)),
                )
            },
        ),
    )
    if (s.goals.isNotEmpty()) {
        out.add(
            field(
                "goals",
                arr(s.goals.take(SUMMARY_MAX_GOALS)) { g ->
                    obj(
                        field("n", jsonQuote(g.name)),
                        field("target", jsonHundredths(g.target)),
                        field("saved", jsonHundredths(g.saved)),
                        field("c", jsonQuote(g.currency)),
                    )
                },
            ),
        )
    }
    if (s.upcoming.isNotEmpty()) {
        out.add(
            field(
                "upcoming",
                arr(s.upcoming.take(SUMMARY_MAX_UPCOMING)) { u ->
                    obj(
                        field("n", jsonQuote(u.name)),
                        field("date", jsonQuote(u.date)),
                        field("amt", jsonHundredths(u.amount)),
                    )
                },
            ),
        )
    }
    // Any ONE of the three being non-zero sends all three -- "you owe nothing
    // and are owed nothing across 3 groups" is a real answer.
    if (s.splits.owed != 0.0 || s.splits.owe != 0.0 || s.splits.groups != 0) {
        out.add(
            field(
                "splits",
                obj(
                    field("friendsOweYou", jsonHundredths(s.splits.owed)),
                    field("youOwe", jsonHundredths(s.splits.owe)),
                    field("groups", s.splits.groups.toString()),
                ),
            ),
        )
    }
    // A run of all-zero months is six months of nothing, and saying so costs
    // tokens the model cannot use.
    if (s.monthlyCashflow.any { it.income != 0.0 || it.expense != 0.0 }) {
        out.add(
            field(
                "monthly",
                arr(s.monthlyCashflow) { m ->
                    obj(
                        field("ym", jsonQuote(m.ym)),
                        field("in", jsonHundredths(m.income)),
                        field("exp", jsonHundredths(m.expense)),
                    )
                },
            ),
        )
    }
    if (s.topCategories.isNotEmpty()) {
        out.add(
            field(
                "topSpendCategories",
                arr(s.topCategories) { c ->
                    obj(field("n", jsonQuote(c.name)), field("amt", jsonHundredths(c.amount)))
                },
            ),
        )
    }
    return out.joinToString(",", "{", "}")
}
