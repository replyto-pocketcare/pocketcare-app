package com.sanvya.app.domain.ledger

import com.sanvya.app.domain.money.Money
import com.sanvya.app.domain.money.add
import com.sanvya.app.domain.money.convert
import com.sanvya.app.domain.money.money
import com.sanvya.app.domain.money.subtract

// Ported from packages/core/ledger/src/index.ts (P1.2a). Correctness is
// judged against tools/golden-vectors/vectors/ledger.json, not against a
// fresh reading of the TS -- see docs/plans/native-mobile-apps.md
// section 5 and CLAUDE.md golden rule 8 ("web is the spec").
//
// Balances are NEVER stored as a mutable number; they are always
// computed by summing the signed effects of transactions (golden rule
// #2). Account balances stay within a single currency (no conversion).
// Cross-currency only matters at net-worth aggregation, where cached FX
// rates are applied.

/** Minimal transaction shape the ledger needs (a subset of the full row). */
data class LedgerEntry(
    val type: String,
    val accountId: String,
    val amount: Long,
    val toAccountId: String? = null,
    val toAmount: Long? = null,
)

/**
 * Signed effect (minor units, in the account's own currency) of one
 * entry on a given account. Returns 0 if the entry doesn't touch that
 * account.
 *   income / opening_balance / adjustment: +amount on accountId
 *   expense: -amount on accountId
 *   transfer: -amount on source, +toAmount (or amount) on destination
 */
fun signedEffectFor(entry: LedgerEntry, accountId: String): Long {
    return when (entry.type) {
        "income", "opening_balance", "adjustment" -> if (entry.accountId == accountId) entry.amount else 0L
        "expense" -> if (entry.accountId == accountId) -entry.amount else 0L
        "transfer" -> when {
            entry.accountId == accountId -> -entry.amount
            entry.toAccountId == accountId -> entry.toAmount ?: entry.amount
            else -> 0L
        }
        else -> 0L
    }
}

/** Ledger-derived balance of an account (sum of signed effects). */
fun deriveBalance(accountId: String, currency: String, entries: List<LedgerEntry>): Money {
    val total = entries.fold(0L) { acc, e -> acc + signedEffectFor(e, accountId) }
    return money(total, currency)
}

/** Available balance = total minus amounts blocked toward goals (feature #9). */
fun availableBalance(total: Money, blocked: Money): Money = subtract(total, blocked)

/** A per-account balance plus how much of it is blocked toward goals. */
data class AccountBalance(val balance: Money, val blocked: Money)

typealias RateLookup = (String, String) -> Double

/**
 * Aggregate net worth in the base currency (feature #13).
 * @param includeBlocked when false, blocked amounts are excluded (available view, #9)
 * @param getRate resolves an FX rate (same currency should return 1)
 */
fun aggregateNetWorth(
    balances: List<AccountBalance>,
    base: String,
    getRate: RateLookup,
    includeBlocked: Boolean,
): Money {
    var total = money(0L, base)
    for (b in balances) {
        val effective = if (includeBlocked) b.balance else availableBalance(b.balance, b.blocked)
        val rate = if (effective.currency == base) 1.0 else getRate(effective.currency, base)
        total = add(total, convert(effective, base, rate))
    }
    return total
}
