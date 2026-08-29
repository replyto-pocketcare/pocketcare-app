import Foundation

/// What one `transaction_audit` row actually says, once the backend noise is
/// stripped out. Ported from the `AUDIT_LABELS` table and the `AuditChanges`
/// component in apps/web/app/transactions/[id]/edit/page.tsx.
///
/// Web decides three things inline in a React component: which changed fields
/// are worth showing, in what order, and how each value should be rendered.
/// Only the rendering is locale-work; the other two are logic, and putting them
/// here is what stops iOS and Android from disagreeing about whether a given
/// edit shows as a real change or as "Minor update."
///
/// The `changes` column is JSON, and neither Domain has a JSON dependency in
/// its main source set (see AssistantMarkdown's `AssistantJson` for the same
/// boundary and the same reason). So the caller parses, and this takes the
/// decoded map.
///
/// Mirrors apps/android/domain/.../transactions/AuditSummary.kt.

/// How the view should render an audit value. Web switches on the field name
/// inside `show()`; naming the cases here keeps that decision on this side of
/// the boundary while leaving the actual formatting — money, dates, the id to
/// name lookups — to the platform that has a locale and the rows.
public enum AuditValueKind: String, Equatable, Sendable {
    /// Minor units, formatted in the transaction's currency.
    case money
    /// An ISO timestamp.
    case date
    /// A `categories.id` the view resolves to a name.
    case category
    /// An `accounts.id` the view resolves to a name.
    case account
    /// A `payment_methods.id` the view resolves to a label.
    case paymentMethod
    /// A transaction type — expense/income/transfer/adjustment.
    case type
    /// Shown as-is.
    case text
}

/// One field's before/after, as the `changes` column stores it.
public struct AuditFromTo: Equatable, Sendable {
    public let from: String?
    public let to: String?

    public init(from: String?, to: String?) {
        self.from = from
        self.to = to
    }
}

/// One field's before/after, ready for the view.
public struct AuditChange: Equatable, Sendable {
    /// The column name, which is also the i18n key under `audit.`.
    public let field: String
    public let kind: AuditValueKind
    /// Nil means "absent" — the view shows its placeholder, not an empty gap.
    public let from: String?
    public let to: String?

    public init(field: String, kind: AuditValueKind, from: String?, to: String?) {
        self.field = field
        self.kind = kind
        self.from = from
        self.to = to
    }
}

/// What to draw for one audit row.
public enum AuditSummary: Equatable, Sendable {
    /// Draw nothing at all. Web's `AuditChanges` returns null both when the
    /// column is null and when it will not parse.
    ///
    /// Named `absent` rather than `none`: `.none` collides with
    /// `Optional.none` at every call site that has an optional in scope.
    case absent
    /// The row changed something, but nothing a user would recognise — an id we
    /// cannot resolve, a checksum, the soft-delete marker. Web's `minorUpdate`.
    case minorUpdate
    case changes([AuditChange])
}

/// The fields worth showing, in the order they are shown.
///
/// Web's `AUDIT_LABELS` is an object literal and it iterates `parsed`, so its
/// order is whatever order the WRITER happened to emit — which differs between
/// the three clients that write this column. The whitelist's own order is used
/// here instead, so two devices looking at the same audit row list the same
/// fields the same way. That is a deliberate divergence, and the only one in
/// this file.
public let auditFields: [String] = [
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
]

private func auditKind(of field: String) -> AuditValueKind {
    switch field {
    case "amount", "to_amount": return .money
    case "occurred_at": return .date
    case "category_id": return .category
    case "account_id", "to_account_id": return .account
    case "payment_method_id": return .paymentMethod
    case "type": return .type
    default: return .text
    }
}

/// - Parameter parsed: the decoded `changes` object, or nil when the column was
///   null or did not parse as JSON.
public func summarizeAuditChanges(_ parsed: [String: AuditFromTo]?) -> AuditSummary {
    guard let parsed else { return .absent }
    let entries: [AuditChange] = auditFields.compactMap { field in
        guard let fromTo = parsed[field] else { return nil }
        // Web's `show()` collapses null, undefined and "" to the same
        // placeholder, so an empty string is an ABSENT value here rather than a
        // value that happens to be empty.
        let from = (fromTo.from?.isEmpty ?? true) ? nil : fromTo.from
        let to = (fromTo.to?.isEmpty ?? true) ? nil : fromTo.to
        return AuditChange(field: field, kind: auditKind(of: field), from: from, to: to)
    }
    return entries.isEmpty ? .minorUpdate : .changes(entries)
}
