import Foundation

/// CSV import adapters, ported from apps/web/src/data/adapters.ts.
///
/// Mirrors apps/android/domain/.../csv/ImportAdapters.kt.

/// Canonical transaction shape all importers produce and the exporter emits.
public struct CanonRow: Equatable, Sendable {
    /// ISO date/datetime for `occurred_at`.
    public let date: String
    /// income | expense | transfer | opening_balance | adjustment
    public let type: String
    /// MAJOR units. Positive except for the signed types — see `isSignedType`.
    public let amount: Double
    public let currency: String
    /// From-account NAME, not id: a CSV has no ids.
    public let account: String
    public let toAccount: String?
    public let toAmount: Double?
    public let category: String?
    public let labels: [String]
    /// Display label, e.g. "UPI".
    public let paymentMethod: String?
    public let note: String?
    public let description: String?

    public init(
        date: String, type: String, amount: Double, currency: String, account: String,
        toAccount: String? = nil, toAmount: Double? = nil, category: String? = nil,
        labels: [String] = [], paymentMethod: String? = nil, note: String? = nil,
        description: String? = nil
    ) {
        self.date = date
        self.type = type
        self.amount = amount
        self.currency = currency
        self.account = account
        self.toAccount = toAccount
        self.toAmount = toAmount
        self.category = category
        self.labels = labels
        self.paymentMethod = paymentMethod
        self.note = note
        self.description = description
    }
}

public struct ImportAdapter: Equatable, Sendable, Identifiable {
    public let id: String
    public let label: String
    public let beta: Bool
    /// Delimiter hint; nil means auto-detect.
    public let delimiter: String?
}

/// Tolerates thousands separators and currency symbols; keeps sign and decimal.
///
/// The comma rule is web's and is worth reading twice: a value with commas and
/// NO dot treats the last comma as a decimal point ("1.234,56" is European),
/// and anything else strips commas as thousands separators.
func parseAmount(_ v: String?) -> Double {
    guard let v, !v.isEmpty else { return 0 }
    var cleaned = v.replacingOccurrences(of: "[^0-9.,\\-]", with: "", options: .regularExpression)
    cleaned = cleaned.replacingOccurrences(of: ",(?=\\d{3}\\b)", with: "", options: .regularExpression)
    let norm: String
    if cleaned.contains(",") && !cleaned.contains(".") {
        if let range = cleaned.range(of: ",") {
            norm = cleaned.replacingCharacters(in: range, with: ".")
        } else {
            norm = cleaned
        }
    } else {
        norm = cleaned.replacingOccurrences(of: ",", with: "")
    }
    guard let n = jsParseFloat(norm), n.isFinite else { return 0 }
    return n
}

