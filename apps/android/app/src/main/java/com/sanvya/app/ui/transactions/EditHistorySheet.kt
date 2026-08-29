package com.sanvya.app.ui.transactions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.sanvya.app.data.repository.Account
import com.sanvya.app.data.repository.CategoryRow
import com.sanvya.app.data.repository.PaymentMethodRow
import com.sanvya.app.data.repository.TransactionAudit
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.transactions.AuditChange
import com.sanvya.app.domain.transactions.AuditFromTo
import com.sanvya.app.domain.transactions.AuditSummary
import com.sanvya.app.domain.transactions.AuditValueKind
import com.sanvya.app.domain.transactions.summarizeAuditChanges
import com.sanvya.app.i18n.S
import com.sanvya.app.i18n.sRes
import com.sanvya.app.theme.LocalSanvyaColors
import com.sanvya.app.theme.SanvyaColors
import com.sanvya.app.ui.components.SanvyaModal
import com.sanvya.app.ui.formatMoneyAware
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * The edit-history modal from apps/web/app/transactions/[id]/edit/page.tsx.
 *
 * `transaction_audit` has recorded every change to every transaction since
 * migration 0001 and neither phone had a way to read it, so "what did I change,
 * and when?" had no answer outside the browser.
 *
 * Which fields are worth showing, and in what order, is decided in domain
 * (`summarizeAuditChanges`, vector-pinned) so the two phones cannot disagree.
 * This file does only what needs a locale: naming the fields, formatting the
 * values, and resolving ids to the names the user actually chose.
 */
@Composable
fun EditHistorySheet(
    open: Boolean,
    onClose: () -> Unit,
    entries: List<TransactionAudit>,
    currency: String,
    categories: List<CategoryRow>,
    accounts: List<Account>,
    paymentMethods: List<PaymentMethodRow>,
) {
    val colors = LocalSanvyaColors.current
    SanvyaModal(open = open, onClose = onClose, label = S.Transactions.editHistory(sRes())) {
        Text(
            S.Transactions.editHistory(sRes()),
            fontSize = 18.sp,
            fontWeight = FontWeight.Bold,
            color = colors.text,
        )
        if (entries.isEmpty()) {
            Text(S.Transactions.noEdits(sRes()), fontSize = 13.sp, color = colors.text2)
            return@SanvyaModal
        }
        // No scroll of its own. Web caps this list at 60vh and scrolls INSIDE
        // the modal; `SanvyaModal` already puts the whole card in a vertical
        // scroll for exactly that case, and a second scrollable in the same
        // axis would fight it for the gesture.
        Column(
            modifier = Modifier.fillMaxWidth(),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            entries.forEach { entry ->
                Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(
                        "${auditTimestampLabel(entry.createdAt)}$AUDIT_HEADER_SEPARATOR${auditActionLabel(entry.action)}",
                        fontSize = 12.sp,
                        color = colors.text2,
                    )
                    AuditChanges(
                        changes = entry.changes,
                        currency = currency,
                        categories = categories,
                        accounts = accounts,
                        paymentMethods = paymentMethods,
                        colors = colors,
                    )
                }
            }
        }
    }
}

@Composable
private fun AuditChanges(
    changes: String?,
    currency: String,
    categories: List<CategoryRow>,
    accounts: List<Account>,
    paymentMethods: List<PaymentMethodRow>,
    colors: SanvyaColors,
) {
    when (val summary = summarizeAuditChanges(parseAuditChanges(changes))) {
        is AuditSummary.Absent -> Unit
        is AuditSummary.MinorUpdate ->
            Text(S.Transactions.minorUpdate(sRes()), fontSize = 12.sp, color = colors.text2)
        is AuditSummary.Changes -> Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            summary.entries.forEach { change ->
                // Resolved BEFORE buildAnnotatedString: its builder lambda is
                // not @Composable, so a `sRes()` call inside it would not
                // compile -- and the error names the builder, not the string.
                val label = auditFieldLabel(change.field)
                val from = showAuditValue(change, change.from, currency, categories, accounts, paymentMethods)
                val to = showAuditValue(change, change.to, currency, categories, accounts, paymentMethods)
                Text(
                    buildAnnotatedString {
                        withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(label) }
                        append(AUDIT_LABEL_SEPARATOR)
                        withStyle(SpanStyle(color = colors.text2)) { append(from) }
                        append(AUDIT_CHANGE_ARROW)
                        append(to)
                    },
                    fontSize = 13.sp,
                    color = colors.text,
                )
            }
        }
    }
}

/**
 * One audit value, rendered.
 *
 * Mirrors web's `show()` case for case, with two deliberate differences, both
 * of them about not shipping English:
 *
 * * a TYPE renders through `txTypeLabel`, not `s.charAt(0).toUpperCase()`;
 * * a DATE renders in the device locale rather than the browser's.
 */
