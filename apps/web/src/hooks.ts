"use client";

import { useQuery } from "@powersync/react";
import { money, convert, type Money } from "@pocketcare/money";
import {
  deriveBalance,
  aggregateNetWorth,
  type LedgerEntry,
  type AccountBalance,
  type RateLookup,
} from "@pocketcare/ledger";
import type { Account, ExchangeRate } from "@pocketcare/types";

// Entitlement tier comes from a local reactive store (see src/tier.ts).
export { useTier } from "./tier";
// Base currency (default INR) comes from a reactive store. Import locally (so
// hooks in this file can call it) AND re-export for consumers.
import { useBaseCurrency } from "./prefs";
export { useBaseCurrency };

/** A rate lookup backed by the synced exchange_rates table (latest per pair). */
export function useRates(): RateLookup {
  const { data: rates = [] } = useQuery<ExchangeRate>(
    "SELECT base_currency, quote_currency, rate, as_of FROM exchange_rates ORDER BY as_of DESC",
  );
  const map = new Map<string, number>();
  for (const r of rates) {
    const key = `${r.base_currency}->${r.quote_currency}`;
    if (!map.has(key)) map.set(key, r.rate); // first = latest (ordered desc)
  }
  return (from, to) => {
    if (from === to) return 1;
    const direct = map.get(`${from}->${to}`);
    if (direct) return direct;
    const inverse = map.get(`${to}->${from}`);
    if (inverse) return 1 / inverse;
    return 1; // fallback: treat as par if no rate known yet
  };
}

/** True until the accounts table has returned its first result. Use to show a
 *  skeleton instead of a misleading "create your first account" flash. */
export function useAccountsLoading(): boolean {
  const { isLoading } = useQuery("SELECT id FROM accounts WHERE deleted_at IS NULL LIMIT 1");
  return isLoading;
}

export type WebAccount = Account & { include_in_net_worth?: number; color?: string | null };

export interface AccountWithBalance {
  account: WebAccount;
  balance: Money;
}

/** All accounts with their ledger-derived balances (reactive).
 *  Archived accounts are excluded unless `includeArchived` is true. */
export function useAccountBalances(includeArchived = false): AccountWithBalance[] {
  // Virtual split accounts (receivable/payable) are hidden from the account UI.
  const where = includeArchived
    ? "deleted_at IS NULL AND IFNULL(kind,'real') = 'real'"
    : "deleted_at IS NULL AND IFNULL(is_archived, 0) = 0 AND IFNULL(kind,'real') = 'real'";
  const { data: accounts = [] } = useQuery<WebAccount>(
    `SELECT * FROM accounts WHERE ${where} ORDER BY created_at`,
  );
  const { data: entries = [] } = useQuery<LedgerEntry & { account_id: string }>(
    "SELECT type, account_id, amount, to_account_id, to_amount FROM transactions WHERE deleted_at IS NULL",
  );
  return accounts.map((account) => ({
    account,
    balance: deriveBalance(account.id, account.currency, entries),
  }));
}

/** Blocked amounts per account (goal allocations, EXCLUDING the emergency fund
 *  which stays liquid — feature #8). */
function useBlockedByAccount(): Map<string, number> {
  const { data: allocs = [] } = useQuery<{ source_account_id: string; amount_blocked: number }>(
    `SELECT source_account_id, amount_blocked FROM goal_allocations
     WHERE deleted_at IS NULL
       AND goal_id NOT IN (SELECT id FROM goals WHERE is_emergency_fund = 1 AND deleted_at IS NULL)`,
  );
  const m = new Map<string, number>();
  for (const a of allocs) m.set(a.source_account_id, (m.get(a.source_account_id) ?? 0) + a.amount_blocked);
  return m;
}

/** Net worth in the base currency, with and without blocked amounts. */
export function useNetWorth(): { total: Money; available: Money; base: string } {
  const base = useBaseCurrency();
  const rates = useRates();
  const balances = useAccountBalances();
  const blocked = useBlockedByAccount();

  const accountBalances: AccountBalance[] = balances
    // Respect per-account inclusion; treat missing flag (older rows) as included.
    .filter(({ account }) => account.include_in_net_worth !== 0)
    .map(({ account, balance }) => ({
      balance,
      blocked: money(blocked.get(account.id) ?? 0, account.currency),
    }));

  return {
    total: aggregateNetWorth(accountBalances, base, rates, true),
    available: aggregateNetWorth(accountBalances, base, rates, false),
    base,
  };
}

/**
 * Convert a Money into the user's base currency using live exchange rates.
 * Accounts keep their own currency; anywhere we aggregate or show a base-currency
 * figure (net worth, subscriptions, planned cashflow, dashboard) we convert here.
 * Falls back to par (1:1) when a rate pair isn't known yet.
 */
export function useConvert(): (m: Money) => Money {
  const base = useBaseCurrency();
  const rates = useRates();
  return (m: Money): Money => {
    if (!m || m.currency === base) return m;
    const rate = rates(m.currency, base);
    return convert(m, base, rate);
  };
}

/** Convenience: convert a raw minor-unit amount from `currency` → base minor units. */
export function useConvertAmount(): (amount: number, currency: string) => number {
  const base = useBaseCurrency();
  const conv = useConvert();
  return (amount: number, currency: string) => (currency === base ? amount : conv(money(amount, currency)).amount);
}

export interface CurrencySlice { currency: string; native: number; base: number }

/**
 * Net worth split by the currency each account is held in — powers the
 * multi-currency insight. `native` is the total in that currency; `base` is the
 * converted value in the user's base currency.
 */
export function useCurrencyBreakdown(): { base: string; slices: CurrencySlice[]; total: number } {
  const base = useBaseCurrency();
  const rates = useRates();
  const balances = useAccountBalances();
  const byCcy = new Map<string, number>();
  for (const { account, balance } of balances) {
    if (account.include_in_net_worth === 0) continue;
    byCcy.set(balance.currency, (byCcy.get(balance.currency) ?? 0) + balance.amount);
  }
  const slices: CurrencySlice[] = [...byCcy.entries()]
    .map(([currency, native]) => ({
      currency,
      native,
      base: currency === base ? native : convert(money(native, currency), base, rates(currency, base)).amount,
    }))
    .sort((a, b) => Math.abs(b.base) - Math.abs(a.base));
  const total = slices.reduce((s, x) => s + x.base, 0);
  return { base, slices, total };
}
