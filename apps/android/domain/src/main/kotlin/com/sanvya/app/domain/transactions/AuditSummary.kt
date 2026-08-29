package com.sanvya.app.domain.transactions

/**
 * What one `transaction_audit` row actually says, once the backend noise is
 * stripped out. Ported from the `AUDIT_LABELS` table and the `AuditChanges`
 * component in apps/web/app/transactions/[id]/edit/page.tsx.
 *
 * Web decides three things inline in a React component: which changed fields
 * are worth showing, in what order, and how each value should be rendered.
 * Only the rendering is locale-work; the other two are logic, and putting them
 * here is what stops Android and iOS from disagreeing about whether a given
 * edit shows as a real change or as "Minor update."
 *
 * The `changes` column is JSON, and neither Domain has a JSON dependency in its
 * main source set (see AssistantMarkdown's `AssistantJson` for the same
 * boundary and the same reason). So the caller parses, and this takes the
 * decoded map.
 *
 * Mirrors apps/ios/Domain/Sources/Domain/AuditSummary.swift.
 */

/**
 * How the view should render an audit value. Web switches on the field name
 * inside `show()`; naming the cases here keeps that decision on this side of
 * the boundary while leaving the actual formatting -- money, dates, the id to
 * name lookups -- to the platform that has a locale and the rows.
 */
enum class AuditValueKind {
    /** Minor units, formatted in the transaction's currency. */
    MONEY,

    /** An ISO timestamp. */
    DATE,

    /** A `categories.id` the view resolves to a name. */
    CATEGORY,

    /** An `accounts.id` the view resolves to a name. */
    ACCOUNT,

    /** A `payment_methods.id` the view resolves to a label. */
    PAYMENT_METHOD,

    /** A transaction type -- expense/income/transfer/adjustment. */
    TYPE,

    /** Shown as-is. */
    TEXT,
}

/** One field's before/after, as the `changes` column stores it. */
data class AuditFromTo(val from: String?, val to: String?)

/** One field's before/after, ready for the view. */
data class AuditChange(
    /** The column name, which is also the i18n key under `audit.`. */
    val field: String,
    val kind: AuditValueKind,
    /** Null means "absent" -- the view shows its placeholder, not an empty gap. */
    val from: String?,
    val to: String?,
)

/** What to draw for one audit row. */
sealed interface AuditSummary {
    /**
     * Draw nothing at all. Web's `AuditChanges` returns null both when the
     * column is null and when it will not parse.
     *
     * Named `Absent` rather than `None`: Swift's mirror of this type would
     * spell `None` as `.none`, which collides with `Optional.none` at every
     * call site that has an optional in scope.
     */
    data object Absent : AuditSummary

    /**
     * The row changed something, but nothing a user would recognise -- an id we
     * cannot resolve, a checksum, the soft-delete marker. Web's `minorUpdate`.
     */
    data object MinorUpdate : AuditSummary

    data class Changes(val entries: List<AuditChange>) : AuditSummary
}

/**
 * The fields worth showing, in the order they are shown.
 *
 * Web's `AUDIT_LABELS` is an object literal and it iterates `parsed`, so its
 * order is whatever order the WRITER happened to emit -- which differs between
 * the three clients that write this column. The whitelist's own order is used
 * here instead, so two devices looking at the same audit row list the same
 * fields the same way. That is a deliberate divergence, and the only one in
 * this file.
 */
val AUDIT_FIELDS: List<String> = listOf(
    "amount",
    "to_amount",
    "description",
    "merchant",
    "note",
    "occurred_at",
    "type",
    "category_id",
    "account_id",
    "to_account_id",
    "payment_method_id",
)

private fun kindOf(field: String): AuditValueKind = when (field) {
    "amount", "to_amount" -> AuditValueKind.MONEY
    "occurred_at" -> AuditValueKind.DATE
    "category_id" -> AuditValueKind.CATEGORY
    "account_id", "to_account_id" -> AuditValueKind.ACCOUNT
    "payment_method_id" -> AuditValueKind.PAYMENT_METHOD
    "type" -> AuditValueKind.TYPE
    else -> AuditValueKind.TEXT
}

/**
 * @param parsed the decoded `changes` object, or null when the column was null
 *   or did not parse as JSON.
 */
fun summarizeAuditChanges(parsed: Map<String, AuditFromTo>?): AuditSummary {
    if (parsed == null) return AuditSummary.Absent
    val entries = AUDIT_FIELDS.mapNotNull { field ->
        val fromTo = parsed[field] ?: return@mapNotNull null
        AuditChange(
            field = field,
            kind = kindOf(field),
            // Web's `show()` collapses null, undefined and "" to the same
            // placeholder, so an empty string is an ABSENT value here rather
            // than a value that happens to be empty.
            from = fromTo.from?.takeIf { it.isNotEmpty() },
            to = fromTo.to?.takeIf { it.isNotEmpty() },
        )
    }
    return if (entries.isEmpty()) AuditSummary.MinorUpdate else AuditSummary.Changes(entries)
}