@Composable
private fun showAuditValue(
    change: AuditChange,
    raw: String?,
    currency: String,
    categories: List<CategoryRow>,
    accounts: List<Account>,
    paymentMethods: List<PaymentMethodRow>,
): String {
    if (raw == null) return AUDIT_ABSENT_VALUE
    return when (change.kind) {
        // Mask-aware, unlike web's bare `format(...)`. This is a DISPLAY
        // amount, not a field being typed into, and an unmasked amount on a
        // screen the user opened with hide-amounts on is the privacy-leak class
        // PARITY_AUDIT calls trap 7.
        AuditValueKind.MONEY -> raw.toLongOrNull()?.let { formatMoneyAware(money(it, currency)) } ?: raw
        AuditValueKind.DATE -> auditTimestampLabel(raw)
        AuditValueKind.CATEGORY -> categories.find { it.id == raw }?.name ?: AUDIT_ABSENT_VALUE
        AuditValueKind.ACCOUNT -> accounts.find { it.id == raw }?.name ?: AUDIT_ABSENT_VALUE
        AuditValueKind.PAYMENT_METHOD -> paymentMethods.find { it.id == raw }?.label ?: raw
        AuditValueKind.TYPE -> txTypeLabel(raw)
        AuditValueKind.TEXT -> raw
    }
}

/** The translated name of an audited column — web's `t(`audit.${field}`)`. */
@Composable
private fun auditFieldLabel(field: String): String = when (field) {
    "to_amount" -> S.Transactions.auditToAmount(sRes())
    "description" -> S.Transactions.auditDescription(sRes())
    "merchant" -> S.Transactions.auditMerchant(sRes())
    "note" -> S.Transactions.auditNote(sRes())
    "occurred_at" -> S.Transactions.auditOccurredAt(sRes())
    "type" -> S.Transactions.auditType(sRes())
    "category_id" -> S.Transactions.auditCategoryId(sRes())
    "account_id" -> S.Transactions.auditAccountId(sRes())
    "to_account_id" -> S.Transactions.auditToAccountId(sRes())
    "payment_method_id" -> S.Transactions.auditPaymentMethodId(sRes())
    "amount" -> S.Transactions.auditAmount(sRes())
    // Unreachable while domain's whitelist and these cases agree; the raw
    // column name is a better failure than a wrong label if they ever drift.
    else -> field
}

/**
 * "Updated" / "Deleted" — the two actions the write path records.
 *
 * Web prints the raw column ("update"), which is a lowercase English verb on
 * every screen in every language. An action nothing recognises falls back to
 * the raw value rather than being hidden, so a new one added later is visible
 * instead of silently blank.
 */
@Composable
private fun auditActionLabel(action: String): String = when (action) {
    "update" -> S.Transactions.auditActionUpdate(sRes())
    "delete" -> S.Transactions.auditActionDelete(sRes())
    else -> action
}

/**
 * Date AND time, in the device locale — web's `toLocaleString()`.
 *
 * `DateLabels.kt`'s helpers are date-only, and this is the one place in the app
 * that needs both halves; a fourth entry there for a single caller would be a
 * shared helper nothing shares. An unparseable timestamp renders as itself
 * rather than as a wrong date.
 */
private fun auditTimestampLabel(iso: String): String {
    val instant = runCatching { Instant.parse(iso) }.getOrNull() ?: return iso
    return instant.atZone(ZoneId.systemDefault())
        .format(DateTimeFormatter.ofLocalizedDateTime(FormatStyle.SHORT))
}

/**
 * The `changes` column, decoded into what domain's `summarizeAuditChanges`
 * takes. Null when the column is null or is not a JSON object — web's
 * `try { JSON.parse } catch { return null }`.
 *
 * `org.json`, not kotlinx.serialization, for the reason ReceiptDraftJson.kt
 * gives: the serialization library is test-scope only and does not ship.
 */
private fun parseAuditChanges(changes: String?): Map<String, AuditFromTo>? {
    if (changes.isNullOrEmpty()) return null
    val root = runCatching { JSONObject(changes) }.getOrNull() ?: return null
    val out = LinkedHashMap<String, AuditFromTo>()
    for (key in root.keys()) {
        val entry = root.optJSONObject(key) ?: continue
        out[key] = AuditFromTo(
            from = if (entry.isNull("from")) null else entry.optString("from"),
            to = if (entry.isNull("to")) null else entry.optString("to"),
        )
    }
    return out
}

/**
 * The three punctuation marks this sheet joins with.
 *
 * Glyphs, not copy: the middot between a timestamp and its action, the colon
 * after a field name and the arrow between two values are the same marks in
 * every language, so they stay out of the string files rather than being
 * duplicated into three of them. Same call as `AUTO_CATEGORISE_GLYPH`.
 */
private const val AUDIT_HEADER_SEPARATOR = " · "
private const val AUDIT_LABEL_SEPARATOR = ": "
private const val AUDIT_CHANGE_ARROW = " → "

/** Web's `"—"` for a value that was absent on one side of the change. */
private const val AUDIT_ABSENT_VALUE = "—"
