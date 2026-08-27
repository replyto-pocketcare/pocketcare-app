import Foundation

/**
 Statement parsing/analysis domain types.

 Ported from `apps/web/src/statements/types.ts`. Fully on-device: statements are
 parsed on the phone and never sent anywhere — the same claim web's header
 makes, and the reason none of this touches a repository.

 Amounts are integer MINOR units and a transaction's `amount` is SIGNED:
 negative = debit/spend, positive = credit/received. Dates are ISO
 `YYYY-MM-DD`.

 Mirrors Android's StatementTypes.kt.
 */

/// One printed line of a statement.
public struct StatementTxn: Equatable, Sendable {
    /// YYYY-MM-DD.
    public let date: String
    public let description: String
    /// Minor units, signed (− debit / + credit).
    public let amount: Int64
    /// Running balance (minor), when the statement prints one.
    public let balance: Int64?
    /// Filled by the on-device categoriser at review time.
    public let category: String?
    /// Cheque/UPI ref, when present.
    public let ref: String?

    public init(
        date: String,
        description: String,
        amount: Int64,
        balance: Int64? = nil,
        category: String? = nil,
        ref: String? = nil
    ) {
        self.date = date
        self.description = description
        self.amount = amount
        self.balance = balance
        self.category = category
        self.ref = ref
    }
}

/// Credit-card-only figures, read off the statement header.
public struct CardMeta: Equatable, Sendable {
    /// Statement balance / total outstanding (minor).
    public let totalDue: Int64?
    /// Minimum amount due (minor).
    public let minDue: Int64?
    /// YYYY-MM-DD.
    public let dueDate: String?
    /// Amount due this cycle (minor).
    public let thisMonthDue: Int64?

    public init(totalDue: Int64? = nil, minDue: Int64? = nil, dueDate: String? = nil, thisMonthDue: Int64? = nil) {
        self.totalDue = totalDue
        self.minDue = minDue
        self.dueDate = dueDate
        self.thisMonthDue = thisMonthDue
    }
}

/// The statement's date range. Either end can be unknown.
public struct StatementPeriod: Equatable, Sendable {
    public let from: String?
    public let to: String?
    public init(from: String? = nil, to: String? = nil) {
        self.from = from
        self.to = to
    }
}

/**
 How the columns were mapped, for the review UI and a manual override.

 Values are column INDICES as strings, which is what web stores — it keys them
 by `String(ci)` so the mapping can round-trip through JSON and through a
 `<select>` value without a second type.
 */
public struct ColumnMapping: Equatable, Sendable {
    public let date: String?
    public let description: String?
    public let debit: String?
    public let credit: String?
    /// A single signed-amount column, the alternative to debit/credit.
    public let amount: String?
    public let balance: String?

    public init(
        date: String? = nil,
        description: String? = nil,
        debit: String? = nil,
        credit: String? = nil,
        amount: String? = nil,
        balance: String? = nil
    ) {
        self.date = date
        self.description = description
        self.debit = debit
        self.credit = credit
        self.amount = amount
        self.balance = balance
    }
}

public struct ParsedStatement: Equatable, Sendable {
    /// "bank" | "card".
    public let kind: String
    /// Detected bank/card name, else a generic label.
    public let label: String
    /// ISO code (defaults to the user's base).
    public let currency: String
    public let period: StatementPeriod
    public let openingBalance: Int64?
    public let closingBalance: Int64?
    public let txns: [StatementTxn]
    public let card: CardMeta?
    /// What the parser is unsure about — surfaced to the user, not swallowed.
    public let warnings: [String]
    public let mapping: ColumnMapping?

    public init(
        kind: String,
        label: String,
        currency: String,
        period: StatementPeriod,
        openingBalance: Int64? = nil,
        closingBalance: Int64? = nil,
        txns: [StatementTxn] = [],
        card: CardMeta? = nil,
        warnings: [String] = [],
        mapping: ColumnMapping? = nil
    ) {
        self.kind = kind
        self.label = label
        self.currency = currency
        self.period = period
        self.openingBalance = openingBalance
        self.closingBalance = closingBalance
        self.txns = txns
        self.card = card
        self.warnings = warnings
        self.mapping = mapping
    }
}
