package com.sanvya.app.ui.transactions

import androidx.compose.ui.graphics.Color

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
