package com.sanvya.app.ui.transactions

import androidx.compose.ui.graphics.Color
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.TransactionRow
import com.sanvya.app.ui.baseCurrencyNow
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
    val dateFormatted: String,
    val avatarColor: androidx.compose.ui.graphics.Color,
    val avatarLetter: String,
)

enum class TxAmountColor { POSITIVE, DEFAULT }

fun transactionListItem(
    txn: TransactionRow,
    accountMap: Map<String, Account>,
    categoryMap: Map<String, CategoryRow>,
    labels: List<String>?,
): TransactionListItem {
    val categoryName = txn.categoryId?.let { categoryMap[it]?.name } ?: "Uncategorised"
    val labelsCsv = labels?.joinToString(", ")
    val raw = (txn.description ?: labelsCsv ?: categoryName).trim().ifEmpty { txn.type }
    val title = merchantTitle(raw)
    val subtitle = if (raw != title) raw else ""
    val tags = txTags(categoryName, labels)
    val account = accountMap[txn.accountId]

    val sign = if (txn.type == "expense") "−" else if (txn.type == "income") "+" else ""
    val amountColor = if (txn.type == "income") TxAmountColor.POSITIVE else TxAmountColor.DEFAULT
    val amountFormatted = "$sign${formatMoney(txn.amount, account?.currency ?: baseCurrencyNow())}"

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
        accountName = account?.name,
        amountFormatted = amountFormatted,
        amountColor = amountColor,
        dateFormatted = dateFormatted,
        avatarColor = avatarColor(title),
        avatarLetter = (title.firstOrNull() ?: '•').uppercase(),
    )
}
