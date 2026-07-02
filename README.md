# PocketCare

Offline-first, cross-device (iOS / Android / Web), multi-currency, multi-language expense & wealth manager. Earthy, minimal design.

> **Docs:** [`PROJECT_REFERENCE.md`](./PROJECT_REFERENCE.md) (living index — read first) · [`ARCHITECTURE.md`](./ARCHITECTURE.md) (full design & roadmap).

## Monorepo layout

```
apps/
  mobile/        Expo (React Native) app
  web/           Next.js (App Router) app
packages/
  types/         shared domain types & enums
  core/money/    currency-aware Money + FX + Intl formatting   (unit-tested)
  core/finance/  projections, recurring, subscription impact   (unit-tested)
  core/i18n/     i18next config + en/hi/ar bundles, RTL support
  core/entitlements/ freemium gating                            (unit-tested)
  db/            PowerSync client schema + sync-rules.yaml
  data/          repository interfaces (data-access contract)
  ui-tokens/     earthy theme design tokens
```

Presentation is the only platform-specific layer; everything in `packages/*` is shared by both apps.

## Prerequisites

- **Node 22+** (`.nvmrc` pins 22) and **pnpm 9+** (`corepack enable`)
- For mobile: Xcode (iOS) / Android Studio, and a **dev build** — this project uses PowerSync native modules, so **Expo Go will not work**.

## Install

```bash
corepack enable
pnpm install
```

## Run the tested core (no accounts needed)

The financial logic runs and is tested in isolation — no Supabase/PowerSync required:

```bash
pnpm test:core
```

This runs the `@pocketcare/money` and `@pocketcare/finance` test suites via Node's built-in test runner (TypeScript is type-stripped, no build step).

## Connect the backend (Supabase + PowerSync)

Phase 0 ships the client scaffold. To make it sync, wire up the two services:

1. **Supabase** — create a project. Enable **Anonymous sign-ins** (Auth → Providers) so every user gets a real UID from first launch (guest identity — see ARCHITECTURE.md §9). Apply the SQL schema, RLS policies, constraints, and triggers (added next phase under `supabase/migrations/`).
2. **PowerSync** — create an instance pointed at your Supabase Postgres. Paste `packages/db/sync-rules.yaml` into the instance's Sync Rules.
3. **Env** — copy `.env.example` to `.env` and fill in the Supabase + PowerSync URLs/keys. Note the prefix rules: `NEXT_PUBLIC_` (web) and `EXPO_PUBLIC_` (mobile) expose vars to the client.

## Run the apps

```bash
# Web
pnpm --filter @pocketcare/web dev

# Mobile (creates/uses a dev build)
pnpm --filter @pocketcare/mobile prebuild
pnpm --filter @pocketcare/mobile ios      # or: android
```

## Financial-integrity rules (do not violate)

Money is stored as **integer minor units** (never floats); balances are **derived from an append-only ledger** (never mutated in place); transaction breakdown items **must reconcile** to the total; sync is **server-authoritative** with immutable synced ledger entries. Full rationale in `ARCHITECTURE.md` §2.

## What's next (roadmap)

Phase 0 (this scaffold) → **Phase 1**: Supabase migrations + anonymous auth + accounts/transactions wired end-to-end on both apps. See `ARCHITECTURE.md` §8.
