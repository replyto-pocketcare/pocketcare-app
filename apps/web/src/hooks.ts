"use client";

import { useQuery } from "@powersync/react";
import { money, type Money } from "@pocketcare/money";
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
// Base currency (default INR) + amount masking come from a reactive store.
export { useBaseCurrency } from "./prefs";

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

export type WebAccount = Account & { include_in_net_worth?: number; color?: string | null };

export interface AccountWithBalance {
  account: WebAccount;
  balance: Money;
}

/** All accounts with their ledger-derived balances (reactive). */
export function useAccountBalances(): AccountWithBalance[] {
  const { data: accounts = [] } = useQuery<WebAccount>(
    "SELECT * FROM accounts WHERE deleted_at IS NULL ORDER BY created_at",
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
