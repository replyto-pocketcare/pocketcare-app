import SwiftUI
import Domain
import Data

/// The edit-history modal from apps/web/app/transactions/[id]/edit/page.tsx.
///
/// `transaction_audit` has recorded every change to every transaction since
/// migration 0001 and neither phone had a way to read it, so "what did I
/// change, and when?" had no answer outside the browser.
///
/// Which fields are worth showing, and in what order, is decided in Domain
/// (`summarizeAuditChanges`, vector-pinned) so the two phones cannot disagree.
/// This file does only what needs a locale: naming the fields, formatting the
/// values, and resolving ids to the names the user actually chose.
struct EditHistorySheet: View {
    let entries: [TransactionAudit]
    let currency: String
    let categories: [CategoryRow]
    let accounts: [Account]
    let paymentMethods: [PaymentMethodRow]
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(S.Transactions.editHistory)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.text)
                Spacer()
                Button(S.Translation.commonClose, action: onClose).foregroundColor(.text2)
            }

            if entries.isEmpty {
                Text(S.Transactions.noEdits).font(.system(size: 13)).foregroundColor(.text2)
            } else {
                // No `ScrollView` of its own. Web caps this list at 60vh and
                // scrolls INSIDE the modal; `sanvyaModal` already puts the whole
                // card in a scroll view for exactly that case, and a second one
                // in the same axis would fight it for the gesture.
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(entries, id: \.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(auditTimestampLabel(entry.createdAt))\(auditHeaderSeparator)\(auditActionLabel(entry.action))")
                                .font(.system(size: 12))
                                .foregroundColor(.text2)
                            changes(for: entry)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func changes(for entry: TransactionAudit) -> some View {
        switch summarizeAuditChanges(parseAuditChanges(entry.changes)) {
        case .absent:
            EmptyView()
        case .minorUpdate:
            Text(S.Transactions.minorUpdate).font(.system(size: 12)).foregroundColor(.text2)
        case .changes(let list):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(list, id: \.field) { change in
                    changeLine(change)
                }
            }
        }
    }

    private func changeLine(_ change: AuditChange) -> some View {
        // Concatenated `Text`s rather than one interpolated string: the field
        // name is semibold and the OLD value is muted, which is web's
        // `<strong>` plus `.muted` on the same line.
        //
        // Every segment carries its own colour rather than relying on an outer
        // `.foregroundColor`: on a concatenated `Text` the outer one is not a
        // default, it is applied to the whole run, and it would flatten the
        // muted OLD value back to the body colour.
        let label = Text(auditFieldLabel(change.field)).fontWeight(.semibold).foregroundColor(.text)
        let separator = Text(auditLabelSeparator).foregroundColor(.text)
        let from = Text(show(change, change.from)).foregroundColor(.text2)
        let arrow = Text(auditChangeArrow).foregroundColor(.text)
        let to = Text(show(change, change.to)).foregroundColor(.text)
        return (label + separator + from + arrow + to)
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// One audit value, rendered.
    ///
    /// Mirrors web's `show()` case for case, with two deliberate differences,
    /// both of them about not shipping English:
    ///
    /// * a type renders through the translated `type.*` key, not
    ///   `s.charAt(0).toUpperCase()`;
    /// * a date renders in the device locale rather than the browser's.
    private func show(_ change: AuditChange, _ raw: String?) -> String {
        guard let raw else { return auditAbsentValue }
        switch change.kind {
        // Mask-aware, unlike web's bare `format(...)`. This is a DISPLAY
        // amount, not a field being typed into, and an unmasked amount on a
        // screen the user opened with hide-amounts on is the privacy-leak class
        // PARITY_AUDIT calls trap 7.
        case .money:
            guard let minor = Int64(raw) else { return raw }
            return formatMoneyAware(money(minor, currency))
        case .date:
            return auditTimestampLabel(raw)
        case .category:
            return categories.first { $0.id == raw }?.name ?? auditAbsentValue
        case .account:
            return accounts.first { $0.id == raw }?.name ?? auditAbsentValue
        case .paymentMethod:
            return paymentMethods.first { $0.id == raw }?.label ?? raw
        case .type:
            return auditTypeLabel(raw)
        case .text:
            return raw
        }
    }
}

/// The translated name of an audited column — web's `t(`audit.${field}`)`.
private func auditFieldLabel(_ field: String) -> String {
    switch field {
    case "amount": return S.Transactions.auditAmount
    case "to_amount": return S.Transactions.auditToAmount
    case "description": return S.Transactions.auditDescription
    case "merchant": return S.Transactions.auditMerchant
    case "note": return S.Transactions.auditNote
    case "occurred_at": return S.Transactions.auditOccurredAt
    case "type": return S.Transactions.auditType
    case "category_id": return S.Transactions.auditCategoryId
    case "account_id": return S.Transactions.auditAccountId
    case "to_account_id": return S.Transactions.auditToAccountId
    case "payment_method_id": return S.Transactions.auditPaymentMethodId
    // Unreachable while Domain's whitelist and these cases agree; the raw
    // column name is a better failure than a wrong label if they ever drift.
    default: return field
    }
}

/// The translated name of a transaction type — web's `t(`type.${tp}`)`.
private func auditTypeLabel(_ type: String) -> String {
    switch type {
    case "income": return S.Transactions.typeIncome
    case "transfer": return S.Transactions.typeTransfer
    default: return S.Transactions.typeExpense
    }
}

/// "Updated" / "Deleted" — the two actions the write path records.
///
/// Web prints the raw column ("update"), which is a lowercase English verb on
/// every screen in every language. An action nothing recognises falls back to
/// the raw value rather than being hidden, so a new one added later is visible
/// instead of silently blank.
private func auditActionLabel(_ action: String) -> String {
    switch action {
    case "update": return S.Transactions.auditActionUpdate
    case "delete": return S.Transactions.auditActionDelete
    default: return action
    }
}

/// Date AND time, in the device locale — web's `toLocaleString()`.
///
/// `DateLabels.swift`'s helpers are date-only, and this is the one place in the
/// app that needs both halves; a fourth entry there for a single caller would be
/// a shared helper nothing shares. An unparseable timestamp renders as itself
/// rather than as a wrong date.
private func auditTimestampLabel(_ iso: String) -> String {
    guard let date = parseOccurredAt(iso) else { return iso }
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

/// The `changes` column, decoded into what Domain's `summarizeAuditChanges`
/// takes. Nil when the column is null or is not a JSON object — web's
/// `try { JSON.parse } catch { return null }`.
private func parseAuditChanges(_ changes: String?) -> [String: AuditFromTo]? {
    guard let changes, !changes.isEmpty, let data = changes.data(using: .utf8) else { return nil }
    // Two steps on purpose: `try? x as? T` is the shape that makes readers
    // (and older compilers) argue about whether the result is doubly optional.
    guard let parsed = try? JSONSerialization.jsonObject(with: data),
          let root = parsed as? [String: Any] else { return nil }
    var out: [String: AuditFromTo] = [:]
    for (field, value) in root {
        guard let entry = value as? [String: Any] else { continue }
        out[field] = AuditFromTo(from: entry["from"] as? String, to: entry["to"] as? String)
    }
    return out
}

/// The three punctuation marks this sheet joins with.
///
/// Glyphs, not copy: the middot between a timestamp and its action, the colon
/// after a field name and the arrow between two values are the same marks in
/// every language, so they stay out of the string files rather than being
/// duplicated into three of them.
private let auditHeaderSeparator = " · "
private let auditLabelSeparator = ": "
private let auditChangeArrow = " → "

/// Web's `"—"` for a value that was absent on one side of the change.
private let auditAbsentValue = "—"
