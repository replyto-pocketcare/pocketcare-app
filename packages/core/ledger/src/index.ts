/**
 * @pocketcare/ledger — derive balances from the append-only ledger.
 *
 * Balances are NEVER stored as a mutable number; they are always computed by
 * summing the signed effects of transactions (invariant #2). Account balances
 * stay within a single currency (no conversion). Cross-currency only matters at
 * net-worth aggregation, where cached FX rates are applied.
 */
import type { CurrencyCode, TransactionType } from "@pocketcare/types";
import { money, add, subtract, convert, type Money } from "@pocketcare/money";

/** Minimal transaction shape the ledger needs (a subset of the full row). */
export interface LedgerEntry {
  type: TransactionType;
  account_id: string;
  amount: number;
  to_account_id?: string | null;
  to_amount?: number | null;
}

/**
 * Signed effect (minor units, in the account's own currency) of one entry on a
 * given account. Returns 0 if the entry doesn't touch that account.
 *   income / opening_balance / adjustment: +amount on account_id
 *   expense: -amount on account_id
 *   transfer: -amount on source, +to_amount (or amount) on destination
 */
export function signedEffectFor(entry: LedgerEntry, accountId: string): number {
  switch (entry.type) {
    case "income":
    case "opening_balance":
    case "adjustment":
      return entry.account_id === accountId ? entry.amount : 0;
    case "expense":
      return entry.account_id === accountId ? -entry.amount : 0;
    case "transfer": {
      if (entry.account_id === accountId) return -entry.amount;
      if (entry.to_account_id === accountId) {
        return entry.to_amount ?? entry.amount;
      }
      return 0;
    }
    default:
      return 0;
  }
}

/** Ledger-derived balance of an account (sum of signed effects). */
export function deriveBalance(
  accountId: string,
  currency: CurrencyCode,
  entries: readonly LedgerEntry[],
): Money {
  const total = entries.reduce((acc, e) => acc + signedEffectFor(e, accountId), 0);
  return money(total, currency);
}

/** Available balance = total minus amounts blocked toward goals (feature #9). */
export function availableBalance(total: Money, blocked: Money): Money {
  return subtract(total, blocked);
}

/** A per-account balance plus how much of it is blocked toward goals. */
export interface AccountBalance {
  balance: Money;
  blocked: Money;
}

export type RateLookup = (from: CurrencyCode, to: CurrencyCode) => number;

/**
 * Aggregate net worth in the base currency (feature #13).
 * @param includeBlocked when false, blocked amounts are excluded (available view, #9)
 * @param getRate resolves an FX rate (same currency should return 1)
 */
export function aggregateNetWorth(
  balances: readonly AccountBalance[],
  base: CurrencyCode,
  getRate: RateLookup,
  includeBlocked: boolean,
): Money {
  let total = money(0, base);
  for (const b of balances) {
    const effective = includeBlocked ? b.balance : availableBalance(b.balance, b.blocked);
    const rate = effective.currency === base ? 1 : getRate(effective.currency, base);
    total = add(total, convert(effective, base, rate));
  }
  return total;
}
