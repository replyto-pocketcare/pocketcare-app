# Features

Each feature has a dedicated doc with: **Overview**, **User flow** (Mermaid), **Technical flow** (Mermaid sequence/flowchart), **Data touched**, **Key files**, **Gating** (free/premium), and **Edge cases**.

> When you add or change a feature, update its doc here (and the data-model / sync docs if schema or streams changed). See the [maintenance rule](../README.md#-documentation-maintenance-rule-read-before-shipping-a-feature).

## Index

| Area | Doc | Route(s) |
|---|---|---|
| Onboarding & identity | [onboarding-and-identity](onboarding-and-identity.md) | `/onboarding`, `/login`, `/join` |
| Dashboard | [dashboard](dashboard.md) | `/` |
| Accounts & ledger | [accounts-and-ledger](accounts-and-ledger.md) | `/accounts` |
| Transactions | [transactions](transactions.md) | `/transactions` |
| Templates & recurring | [templates-and-recurring](templates-and-recurring.md) | `/templates` |
| Cards (3D wallet) | [cards](cards.md) | `/cards` |
| Budgets | [budgets](budgets.md) | `/budgets` |
| Goals & emergency fund | [goals](goals.md) | `/goals` |
| Planned Cashflow (BETA) | [planned-cashflow](planned-cashflow.md) | `/cashflow` |
| Recurring payments & income | [recurring](recurring.md) | `/recurring` |
| Loans (EMI schedule) | [loans](loans.md) | `/loans`, `/loans/[id]` |
| Investments | [investments](investments.md) | `/investments` |
| Splits (friends, groups & trips) | [splits](splits.md) | `/friends`, `/groups` |
| Search | [search](search.md) | `/search` |
| Insights | [insights](insights.md) | `/insights` |
| Statements | [statements](statements.md) | `/statements` |
| Ask PocketCare (AI assistant) | [assistant](assistant.md) | `/assistant` |
| Settings & preferences | [settings](settings.md) | `/settings` |
| Billing & entitlements | [billing-and-entitlements](billing-and-entitlements.md) | `/settings` (plan) |
| Security & account deletion | [../architecture/04-security-and-privacy](../architecture/04-security-and-privacy.md) | `/settings` |
| Admin console | [admin-console](admin-console.md) | `/admin/*` |
| PWA & offline | [pwa-and-offline](pwa-and-offline.md) | (app-wide) |

## Free vs Premium (gating summary)

- **Free:** accounts, transactions + breakdown, categories/labels, a simple budget, search, basic balances, Planned Cashflow basics.
- **Premium:** advanced analytics/insights, multi-budget + notifications, goal compounding projections, subscription impact simulator, investment auto-fetch, statement PDF export, period comparisons, higher AI assistant quota.

Gating is enforced by `useEntitlement()` (offline-capable, effective tier + trial + quota).
