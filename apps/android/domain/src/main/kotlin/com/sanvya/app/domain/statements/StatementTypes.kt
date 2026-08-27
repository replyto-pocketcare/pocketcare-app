package com.sanvya.app.domain.statements

/**
 * Statement parsing/analysis domain types.
 *
 * Ported from `apps/web/src/statements/types.ts`. Fully on-device: statements
 * are parsed on the phone and never sent anywhere — the same claim web's header
 * makes, and the reason none of this touches a repository.
 *
 * Amounts are integer MINOR units and a transaction's [StatementTxn.amount] is
 * SIGNED: negative = debit/spend, positive = credit/received. Dates are ISO
 * `YYYY-MM-DD`.
 */

/** One printed line of a statement. */
data class StatementTxn(
    /** YYYY-MM-DD. */
    val date: String,
    val description: String,
    /** Minor units, signed (− debit / + credit). */
    val amount: Long,
    /** Running balance (minor), when the statement prints one. */
    val balance: Long? = null,
    /** Filled by the on-device categoriser at review time. */
    val category: String? = null,
    /** Cheque/UPI ref, when present. */
    val ref: String? = null,
)

/** Credit-card-only figures, read off the statement header. */
data class CardMeta(
    /** Statement balance / total outstanding (minor). */
    val totalDue: Long? = null,
    /** Minimum amount due (minor). */
    val minDue: Long? = null,
    /** YYYY-MM-DD. */
    val dueDate: String? = null,
    /** Amount due this cycle (minor). */
    val thisMonthDue: Long? = null,
)

/** The statement's date range. Either end can be unknown. */
data class StatementPeriod(val from: String? = null, val to: String? = null)

/**
 * How the columns were mapped, for the review UI and a manual override.
 *
 * Values are column INDICES as strings, which is what web stores — it keys them
 * by `String(ci)` so the mapping can round-trip through JSON and through a
 * `<select>` value without a second type.
 */
data class ColumnMapping(
    val date: String? = null,
    val description: String? = null,
    val debit: String? = null,
    val credit: String? = null,
    /** A single signed-amount column, the alternative to debit/credit. */
    val amount: String? = null,
    val balance: String? = null,
)

data class ParsedStatement(
    /** "bank" | "card". */
    val kind: String,
    /** Detected bank/card name, else a generic label. */
    val label: String,
    /** ISO code (defaults to the user's base). */
    val currency: String,
    val period: StatementPeriod,
    val openingBalance: Long? = null,
    val closingBalance: Long? = null,
    val txns: List<StatementTxn> = emptyList(),
    val card: CardMeta? = null,
    /** What the parser is unsure about — surfaced to the user, not swallowed. */
    val warnings: List<String> = emptyList(),
    val mapping: ColumnMapping? = null,
)
