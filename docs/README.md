# PocketCare — Documentation

> Living technical documentation for engineers, reviewers, and new joiners.
> Diagrams are written in **Mermaid** and render natively on GitHub.

PocketCare is an **offline-first, multi-currency personal expense & wealth manager**. It runs as an installable **PWA** (Next.js), backed by **PowerSync** (local WASM SQLite) syncing to **Supabase** Postgres. All money is stored as integer minor units; balances are derived from an append-only ledger.

## Map of this documentation

### Architecture (start here)

| Doc | What it covers |
|---|---|
| [01 — System Overview](architecture/01-system-overview.md) | Stack, monorepo layout, runtime topology, request/sync path |
| [02 — Data Model](architecture/02-data-model.md) | Postgres schema, entity relationships (ER), core class model |
| [03 — Sync & Offline](architecture/03-sync-and-offline.md) | PowerSync ↔ Supabase, offline writes, conflict handling, guest identity |
| [04 — Security & Privacy](architecture/04-security-and-privacy.md) | Auth, RLS, zero-trust encryption, support-key custody, account deletion |
| [05 — Frontend & Design System](architecture/05-frontend-and-design-system.md) | App shell, state, repositories, design tokens, components |

### Features

Every user-facing feature area has its own doc with an **overview**, a **user-flow diagram**, a **technical/sequence diagram**, the **data it touches**, **key files**, and **edge cases**. See the [features index](features/README.md).

### Shareables (generated)

- [`docs/exports/PocketCare-Technical-Overview.pdf`](exports/PocketCare-Technical-Overview.pdf) — polished PDF snapshot of the architecture, with rendered diagrams (regenerate via `scripts/build-docs-pdf.sh`; sources in `docs/pdf-src/`).
- [`pitch/PocketCare-Investor-Deck.pptx`](../pitch/PocketCare-Investor-Deck.pptx) — investor pitch deck (+ a rendered `.pdf`). Business-specific figures are marked `[PLACEHOLDER]`.

### Other references (repo root)

- [`PROJECT_REFERENCE.md`](../PROJECT_REFERENCE.md) — living per-session index + change log (source of truth for "what changed").
- [`ARCHITECTURE.md`](../ARCHITECTURE.md) — original architecture & implementation plan.
- [`DESIGN_SYSTEM.md`](../DESIGN_SYSTEM.md) — visual language tokens.
- [`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md), [`SECURITY_ENCRYPTION_PLAN.md`](../SECURITY_ENCRYPTION_PLAN.md) — security posture.

---

## 🔧 Documentation maintenance rule (read before shipping a feature)

**These docs are living artifacts. Any change that adds or materially alters a feature MUST update the docs in the same change set.** Concretely, when you add/modify a feature:

1. **Feature doc** — create or update `docs/features/<feature>.md` (overview, user-flow diagram, technical diagram, data touched, key files, gating, edge cases).
2. **Diagrams** — update the relevant Mermaid diagram(s). If you added a table, update the ER diagram in [02 — Data Model](architecture/02-data-model.md). If you added a sync stream or edge function, update [03 — Sync & Offline](architecture/03-sync-and-offline.md).
3. **Index** — add the feature to the [features index](features/README.md) and, if architectural, to this README.
4. **Change log** — add a dated entry to `PROJECT_REFERENCE.md` (existing convention).
5. **PDF/deck** — regenerate the shareable PDF (`scripts/build-docs-pdf.sh`) and, if the change is investor-relevant, note it for the next deck refresh.

This rule is also mirrored in the project's `CLAUDE.md` so the AI agent applies it automatically on every feature.

> Rule of thumb: **if a reviewer would need to know it, it belongs in `/docs`; if it changed, the doc changes with it.**
