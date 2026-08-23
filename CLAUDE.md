# CLAUDE.md — Sanvya working guide

> Read `PROJECT_REFERENCE.md` first (compact LLM boot file: architecture, structure, patterns — read it INSTEAD of scanning the repo). Dated change history lives in `AUDIT_HISTORY.md` — new dated entries go there, and PROJECT_REFERENCE.md is updated only for evergreen changes (new tables/patterns/conventions/instructions). This file adds the rules an agent must follow while working here.

## What this is
Offline-first, multi-currency personal expense & wealth manager. Live client: **web** (Next.js PWA). Pure-native Android/iOS apps are planned/in-flight (`docs/plans/native-mobile-apps.md`, queue in `docs/mobile/TODO.md`). PowerSync (WASM SQLite) ↔ Supabase Postgres. Full technical docs live in [`docs/`](docs/README.md).

## Golden rules (never violate)
1. Money = **integer minor units**, never floats. Use `@sanvya/money`.
2. Balances are **derived from an append-only ledger**, never mutated.
3. All tables + RPCs live in the **`pocketcare`** Postgres schema → direct calls must be schema-qualified (`supabase.schema('pocketcare').rpc(...)`) or PostgREST 404s. The product was renamed to Sanvya; the schema was not. Verified 2026-08-23 against `0001_init.sql`, every migration since, web's `schema("pocketcare")` call sites and `SupabaseConnector.DB_SCHEMA` on both native platforms — this rule said `sanvya` and was wrong.
4. Server is authoritative; the client is an offline cache reconciled via sync.

## Writing migrations
- **Schema-qualify every function call** — `pocketcare.is_group_member(...)`, not bare. Older migrations (0011) get away with a bare call only because they `set search_path` at the top of the file; copying their policy shape without that fails with `function is_group_member(uuid, uuid) does not exist`. (Same rename caveat as golden rule 3 — the schema is `pocketcare`.)
- **Make migrations re-runnable.** `create table`/`create index` take `if not exists`, but `create policy` and `create constraint trigger` do **not** — precede each with `drop policy if exists` / `drop trigger if exists`. A migration that fails halfway (as 0040 first did) otherwise can't be retried, because the statements before the failure already applied.
- Validate before shipping: `pip install pglast --break-system-packages`, then parse the file.
- **Never write a cross-row constraint on a synced table.** PowerSync uploads the write queue as separate HTTP requests, each its own Postgres transaction, so related rows arrive **incrementally** — a "these rows must sum to that row" check will fire against a partial set and **wedge the upload queue forever** (0040 did exactly this; 0042 removed it). `DEFERRABLE INITIALLY DEFERRED` does not help: it defers only to the end of its own transaction. Enforce such invariants on the client, where the whole set is known at once, and expose a server-side *audit* function for observability instead.

## Adding a COLUMN to a synced table (easy to forget — 2 steps)
PowerSync's local SQLite only has the columns declared in `AppSchema`. A column added in a migration but **not** mirrored there fails at runtime with `table <x> has no column named <y>` on both reads and writes — Postgres is fine, the device is not.
1. Add it to the table's `new Table({...})` in `packages/db/src/index.ts`.
2. `supabase db push` **and** deploy the Sync Streams config (a `SELECT *` stream picks it up automatically; an explicit column list does not).

## Adding a synced table (all four steps or it won't sync)
1. Add to `AppSchema` (`packages/db/src/index.ts`).
2. Add a migration `supabase/migrations/00xx_*.sql` (RLS owner policy + grants).
3. Add to `packages/db/sync-streams.yaml` (`user_data` or the right stream).
4. `supabase db push` **and** deploy the Sync Streams config in the PowerSync dashboard.

