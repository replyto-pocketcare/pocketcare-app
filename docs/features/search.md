# Search

## Overview
Filter and find transactions by free text, type, account, and date range. Results render as responsive transaction tiles.

## User flow
```mermaid
flowchart TD
    S([Search]) --> Q[Enter query]
    Q --> Filt[Filters: type · account · date range]
    Filt --> Res[Matching transactions as tiles]
    Res --> Open[Open → edit transaction]
```

## Technical flow
```mermaid
flowchart LR
    Q["query + filters"] --> SQL["parameterised SQLite query\n(description/labels/category, type, account, occurred_at range)"]
    SQL --> Rows["results"] --> Grid[".list-grid of TransactionRow tile"]
```

## Data touched
`transactions`, `accounts`, `categories`, `labels` (read-only queries).

## Key files
`app/search/page.tsx`, `src/ui/TransactionRow.tsx`.

## Gating
Free.

## Edge cases
- Empty/blank query shows a clear empty state (full-width card).
- Date-input min-width handled so the page never overflows horizontally.
