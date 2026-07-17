# Recurring payments & income

## Overview
A dedicated page (`/recurring`) for regular money in and out — salary, rent, bills, EMIs, SIPs — modelled as **real recurring rules** (a `transaction_templates` row + a `recurring_rules` row) that post transactions via the recurring engine (auto-post on the due date, or ask-to-confirm). Grouped into **Incomes**, **Payments** and **Savings**, each with add/edit/remove and post-now, plus a "due now — confirm to record" tray.

## Where it's used
```mermaid
flowchart LR
    PC[Planned Cashflow] -- Add / quick-add / edit / convert --> R[/recurring]
    R -- creates template + rule --> Eng[Recurring engine]
    Eng -- posts --> Txn[transactions]
    R -- useRecurringItems --> PC
```
Adding a recurring item is centralised here. Planned Cashflow deep-links in via query params rather than opening its own dialog:
`?add=income|payment|saving` (optionally `&name=&amount=<minor>&freq=&convertFrom=<plannedId>`) or `?edit=<ruleId>`. On save, a `convertFrom` also soft-deletes the legacy standalone `planned_cashflow` row.

## Direction → template type
income → income template · payment → expense template · saving → transfer template into an investment account (`src/cashflow/recurring.ts` `createRecurring`/`updateRecurring`/`removeRecurring`, `RecurringModal`).

## Data touched
`transaction_templates`, `recurring_rules` (created/edited together), `transactions` (posted by the engine), `planned_cashflow` (only to remove a converted legacy row).

## Key files
`app/recurring/page.tsx`, `src/cashflow/recurring.ts`, `src/cashflow/RecurringModal.tsx`, `src/templates/write.ts` (engine: `postRuleOnce`/`skipRuleOnce`/`runRecurring`).

## Gating
Free.

## Notes
- The **Templates** page is now one-tap transaction templates only; recurring rules moved here.
- Due auto-post rules are materialised on app open (`runRecurring` in `AppShell`); confirm-rules appear in the due tray here.
