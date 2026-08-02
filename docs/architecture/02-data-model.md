# 02 — Data Model

All persistent state lives in the **`sanvya`** Postgres schema (mirrored locally as WASM SQLite via the PowerSync `AppSchema` in `packages/db/src/index.ts`). Money columns are **integer minor units**. Every owner-scoped table has `user_id`, `created_at`, `updated_at`, `deleted_at` (soft delete) and is protected by RLS (`user_id = auth.uid()`).

## Entity relationships (core financial ledger)

```mermaid
erDiagram
    profiles ||--o{ accounts : owns
    profiles ||--o{ transactions : owns
    profiles ||--o{ categories : owns
    profiles ||--o{ labels : owns
    profiles ||--|| entitlements : has

    accounts ||--o{ transactions : "source/dest"
    accounts ||--o| credit_card_details : "may have"
    accounts {
        uuid id PK
        uuid user_id FK
        text name
        text type "FK account_types"
        text currency
        int  include_in_net_worth
        text color
    }

    transactions ||--o{ transaction_items : "breaks down into"
    transactions ||--o{ transaction_labels : "tagged by"
    transactions }o--|| categories : "categorised as"
    transactions ||--o{ transaction_audit : "audited by"
    transactions {
        uuid id PK
        uuid user_id FK
        text type "income|expense|transfer|opening_balance|adjustment"
        int  amount "minor units"
        text currency
        uuid account_id FK
        uuid to_account_id FK "transfers"
        uuid category_id FK
        timestamptz occurred_at
    }

    transaction_labels }o--|| labels : references
    transaction_items {
        uuid id PK
        uuid transaction_id FK
        text label
        int  amount "sum = parent amount"
    }

    budgets ||--o{ budget_categories : scopes
    budgets ||--o{ budget_labels : scopes
    budget_categories }o--|| categories : on
    budget_labels }o--|| labels : on

    goals ||--o{ goal_allocations : "funded by"
    goals {
        uuid id PK
        uuid user_id FK
        int  target_amount
        int  is_emergency_fund
        int  priority
    }
```

## Entity relationships (planning, growth, recurring)

```mermaid
erDiagram
    profiles ||--o{ subscriptions : owns
    profiles ||--o{ loans : owns
    profiles ||--o{ recurring_commitments : owns
    profiles ||--o{ planned_cashflow : owns
    profiles ||--o{ holdings : owns
    profiles ||--o{ transaction_templates : owns
    transaction_templates ||--o{ recurring_rules : "scheduled by"

    planned_cashflow {
        uuid id PK
        uuid user_id FK
        text direction "income|payment|saving"
        text bucket "salary|household|fd|…"
        int  amount
        text frequency "daily|weekly|monthly|yearly"
        text timeframe "monthly|quarterly|yearly"
        int  expected_return "annual % x100 (savings)"
    }
    subscriptions {
        uuid id PK
        int  amount
        text billing_cycle
        date next_renewal
    }
    loans {
        uuid id PK
        text lender
        int  principal
        int  emi_amount
        real interest_rate
        int  tenure_months
        text start_date
        int  emi_due_day
        int  auto_mark_paid
        text rate_type
        text emi_payments
        text emi_amounts
    }
    holdings {
        uuid id PK
        text symbol
        text exchange
        real quantity
        int  avg_cost
        text asset_class
        int  current_value
        real annual_rate
        text maturity_date
        text source_account_id
        text planned_id
        int  auto_fetch
    }
    holdings }o--o| market_overview : "priced by (symbol)"
```

> **Note:** subscriptions and loan EMIs are surfaced inside the **Planned Cashflow** hub, but keep their own tables (`subscriptions`, `loans`). `planned_cashflow` stores named incomes, household payments, and savings plans. See [features/planned-cashflow](../features/planned-cashflow.md).

## Entity relationships (multi-user splits ledger)

The shared ledger is the one place data is **not** strictly single-owner — rows are visible by group membership via a dedicated sync stream.

```mermaid
erDiagram
    split_groups ||--o{ split_group_members : has
    split_groups ||--o{ expenses : contains
    split_groups ||--o{ settlements : contains
    split_groups ||--o{ split_invitations : invites
    expenses ||--o{ expense_participants : "split among"
    expenses ||--o{ expense_items : "itemized into"
    expense_items ||--o{ expense_item_shares : "shared by"
    profiles ||--o{ receipt_scans : "scanned"
    profiles ||--o| payment_handles : "pays via"
    profiles ||--o{ payment_handle_disclosures : "audits"
    profiles ||--o{ split_group_members : "member of"
    profiles ||--o{ connections : "connected to"
    profiles ||--o{ expense_postings : "private projection"

    split_groups {
        uuid id PK
        uuid created_by FK "auth.users"
        text kind "group|trip"
        int  is_direct
    }
    expense_participants {
        uuid id PK
        uuid expense_id FK
        uuid user_id FK "auth.users (NO cascade)"
        int  paid_amount
        int  share_amount
    }
    settlements {
        uuid id PK
        uuid from_user FK
        uuid to_user FK
        int  amount
    }
    expense_items {
        uuid id PK
        uuid expense_id FK
        text kind "item|tax|service_charge|tip|discount"
        int  quantity "MILLI-units (1000 = 1)"
        int  unit_price
        int  amount "minor units; negative for discount"
        text split_mode "equal|quantity|percent|exact|proportional"
    }
    expense_item_shares {
        uuid id PK
        uuid item_id FK
        uuid user_id FK "auth.users (CASCADE)"
        int  weight "mode-dependent input"
        int  share_amount "resolved minor units"
    }
    payment_handles {
        uuid id PK
        uuid user_id FK
        text handle_enc "ENCRYPTED VPA - server-only, never synced"
        text handle_hint "masked, e.g. akh****@okhdfcbank"
        text verified_at "reserved - we do NOT verify ownership"
    }
    settlements_status {
        text status "confirmed|pending|disputed"
        text upi_ref "our tr= reference"
    }
    receipt_scans {
        uuid id PK
        uuid user_id FK
        text engine "tesseract|claude|pdf_text|manual"
        text parsed_json "the ReceiptDraft"
        int  confidence
        text image_path "ALWAYS NULL - no images stored"
    }
```

