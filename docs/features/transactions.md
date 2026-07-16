# Transactions

## Overview
The core of the ledger. Three types — **income, expense, transfer** — with category, labels, payment method, notes, and an optional **breakdown** into sub-items (a "+" calculator whose items must sum to the parent amount). Supports **cross-currency transfers**. Can also create a **split** in a group.

## User flow
```mermaid
flowchart TD
    New([Add transaction]) --> Type{Type}
    Type -->|Income/Expense| One[Pick account]
    Type -->|Transfer| Two[From + To account\n+ cross-currency rate]
    One --> Amt[Amount + currency]
    Two --> Amt
    Amt --> Break["Optional: + breakdown items (must sum)"]
    Break --> Meta[Category, labels, method, note, date]
    Meta --> Split{Split with a group?}
    Split -->|yes| Grp[Create shared expense]
    Split -->|no| Save[Save → ledger entry]
    Grp --> Save
```

## Technical flow
```mermaid
sequenceDiagram
    actor U
    participant Form as New/Edit form
    participant Cat as Auto-categoriser (on-device)
    participant W as write.ts
    participant DB as SQLite→sync
    U->>Form: enter description/amount
    Form->>Cat: suggest category (semantic embeddings)
    Cat-->>Form: nearest category
    U->>Form: confirm
    Form->>W: insertRow('transactions', {...}) + transaction_items + labels
    W->>DB: write (sum constraint enforced in UI)
    Note over Cat: corrections feed useLearnCategory → improves future suggestions
```

## Data touched
`transactions`, `transaction_items` (breakdown, sum = parent), `transaction_labels` ↔ `labels`, `categories`, `transaction_audit` (edit history), `payment_methods` lookup, `category_rules` (learned categorisation). Transfers write paired entries and may hit `exchange_rates`.

## Key files
`app/transactions/`, `app/transactions/new`, `app/transactions/[id]/edit`, `src/ui/TransactionRow.tsx` (list + `tile` variant), `src/categorize/*` (semantic auto-categoriser + keyword fallback).

## Gating
Free (income/expense/transfer + breakdown + search). Advanced analytics on this data is premium.

## Edge cases
- Breakdown items must sum to the parent; UI blocks save otherwise.
- Cross-currency transfer records the rate so both accounts reconcile.
- Auto-categorisation runs fully **on-device** (transformers.js MiniLM); falls back to the keyword engine if the model/CDN is unavailable. Premium-gated.
- Lists render as responsive tiles (`.list-grid` + `TransactionRow tile`).
