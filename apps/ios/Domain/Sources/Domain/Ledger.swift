import Foundation

// Ported from packages/core/ledger/src/index.ts (P1.2b). Mirrors
// apps/android/domain/.../ledger/Ledger.kt (P1.2a) field-for-field.
//
// Balances are NEVER stored as a mutable number; they are always
// computed by summing the signed effects of transactions (golden rule
// #2). Account balances stay within a single currency (no conversion).
// Cross-currency only matters at net-worth aggregation, where cached FX
// rates are applied.

/// Minimal transaction shape the ledger needs (a subset of the full row).
public struct LedgerEntry: Sendable {
    public let type: String
    public let accountId: String
    public let amount: Int64
    public let toAccountId: String?
    public let toAmount: Int64?

    public init(type: String, accountId: String, amount: Int64, toAccountId: String? = nil, toAmount: Int64? = nil) {
        self.type = type
        self.accountId = accountId
        self.amount = amount
        self.toAccountId = toAccountId
        self.toAmount = toAmount
    }
}

/// Signed effect (minor units, in the account's own currency) of one
/// entry on a given account. Returns 0 if the entry doesn't touch that
/// account.
///   income / opening_balance / adjustment: +amount on accountId
///   expense: -amount on accountId
///   transfer: -amount on source, +toAmount (or amount) on destination
public func signedEffectFor(_ entry: LedgerEntry, _ accountId: String) -> Int64 {
    switch entry.type {
    case "income", "opening_balance", "adjustment":
        return entry.accountId == accountId ? entry.amount : 0
    case "expense":
        return entry.accountId == accountId ? -entry.amount : 0
    case "transfer":
        if entry.accountId == accountId { return -entry.amount }
        if entry.toAccountId == accountId { return entry.toAmount ?? entry.amount }
        return 0
    default:
        return 0
    }
}

/// Ledger-derived balance of an account (sum of signed effects).
public func deriveBalance(_ accountId: String, _ currency: String, _ entries: [LedgerEntry]) -> Money {
    let total = entries.reduce(Int64(0)) { $0 + signedEffectFor($1, accountId) }
    return money(total, currency)
}

/// Available balance = total minus amounts blocked toward goals (feature #9).
public func availableBalance(_ total: Money, _ blocked: Money) throws -> Money {
    try subtract(total, blocked)
}

/// A per-account balance plus how much of it is blocked toward goals.
public struct AccountBalance: Sendable {
    public let balance: Money
    public let blocked: Money
    public init(balance: Money, blocked: Money) {
        self.balance = balance
        self.blocked = blocked
    }
}

/// Resolves an FX rate between two currency codes.
///
/// `@Sendable`, unlike Kotlin's plain `typealias RateLookup` — Swift 6 needs it
/// and Kotlin has no equivalent to need. Every lookup this codebase builds
/// closes over an immutable `[String: Double]` table and nothing else, so the
/// annotation records a property these closures already have rather than
/// imposing a new one. Without it a rate lookup cannot cross an `AsyncStream`
/// combinator, which is where CI run 32940348246 found it.
public typealias RateLookup = @Sendable (String, String) -> Double

/// Aggregate net worth in the base currency (feature #13).
/// - includeBlocked: when false, blocked amounts are excluded (available view, #9)
/// - getRate: resolves an FX rate (same currency should return 1)
public func aggregateNetWorth(
    _ balances: [AccountBalance],
    base: String,
    getRate: RateLookup,
    includeBlocked: Bool
) throws -> Money {
    // Int64(0), not the bare literal 0 -- see Money.swift's sum() comment
    // for why an untyped literal here is ambiguous between money's two
    // overloads.
    var total = money(Int64(0), base)
    for b in balances {
        let effective: Money
        if includeBlocked {
            effective = b.balance
        } else {
            effective = try availableBalance(b.balance, b.blocked)
        }
        let rate = effective.currency == base ? 1.0 : getRate(effective.currency, base)
        total = try add(total, convert(effective, to: base, rate: rate))
    }
    return total
}
