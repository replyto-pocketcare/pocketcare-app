# Planned Cashflow (BETA)

## Overview
A consolidated hub for **recurring income, planned payments, and savings**, with **aggregate summaries** per timeframe and a **deterministic, inflation-aware AI projection engine** (1/2/3-year structure). It merges the former standalone Subscriptions and Loans pages: subscriptions and loan EMIs are surfaced here alongside recurring payments. Marked **BETA**.

## Recurring rules are the source (nothing standalone)
Incomes, payments and savings are backed by **real recurring rules** (`transaction_templates` + `recurring_rules`) that actually post transactions via the recurring engine — not informational-only rows. Adding/editing them lives on the dedicated **[Recurring](recurring.md)** page (`/recurring`): the hub's **Add income / Add payment / Add recurring saving** buttons, quick-add chips, per-row Edit, and "Make it recurring" convert all deep-link there (`/recurring?add=…` / `?edit=…` / `…&convertFrom=…`). The hub reads recurring items via `useRecurringItems()` and includes them in every total/projection.

Legacy standalone `planned_cashflow` entries still render (labelled "one-off entry") with a **"Make it recurring"** action that opens the modal prefilled and removes the standalone row once the rule is created. Subscriptions and loan EMIs keep their own tables and are shown in the payments section; SIPs/holdings are managed on Investments.

## Structure
```mermaid
flowchart TB
    Hub([/cashflow]) --> TF[Timeframe tabs: Monthly · Quarterly · Yearly]
    Hub --> Hero[Aggregate hero: income · payments · net · savings]
    Hub --> Inc[Recurring incomes]
    Hub --> Pay[Planned payments\nhousehold + subscriptions + loan EMIs]
    Hub --> Sav[Savings & investments\nFD · emergency · MF · stocks · crypto]
    Hub --> AI[Financial summary + AI projections]
    Hero -.tap card.-> Inc
    Hero -.tap card.-> Pay
    Hero -.tap card.-> Sav
    Hero -.tap card.-> AI
```

## User flow
```mermaid
flowchart TD
    Start([Open hub]) --> Add{Add item}
    Add -->|template| Tpl[Quick-start template prefills form]
    Add -->|manual| Form[Name, amount, frequency, bucket]
    Form --> Route{Bucket routes to table}
    Route -->|subscription| Subs[(subscriptions)]
    Route -->|loan| Loans[(loans)]
    Route -->|income/household/saving| PC[(planned_cashflow)]
    Subs --> Recalc[Totals + charts recompute]
    Loans --> Recalc
    PC --> Recalc
    Recalc --> Proj[Tune return/inflation/growth → 1/2/3-yr projection]
```

## Technical flow — projection engine
```mermaid
flowchart LR
    Items["planned_cashflow + subscriptions + loans"] --> Norm["monthlyEquivalent()\nnormalise to monthly minor units"]
    Norm --> Totals["computeTotals()\nincome · payments · savings · net · surplus"]
    Totals --> Proj["projectCashflow(inputs, 3)\n@pocketcare/finance"]
    Sliders["return % · inflation % · income growth · starting savings"] --> Proj
    Proj --> Cards["1/2/3-yr structure cards"]
    Proj --> Charts["Recharts: growth area (nominal vs real), net-surplus bars"]
```

`projectCashflow` models month-by-month compounding: income/payments step up annually (raises/inflation), savings compound at the blended return and receive the monthly contribution; outputs nominal + inflation-adjusted (real) balances. Pure and unit-tested (9 tests).

## Data touched
`planned_cashflow` (`direction` income|payment|saving, `bucket`, `amount`, `frequency`, `timeframe`, `expected_return`), plus read/write of `subscriptions` and `loans`. Synced via the `user_data` stream (migration `0029`, sync-rules updated).

**Savings ↔ Investments:** adding a **SIP** on the Investments page creates a linked `planned_cashflow` saving (bucket `sip`), so SIPs appear in the Savings section here too. The Savings section also shows a read-only **invested-portfolio summary** card (current value + invested, from `holdings`) that links to `/investments`. See [features/investments](investments.md).

## Key files
`app/cashflow/page.tsx`, `src/cashflow/model.ts` (buckets, templates, aggregation), `src/cashflow/Charts.tsx` (recharts, token colors), `src/cashflow/Projections.tsx` (sliders + engine), `@pocketcare/finance` (`projectCashflow`, `yearlyEquivalent`, `timeframeTotal`).

## Gating
Free basics; the AI projection engine runs fully client-side (offline, no API cost).

## Edge cases
- Timeframe tabs scale the aggregate hero (×1/×3/×12); items keep their own frequency.
- Deep-link `/cashflow#payments` (from the dashboard subscriptions tile) scrolls to the payments section with a retry while synced data loads.
- Old `/subscriptions` and `/loans` routes now redirect here.
- BETA badges appear on the page, AI panel, add-modal, and sidebar item.
