# Statements

## Overview
Generate a **printable / PDF statement** for a chosen period — a letterheaded summary of transactions and balances. Premium.

## User flow
```mermaid
flowchart TD
    St([Statements]) --> Period[Pick period]
    Period --> Preview[Rendered statement]
    Preview --> Export[Print / Save as PDF]
```

## Technical flow
```mermaid
flowchart LR
    Period["date range"] --> Query["transactions + balances in range"]
    Query --> Doc["self-contained HTML statement (letterhead)"]
    Doc --> Print["window.print() → PDF"]
```

## Data touched
`transactions`, `accounts` (balances), profile/issuer details.

## Key files
`app/statements/`, related billing/invoice rendering (`src/billing/invoice.ts` shares the letterhead pattern).

## Gating
**Premium.**

## Edge cases
- Print stylesheet hides app chrome (`@media print`).
- Statement export stays unmasked regardless of the hide-amounts toggle.
