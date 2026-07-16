# Insights

## Overview
A premium **insight feed** of polished 2D charts and generated observations: cashflow, net trend, spending by category/label, month-over-month comparison, biggest expense, weekday patterns, no-spend days, category spikes, goal progress, and more (15+ generators).

## User flow
```mermaid
flowchart TD
    In([Insights]) --> Feed[Scroll feed of insight cards]
    Feed --> Card[Each card: headline + 2D chart]
    Card --> Act[Optional CTA → related page]
```

## Technical flow
```mermaid
flowchart LR
    Q["useInsightStack()\nqueries: 70-day spend, top expenses, labels, goals, category history"] --> Gen["generators\n(compose derived metrics)"]
    Gen --> Stack["composeStack() (cap 12)"]
    Stack --> Cards["InsightCard → Charts2D\n(area, bars, donut, gauge, progress)"]
```

## Data touched
Aggregated reads over `transactions`, `budgets`, `goals`, `goal_allocations`, `labels`, `categories`.

## Key files
`app/insights/`, `src/insights/generators.ts`, `src/insights/Charts2D.tsx`.

## Gating
**Premium.** Gated by `useEntitlement`.

## Edge cases
- Charts are 2D (react-three-fiber visuals were removed for performance).
- Unique gradient ids via `useId` to avoid SVG clashes.
- Charts stay unmasked even when "hide amounts" is on (opt-in analytics context).
