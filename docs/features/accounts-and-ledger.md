# Accounts & Ledger

## Overview
Users hold multiple **accounts** (6 types: cash, bank, credit card, wallet, stocks, mutual funds), each in its own currency. **Balances are derived from an append-only ledger**, never stored directly. Opening balances and corrections are themselves ledger entries (`opening_balance` / `adjustment`).

## User flow
```mermaid
flowchart TD
    A([Accounts]) --> List[List accounts + balances]
    List --> New[+ New account]
    New --> Form[name, type, currency, color, net-worth toggle]
    Form --> Open[Set opening balance → opening_balance entry]
    List --> Detail[Open account]
    Detail --> Edit[Edit / archive / adjust balance]
    Edit --> Adj[adjustment entry created]
```

## Technical flow — balance derivation
```mermaid
flowchart LR
    Entries["transactions rows\n(income/expense/transfer/opening/adjustment)"] --> D["deriveBalance()\n@pocketcare/ledger"]
    D --> Total["total balance"]
    Alloc["goal_allocations (blocked)"] --> Avail["available = total − blocked"]
    Total --> Avail
    Total --> NW["aggregateNetWorth()\n(FX via exchange_rates → base ccy)"]
```

## Data touched
`accounts`, `transactions` (all entry types), `goal_allocations` (blocked amounts), `credit_card_details`, `exchange_rates` (net-worth conversion), `account_types` lookup.

## Key files
`app/accounts/`, `app/accounts/new`, `app/accounts/[id]`, `src/hooks.ts` (`useAccountBalances`, `useNetWorth`), `@pocketcare/ledger` (`deriveBalance`, `aggregateNetWorth`).

## Gating
Free (core ledger). Net-worth roll-up and per-account inclusion toggle are free.

## Edge cases
- **Available vs total:** goals block funds from savings (except emergency fund); toggle shows with/without blocked.
- **Multi-currency:** each account keeps its currency; net worth converts at display time to the base currency.
- Deleting an account can cascade its transactions or keep them (see `app/accounts/[id]/edit`).
- Archived accounts are hidden from pickers but retained for history.