func splitLabels(_ v: String?) -> [String] {
    (v ?? "")
        .components(separatedBy: CharacterSet(charactersIn: "|,"))
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

/// Web's `toType`: read the words, then fall back to the sign.
func toType(_ t: String, _ amount: Double) -> String {
    let s = t.lowercased()
    if s.contains("transfer") { return "transfer" }
    if s.contains("income") || s.contains("deposit") || s.contains("credit") { return "income" }
    if s.contains("opening") { return "opening_balance" }
    if s.contains("adjust") { return "adjustment" }
    if s.contains("expens") || s.contains("debit") || s.contains("withdraw") { return "expense" }
    return amount < 0 ? "expense" : "income"
}

/// `adjustment` and `opening_balance` carry a SIGNED amount — the ledger adds
/// it as-is. `income`, `expense` and `transfer` are always positive, because the
/// type is what gives them their sign.
func isSignedType(_ t: String) -> Bool { t == "adjustment" || t == "opening_balance" }

/// Wallet's human payment labels → PocketCare payment-method labels.
private let walletPayment: [String: String] = [
    "mobile payment": "UPI",
    "bank transfer": "Net Banking",
    "web payment": "Net Banking",
    "cash": "Cash",
    "credit card": "Credit Card",
    "debit card": "Debit Card",
]

private let knownTypes: Set<String> = ["income", "expense", "transfer", "opening_balance", "adjustment"]

public let importAdapters: [ImportAdapter] = [
    ImportAdapter(id: "pocketcare", label: "PocketCare (CSV export)", beta: false, delimiter: nil),
    ImportAdapter(id: "wallet", label: "Wallet by BudgetBakers (beta)", beta: true, delimiter: ";"),
]

/// Column order for PocketCare's own export (matches the pocketcare adapter).
public let exportHeaders = [
    "Date", "Type", "Amount", "Currency", "Account", "To Account", "To Amount",
    "Category", "Labels", "Payment Method", "Note", "Description",
]

/// Parses `text` with the named adapter, falling back to PocketCare's own
/// format for an unknown id — which is web's behaviour.
///
/// `nowIso` stands in for web's `new Date().toISOString()` default for a row
/// with no date. A parameter, not a clock read: nothing in Domain reads a
/// clock, and it is what makes this vector-testable.
public func parseWithAdapter(_ adapterId: String, _ text: String, nowIso: String) -> [CanonRow] {
    let adapter = importAdapters.first { $0.id == adapterId } ?? importAdapters[0]
    let records = parseRecords(text, delimiter: adapter.delimiter)
    let rows = adapter.id == "wallet"
        ? parseWallet(records, nowIso)
        : parsePocketCare(records, nowIso)
    return rows.filter { !$0.account.isEmpty && $0.amount != 0 }
}

/// `nil` for an absent OR empty cell — web tests `r["x"] || undefined`, and an
/// empty string is falsy there.
private func blankAsNil(_ v: String?) -> String? {
    guard let v, !v.isEmpty else { return nil }
    return v
}

private func parsePocketCare(_ records: [CsvRecord], _ nowIso: String) -> [CanonRow] {
    records.map { r in
        let raw = parseAmount(r["amount"])
        let t0 = (r["type"] ?? "").lowercased()
        let type = knownTypes.contains(t0) ? t0 : toType(r["type"] ?? "", raw)
        let toAmountRaw = blankAsNil(r["to amount"]) ?? blankAsNil(r["to_amount"])
        return CanonRow(
            date: blankAsNil(r["date"]) ?? nowIso,
            type: type,
            amount: isSignedType(type) ? raw : abs(raw),
            currency: (r["currency"] ?? "").uppercased(),
            account: r["account"] ?? "",
            toAccount: blankAsNil(r["to account"]) ?? blankAsNil(r["to_account"]),
            toAmount: toAmountRaw.map { abs(parseAmount($0)) },
            category: blankAsNil(r["category"]),
            labels: splitLabels(r["labels"]),
            paymentMethod: blankAsNil(r["payment method"]) ?? blankAsNil(r["payment_method"]),
            note: blankAsNil(r["note"]),
            description: blankAsNil(r["description"])
        )
    }
}

private func parseWallet(_ records: [CsvRecord], _ nowIso: String) -> [CanonRow] {
    records.map { r in
        let rawAmount = parseAmount(r["amount"])
        // Wallet splits a transfer into two one-sided rows (− on source, + on
        // destination) with no link between them. Each is imported as a signed
        // `adjustment` so both balances come out right without polluting the
        // income/expense statistics.
        let isTransfer = r["transfer"] == "true"
        let type = isTransfer ? "adjustment" : toType(r["type"] ?? "", rawAmount)
        let payLocal = (r["payment_type_local"] ?? "").lowercased()
        return CanonRow(
            date: blankAsNil(r["date"]) ?? nowIso,
            type: type,
            amount: isTransfer ? rawAmount : abs(rawAmount),
            currency: (r["currency"] ?? "").uppercased(),
            account: r["account"] ?? "",
            toAccount: nil,
            toAmount: nil,
            category: isTransfer ? nil : blankAsNil(r["category"]),
            labels: splitLabels(r["labels"]),
            paymentMethod: isTransfer ? nil : (walletPayment[payLocal] ?? blankAsNil(r["payment_type_local"])),
            note: isTransfer
                ? (blankAsNil(r["note"]) ?? "Transfer")
                : (blankAsNil(r["note"]) ?? blankAsNil(r["payee"]))
        )
    }
}
