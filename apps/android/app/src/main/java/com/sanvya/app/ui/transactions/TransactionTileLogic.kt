package com.sanvya.app.ui.transactions

import androidx.compose.ui.graphics.Color
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.domain.splits.SplitInfo
import com.sanvya.app.ui.formatMoney
import java.time.OffsetDateTime
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * Ported byte-for-byte from apps/web/src/ui/TransactionTile.tsx's
 * avatarColor/merchantTitle/txTags -- the shared row logic used everywhere a
 * transaction is listed on web (Transactions, Search, Statements, Dashboard
 * recent activity). Kept in its own file per the Phase B "component reuse"
 * rule -- TransactionsScreen.kt is the first caller but Dashboard's eventual
 * real "Recent Activity" tile should use this too, not a second copy.
 */

private val AVATAR_COLORS = listOf(
    Color(0xFFB06A4F), Color(0xFF5F7A52), Color(0xFFC08A3E), Color(0xFF7A4A6B),
    Color(0xFF2F6F6A), Color(0xFF7C4A3A), Color(0xFF9CAE8E),
)

/** Deterministic per-string color -- matches `[...s].reduce((a,c) => a + c.charCodeAt(0), 0) % AV.length`. */
fun avatarColor(s: String): Color {
    if (s.isEmpty()) return AVATAR_COLORS[0]
    val sum = s.sumOf { it.code }
    return AVATAR_COLORS[sum % AVATAR_COLORS.size]
}

private val NARRATION_PREFIX = Regex("^(upi|imps|neft|ach|bil|inft|rtgs|nach|pos)$", RegexOption.IGNORE_CASE)
private val HAS_LETTERS = Regex("[a-z]{3,}", RegexOption.IGNORE_CASE)
private val ALL_DIGITS = Regex("^\\d+$")

/** "UPI/ASHISH ALA/1234/Payment" -> "ASHISH ALA". Falls back to the raw
 * string (capped at 40 chars). Matches merchantTitle() exactly. */
fun merchantTitle(desc: String): String {
    val parts = desc.split("/").map { it.trim() }.filter { it.isNotEmpty() }
    if (parts.size >= 2 && NARRATION_PREFIX.matches(parts[0])) {
        val name = parts.drop(1).firstOrNull { HAS_LETTERS.containsMatchIn(it) && !ALL_DIGITS.matches(it) }
        return (name ?: parts[1]).take(34)
    }
    return desc.take(40)
}

data class TxTag(val icon: String, val text: String)

/** Category first (skipped if "Uncategorised" and there are labels), then
 * each label. Matches txTags() exactly. */
fun txTags(categoryName: String?, labels: List<String>?): List<TxTag> {
    val out = mutableListOf<TxTag>()
    val names = labels?.filter { it.isNotBlank() } ?: emptyList()
    if (categoryName != null && !(names.isNotEmpty() && categoryName.equals("uncategorised", ignoreCase = true))) {
        out += TxTag("category", categoryName)
    }
    for (n in names) out += TxTag("label", n)
    return out
}

/* ------------------------------------------------------------------ *
 * The row model, and the one function that builds it.
 *
 * Both lived inside TransactionsViewModel, private, until 2026-08-25 --
 * which is why this file's own comment above says the dashboard's Recent
 * Activity tile "should use this too, not a second copy". It could not: the
 * shape it needed was sealed inside a view model it had no business owning.
 *
 * Promoted rather than copied. Re-inlining is the failure mode this section of
 * the audit exists to catch, and it had already happened twice (DonutChart and
 * this row are both listed there).
 * ------------------------------------------------------------------ */

data class TransactionListItem(
    val id: String,
    val title: String,
    val subtitle: String,
    val tags: List<TxTag>,
    val accountName: String?,
    val amountFormatted: String,
    val amountColor: TxAmountColor,
    /**
     * True when this row stands for a whole split expense rather than one
     * posting of it -- the row shows a "Split" chip and the amount you paid.
     */
    val isSplit: Boolean,
    /**
     * True when a receipt photo created this transaction -- the row shows a
     * "Scanned" chip. Web's `scannedIds.has(tx.id)`, from `receipt_scans`.
     */
    val isScanned: Boolean,
    val dateFormatted: String,
    val avatarColor: androidx.compose.ui.graphics.Color,
    val avatarLetter: String,
)

enum class TxAmountColor { POSITIVE, DEFAULT }

/**
 * @param split set when this row is the surviving posting of a collapsed split
 *   expense. It changes three things, all of them web's rules: the amount
 *   becomes what you actually PAID (`displayPaid`, in the expense's own
 *   currency) rather than this one posting's figure, the sign is always
 *   negative and the colour never the income green, and the account name is
 *   dropped -- a split spans up to three accounts, so naming one would be a lie.
 * @param scanned set when a receipt photo produced this transaction. Defaults
 *   to false because only the Transactions list carries the chip -- web passes
 *   `scanned` from `<TransactionTile>` there and nowhere else, so Search and
 *   the dashboard tile stay as they are rather than each growing a second
 *   `receipt_scans` watch for a pill they do not draw.
 */
fun transactionListItem(
    txn: TransactionRow,
    accountMap: Map<String, Account>,
    categoryMap: Map<String, CategoryRow>,
    labels: List<String>?,
    split: SplitInfo? = null,
    scanned: Boolean = false,
): TransactionListItem {
    val categoryName = txn.categoryId?.let { categoryMap[it]?.name } ?: "Uncategorised"
    val labelsCsv = labels?.joinToString(", ")
    val raw = (txn.description ?: labelsCsv ?: categoryName).trim().ifEmpty { txn.type }
    val title = merchantTitle(raw)
    val subtitle = if (raw != title) raw else ""
    val tags = txTags(categoryName, labels)
    val account = accountMap[txn.accountId]

    val isSplit = split != null
    val sign = if (isSplit || txn.type == "expense") "−" else if (txn.type == "income") "+" else ""
    val amountColor =
        if (txn.type == "income" && !isSplit) TxAmountColor.POSITIVE else TxAmountColor.DEFAULT
    // The TRANSACTION's currency, not the account's. Web passes `tx.currency`
    // here; reading the account's meant a foreign-currency charge on a rupee
    // card rendered with the wrong symbol, and `baseCurrencyNow()` as the
    // fallback hid it whenever the account lookup missed.
    val amountFormatted =
        "$sign${formatMoney(split?.displayPaid ?: txn.amount, split?.currency ?: txn.currency)}"

    val dateFormatted = try {
        val zdt = OffsetDateTime.parse(txn.occurredAt).atZoneSameInstant(ZoneId.systemDefault())
        val today = OffsetDateTime.now().atZoneSameInstant(ZoneId.systemDefault())
        when (zdt.toLocalDate()) {
            today.toLocalDate() -> "Today"
            today.toLocalDate().minusDays(1) -> "Yesterday"
            else -> zdt.format(DateTimeFormatter.ofPattern("MMM d"))
        }
    } catch (e: Exception) {
        txn.occurredAt.take(10)
    }

    return TransactionListItem(
        id = txn.id,
        title = title,
        subtitle = subtitle,
        tags = tags,
        accountName = if (isSplit) null else account?.name,
        amountFormatted = amountFormatted,
        amountColor = amountColor,
        isSplit = isSplit,
        isScanned = scanned,
        dateFormatted = dateFormatted,
        avatarColor = avatarColor(title),
        avatarLetter = (title.firstOrNull() ?: '•').uppercase(),
    )
}
