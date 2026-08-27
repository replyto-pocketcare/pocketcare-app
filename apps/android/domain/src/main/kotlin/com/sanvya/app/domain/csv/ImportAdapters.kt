package com.sanvya.app.domain.csv

import kotlin.math.abs

/**
 * CSV import adapters, ported from apps/web/src/data/adapters.ts.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/ImportAdapters.swift.
 */

/** Canonical transaction shape all importers produce and the exporter emits. */
data class CanonRow(
    /** ISO date/datetime for `occurred_at`. */
    val date: String,
    /** income | expense | transfer | opening_balance | adjustment */
    val type: String,
    /** MAJOR units. Positive except for the signed types -- see [isSignedType]. */
    val amount: Double,
    val currency: String,
    /** From-account NAME, not id: a CSV has no ids. */
    val account: String,
    val toAccount: String? = null,
    val toAmount: Double? = null,
    val category: String? = null,
    val labels: List<String> = emptyList(),
    /** Display label, e.g. "UPI". */
    val paymentMethod: String? = null,
    val note: String? = null,
    val description: String? = null,
)

data class ImportAdapter(
    val id: String,
    val label: String,
    val beta: Boolean = false,
    /** Delimiter hint; null means auto-detect. */
    val delimiter: String? = null,
)

/**
 * Tolerates thousands separators and currency symbols; keeps sign and decimal.
 *
 * The comma rule is web's and is worth reading twice: a value with commas and
 * NO dot treats the last comma as a decimal point ("1.234,56" is European), and
 * anything else strips commas as thousands separators.
 */
internal fun parseAmount(v: String?): Double {
    if (v.isNullOrEmpty()) return 0.0
    val cleaned = Regex("[^0-9.,\\-]").replace(v, "").let { Regex(",(?=\\d{3}\\b)").replace(it, "") }
    val norm = if (cleaned.contains(",") && !cleaned.contains(".")) {
        cleaned.replaceFirst(",", ".")
    } else {
        cleaned.replace(",", "")
    }
    val n = jsParseFloat(norm) ?: return 0.0
    return if (n.isFinite()) n else 0.0
}

internal fun splitLabels(v: String?): List<String> =
    (v ?: "").split(Regex("[|,]")).map { it.trim() }.filter { it.isNotEmpty() }

/** Web's `toType`: read the words, then fall back to the sign. */
internal fun toType(t: String, amount: Double): String {
    val s = t.lowercase()
    return when {
        s.contains("transfer") -> "transfer"
        s.contains("income") || s.contains("deposit") || s.contains("credit") -> "income"
        s.contains("opening") -> "opening_balance"
        s.contains("adjust") -> "adjustment"
        s.contains("expens") || s.contains("debit") || s.contains("withdraw") -> "expense"
        else -> if (amount < 0) "expense" else "income"
    }
}

/**
 * `adjustment` and `opening_balance` carry a SIGNED amount -- the ledger adds
 * it as-is. `income`, `expense` and `transfer` are always positive, because the
 * type is what gives them their sign.
 */
internal fun isSignedType(t: String): Boolean = t == "adjustment" || t == "opening_balance"

/** Wallet's human payment labels -> PocketCare payment-method labels. */
private val WALLET_PAYMENT = mapOf(
    "mobile payment" to "UPI",
    "bank transfer" to "Net Banking",
    "web payment" to "Net Banking",
    "cash" to "Cash",
    "credit card" to "Credit Card",
    "debit card" to "Debit Card",
)

private val KNOWN_TYPES = setOf("income", "expense", "transfer", "opening_balance", "adjustment")

val IMPORT_ADAPTERS = listOf(
    ImportAdapter(id = "pocketcare", label = "PocketCare (CSV export)"),
    ImportAdapter(id = "wallet", label = "Wallet by BudgetBakers (beta)", beta = true, delimiter = ";"),
)

/** Column order for PocketCare's own export (matches the pocketcare adapter). */
val EXPORT_HEADERS = listOf(
    "Date", "Type", "Amount", "Currency", "Account", "To Account", "To Amount",
    "Category", "Labels", "Payment Method", "Note", "Description",
)

/**
 * Parses `text` with the named adapter, falling back to PocketCare's own format
 * for an unknown id -- which is web's behaviour.
 *
 * `nowIso` stands in for web's `new Date().toISOString()` default for a row
 * with no date. A parameter, not a clock read: nothing in domain reads a clock,
 * and it is what makes this vector-testable.
 */
fun parseWithAdapter(adapterId: String, text: String, nowIso: String): List<CanonRow> {
    val adapter = IMPORT_ADAPTERS.firstOrNull { it.id == adapterId } ?: IMPORT_ADAPTERS.first()
    val records = parseRecords(text, adapter.delimiter)
    val rows = if (adapter.id == "wallet") parseWallet(records, nowIso) else parsePocketCare(records, nowIso)
    return rows.filter { it.account.isNotEmpty() && it.amount != 0.0 }
}

private fun parsePocketCare(records: List<Map<String, String>>, nowIso: String): List<CanonRow> =
    records.map { r ->
        val raw = parseAmount(r["amount"])
        val t0 = (r["type"] ?: "").lowercase()
        val type = if (t0 in KNOWN_TYPES) t0 else toType(r["type"] ?: "", raw)
        val toAmountRaw = r["to amount"].orEmpty().ifEmpty { r["to_amount"].orEmpty() }
        CanonRow(
            date = r["date"].orEmpty().ifEmpty { nowIso },
            type = type,
            amount = if (isSignedType(type)) raw else abs(raw),
            currency = (r["currency"] ?: "").uppercase(),
            account = r["account"] ?: "",
            toAccount = r["to account"].orEmpty().ifEmpty { r["to_account"].orEmpty() }.ifEmpty { null },
            toAmount = if (toAmountRaw.isNotEmpty()) abs(parseAmount(toAmountRaw)) else null,
            category = r["category"]?.ifEmpty { null },
            labels = splitLabels(r["labels"]),
            paymentMethod = r["payment method"].orEmpty().ifEmpty { r["payment_method"].orEmpty() }.ifEmpty { null },
            note = r["note"]?.ifEmpty { null },
            description = r["description"]?.ifEmpty { null },
        )
    }

private fun parseWallet(records: List<Map<String, String>>, nowIso: String): List<CanonRow> =
    records.map { r ->
        val rawAmount = parseAmount(r["amount"])
        // Wallet splits a transfer into two one-sided rows (- on source, + on
        // destination) with no link between them. Each is imported as a signed
        // `adjustment` so both balances come out right without polluting the
        // income/expense statistics.
        val isTransfer = r["transfer"] == "true"
        val type = if (isTransfer) "adjustment" else toType(r["type"] ?: "", rawAmount)
        val payLocal = (r["payment_type_local"] ?: "").lowercase()
        CanonRow(
            date = r["date"].orEmpty().ifEmpty { nowIso },
            type = type,
            amount = if (isTransfer) rawAmount else abs(rawAmount),
            currency = (r["currency"] ?: "").uppercase(),
            account = r["account"] ?: "",
            category = if (isTransfer) null else r["category"]?.ifEmpty { null },
            labels = splitLabels(r["labels"]),
            paymentMethod = if (isTransfer) {
                null
            } else {
                WALLET_PAYMENT[payLocal] ?: r["payment_type_local"]?.ifEmpty { null }
            },
            note = if (isTransfer) {
                r["note"].orEmpty().ifEmpty { "Transfer" }
            } else {
                r["note"].orEmpty().ifEmpty { r["payee"].orEmpty() }.ifEmpty { null }
            },
        )
    }