> **Itemized bills (0040).** `expense_items` / `expense_item_shares` are a **breakdown, not a second balance model**: per-item shares are rolled up by the client into `expense_participants`, which stays the single source of truth for every balance and settle-up query. `expenses.has_items` flags that a breakdown exists. `Σ expense_items.amount = expenses.amount` is enforced **on the client**, not by a DB constraint — a cross-row sum can't be checked synchronously when PowerSync uploads rows incrementally across separate transactions (0042 removed the trigger 0040 shipped). Use `sanvya.audit_expense_item_sums()` to observe drift.
>
> **Payment handles (0041) are server-only.** `payment_handles` is deliberately absent from `sync-streams.yaml` and from `AppSchema` — a UPI ID must never be copied onto co-members' devices. It is released just-in-time by the `payment-handle` edge function. Only `payment_handle_disclosures` (the owner's audit trail, which holds no secret) syncs. `settlements.status` defaults to `confirmed` so every pre-existing row keeps its meaning; **every settlements query must filter `status <> 'disputed'`**.
>
> **`receipt_scans` holds no image bytes.** `image_path` is a forward-compatible seam for a possible future private Storage bucket and is always written as NULL. See [receipt-scanning](../features/receipt-scanning.md).

> ⚠️ **Deletion caveat:** `split_groups.created_by`, `expenses.created_by`, `expense_participants.user_id`, `settlements.{from_user,to_user,created_by}`, and `split_invitations.inviter` reference `auth.users` **without** `ON DELETE CASCADE`. Account deletion (`delete_user_account`, migration 0031) explicitly clears these before removing the user. See [04 — Security & Privacy](04-security-and-privacy.md#account-deletion).

## Reference / lookup tables

Enums are normalised into lookup tables synced read-only to every client (the `reference_data` stream): `account_types`, `transaction_types`, `category_kinds`, `periods`, `commitment_kinds`, `tiers`, `rate_modes`, `payment_methods`, `account_type_payment_methods`.

Global market data (read-only, populated by the `market-sync` edge function): `market_quotes`, `market_overview`, `market_dividends`. FX: `exchange_rates`.

## Domain class model (client core)

The money/ledger domain is pure TypeScript in `packages/core/*`, decoupled from persistence.

```mermaid
classDiagram
    class Money {
        +number amount  "minor units"
        +string currency
        +add(Money) Money
        +subtract(Money) Money
        +fromMajor(value, ccy) Money
        +toMajor() number
        +format(locale) string
    }
    class LedgerEntry {
        +string account_id
        +string type
        +number amount
        +string currency
        +Date occurred_at
    }
    class AccountBalance {
        +string account_id
        +Money total
        +Money available  "total − blocked"
        +Money blocked    "goal allocations"
    }
    class RateLookup {
        <<interface>>
        +rate(from, to) number
    }
    class FinanceEngine {
        <<module @sanvya/finance>>
        +futureValue(P, PMT, r, n) number
        +monthlyEquivalent(amount, period) number
        +recurringMonthlyTotal(items) number
        +projectCashflow(inputs, years) YearProjection[]
        +subscriptionImpact(...) SubscriptionImpact
    }

    LedgerEntry "many" --> "1" AccountBalance : deriveBalance()
    AccountBalance --> Money
    LedgerEntry --> Money
    FinanceEngine ..> Money : operates on minor units
    AccountBalance ..> RateLookup : net worth in base ccy
```

## Repositories (data access)

`packages/data` exposes typed repositories over the local SQLite DB. UI never writes SQL directly for domain entities — it goes through repositories or the generic `write.ts` helpers (`insertRow`, `updateRow`, `softDelete`) which auto-fill `id`, `user_id`, and timestamps.

```mermaid
flowchart LR
    UI["React components / hooks"] --> Repos["Repositories<br/>@sanvya/data"]
    UI --> WriteH["write.ts<br/>insertRow · updateRow · softDelete"]
    Repos --> PS[("PowerSync SQLite")]
    WriteH --> PS
    Repos --> Ledger["@sanvya/ledger<br/>deriveBalance · aggregateNetWorth"]
```

## Conventions

- **Minor units everywhere.** Convert at the UI edge with `fromMajor` / `toMajor`.
- **Soft delete** via `deleted_at`; queries filter `WHERE deleted_at IS NULL`.
- **`updated_at` is always set** by the write helpers (required server-side for upload).
- **UUID primary keys** generated client-side (`crypto.randomUUID()`) so offline inserts have stable ids before sync.