## 📚 Documentation maintenance rule (MANDATORY on every feature change)
When you add or materially change a feature, **update the docs in the same change set**:
1. **Feature doc** — create/update `docs/features/<feature>.md` (overview, user-flow diagram, technical/sequence diagram, data touched, key files, gating, edge cases). Follow the structure of the existing feature docs.
2. **Diagrams** — update affected Mermaid diagrams. New table → update the ER diagram in `docs/architecture/02-data-model.md`. New stream/edge function → update `docs/architecture/03-sync-and-offline.md`. New auth/crypto/deletion behaviour → `docs/architecture/04-security-and-privacy.md`.
3. **Indexes** — add to `docs/features/README.md` (and `docs/README.md` if architectural).
4. **Change log** — add a dated entry to `AUDIT_HISTORY.md` (never to `PROJECT_REFERENCE.md`; update that only if a table/pattern/convention/instruction changed).
5. **Shareables** — if diagrams/architecture changed, regenerate the PDF via `scripts/build-docs-pdf.sh`. If investor-relevant, flag for the next deck refresh (`pitch/`).

Diagrams are **Mermaid** (GitHub-native, maintainable). Keep them accurate — a wrong diagram is worse than none.

## Conventions
- **`useSyncExternalStore` getSnapshot must return a STABLE reference.** `() => [...buffer]` or an inline `() => []` allocates a new value per call, so React sees the store as changed every render and loops until it throws minified error #185 ("maximum update depth exceeded"). Cache the snapshot and rebuild it only on mutation; use a module-level constant for the server snapshot.
- Read with `useQuery` (PowerSync react); write with `write.ts` helpers (`insertRow`/`updateRow`/`softDelete`) — they auto-fill id/user_id/timestamps.
- Soft-delete via `deleted_at`; filter `WHERE deleted_at IS NULL`.
- Format money via `useMoneyFmt()` (respects the hide-amounts toggle).
- Use design tokens (`globals.css` `:root`), `.card`/`.btn`/`.chip`/`.list-grid`; charts use CSS-var fills for theming.
- Gate premium behind `useEntitlement`.
- Verify with `pnpm --filter @sanvya/web typecheck` and core tests (`node --test packages/core/**/src/*.test.ts`).

## Environment notes (agent sandbox)

### Git — enable deletion FIRST, then commit normally
The workspace mount starts read-only for deletes. **Ask for delete permission before touching git** (`allow_cowork_file_delete` on any path in the repo — approval applies to the whole folder). With it enabled, `git add`/`commit` work exactly as normal and leave nothing behind.

Without it, the failure is **silent and it jams the repo**:
- `git add -A` prints `warning: unable to unlink '.git/objects/../tmp_obj_*'` but **exits 0 while staging nothing** — `git diff --cached` is empty.
- It leaves a zero-byte `.git/index.lock` plus dozens of stray `tmp_obj_*` files, which block every later git command.
- You then **cannot `rm` them either**, so the repo is stuck until deletion is enabled.

Recovery, once deletion is enabled:
```bash
rm -f .git/*.lock && find .git/objects -name "tmp_obj_*" -delete
```

### Push is always the user's job
There are no git credentials in the sandbox — `git push` fails with `could not read Username for 'https://github.com'`. Commit locally, then hand the user a `git push origin <branch>`.

### pnpm is NOT installed in the sandbox
Only `node` and `npm`, and there is no network for a global install. Consequences:
- **`pnpm-lock.yaml` cannot be regenerated.** CI runs `pnpm install --frozen-lockfile`, so if a change adds a dependency or a new workspace package, the commit **will fail CI** until the user runs `pnpm install` and amends. Always say so explicitly.
- To typecheck a new workspace package, hand-link it: `ln -s ../../../../packages/core/<name> apps/web/node_modules/@sanvya/<name>` (and add its own `node_modules/@sanvya/*` links for its deps).
- Run tsc directly: `cd apps/web && ../../node_modules/.bin/tsc --noEmit`.
- Run core tests directly: `node --test --experimental-strip-types packages/core/*/src/*.test.ts`.

### Misc
- `mcp__workspace__bash` caps `timeout_ms` at 45000. Wrap slow commands in `timeout 40 …`.
- `pglast` (for validating migrations) installs fine: `pip install pglast --break-system-packages`.
