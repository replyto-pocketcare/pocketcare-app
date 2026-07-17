# CLAUDE.md — PocketCare working guide

> Read `PROJECT_REFERENCE.md` first (living index + change log). This file adds the rules an agent must follow while working here.

## What this is
Offline-first, multi-currency personal expense & wealth manager. **Web-only** (Next.js PWA; mobile was deprecated). PowerSync (WASM SQLite) ↔ Supabase Postgres. Full technical docs live in [`docs/`](docs/README.md).

## Golden rules (never violate)
1. Money = **integer minor units**, never floats. Use `@pocketcare/money`.
2. Balances are **derived from an append-only ledger**, never mutated.
3. All tables + RPCs live in the **`pocketcare`** Postgres schema → direct calls must be schema-qualified (`supabase.schema('pocketcare').rpc(...)`) or PostgREST 404s.
4. Server is authoritative; the client is an offline cache reconciled via sync.

## Adding a synced table (all four steps or it won't sync)
1. Add to `AppSchema` (`packages/db/src/index.ts`).
2. Add a migration `supabase/migrations/00xx_*.sql` (RLS owner policy + grants).
3. Add to `packages/db/sync-streams.yaml` (`user_data` or the right stream).
4. `supabase db push` **and** redeploy sync rules to the PowerSync dashboard.

## 📚 Documentation maintenance rule (MANDATORY on every feature change)
When you add or materially change a feature, **update the docs in the same change set**:
1. **Feature doc** — create/update `docs/features/<feature>.md` (overview, user-flow diagram, technical/sequence diagram, data touched, key files, gating, edge cases). Follow the structure of the existing feature docs.
2. **Diagrams** — update affected Mermaid diagrams. New table → update the ER diagram in `docs/architecture/02-data-model.md`. New stream/edge function → update `docs/architecture/03-sync-and-offline.md`. New auth/crypto/deletion behaviour → `docs/architecture/04-security-and-privacy.md`.
3. **Indexes** — add to `docs/features/README.md` (and `docs/README.md` if architectural).
4. **Change log** — add a dated entry to `PROJECT_REFERENCE.md`.
5. **Shareables** — if diagrams/architecture changed, regenerate the PDF via `scripts/build-docs-pdf.sh`. If investor-relevant, flag for the next deck refresh (`pitch/`).

Diagrams are **Mermaid** (GitHub-native, maintainable). Keep them accurate — a wrong diagram is worse than none.

## Conventions
- Read with `useQuery` (PowerSync react); write with `write.ts` helpers (`insertRow`/`updateRow`/`softDelete`) — they auto-fill id/user_id/timestamps.
- Soft-delete via `deleted_at`; filter `WHERE deleted_at IS NULL`.
- Format money via `useMoneyFmt()` (respects the hide-amounts toggle).
- Use design tokens (`globals.css` `:root`), `.card`/`.btn`/`.chip`/`.list-grid`; charts use CSS-var fills for theming.
- Gate premium behind `useEntitlement`.
- Verify with `pnpm --filter @pocketcare/web typecheck` and core tests (`node --test packages/core/**/src/*.test.ts`).

## Environment note
The workspace mount disallows file deletion, so git commits made by the agent can leave stale `.git/*.lock` files that jam follow-up commits. Prefer handing the user a ready-to-paste `git add && git commit` command; if it jams, `rm -f .git/*.lock`.
