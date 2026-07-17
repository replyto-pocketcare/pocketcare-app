# PocketCare — Ship & Follow-up Checklist

_Last updated: 2026-07-17. Covers Planned Cashflow, currency conversion, loans/investments/cards, admin jobs, and the loan EMI due-date / auto-mark work._

## ✅ Verified this session
- `apps/web` typecheck: **clean** (`tsc --noEmit`).
- Core tests: **96/96 pass** (finance 33 incl. new EMI-schedule tests, + money/ledger/budget/entitlements/guardrail/reconcile/crypto).

## 🚀 Deploy steps (do in order)
- [ ] **Apply migrations** to Supabase: `supabase db push` (or run in SQL editor) — `0029`–`0034`:
  - `0029` planned_cashflow · `0030`/`0031` account deletion · `0032` loans/holdings/cards/demat · `0033` loan emi_payments · `0034` loan emi_due_day + auto_mark_paid.
- [ ] **Redeploy PowerSync sync rules** (`packages/db/sync-streams.yaml`) — required because `planned_cashflow` was added; the column-only migrations (0032/0033/0034) don't change streams but redeploy is safe.
- [ ] **Deploy edge functions:** `supabase functions deploy fx-sync` and (if not already) `market-sync`.
- [ ] **Schedule `fx-sync` daily** (Supabase scheduled function / cron → POST the function). Set secrets `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (and optional `FX_PROVIDER_URL`). Until it runs, unknown currency pairs fall back to 1:1.
- [ ] **Smoke test:** trigger both jobs from **/admin/jobs**; confirm success + that net worth / subscriptions convert after `fx-sync` populates `exchange_rates`.

## 📝 Commits (sandbox can't commit — run locally)
The workspace mount blocks git writes from the agent. Commit locally, e.g.:
```bash
cd ~/Projects/PocketCare && rm -f .git/*.lock
git add packages apps/web supabase docs PROJECT_REFERENCE.md CLAUDE.md pitch
git commit -m "feat(loans): EMI due-dates + auto-mark-paid, EMI→ledger option, grouped-input rollout"
```
Also: an old stray `PocketCare-Investor-Deck.pptx` sits at repo root (canonical copy is in `pitch/`) — `rm` it if you like.

## 🔭 Deferred / follow-ups
- [x] **Grouped amount inputs** — ✅ done everywhere: accounts/loans/cashflow/investments/transactions/budgets/goals + cashflow inline edit, card settle-up & cycle-edit, split exact-share/multi-payer, Friends settle dialog (2026-07-17).
- [x] **EMI "mark paid" → optional ledger transaction** — ✅ Mark-paid dialog optionally posts an EMI expense from a chosen funding account (2026-07-17). Follow-up left: a transfer variant / auto-linking the posted txn back to the EMI.
- [ ] **EMI due-date coverage** — ✅ per-EMI due dates + auto-mark-paid shipped (0034). Follow-up: surface next-EMI-due on the dashboard / a due-soon reminder (needs the deferred notification center).
- [ ] **Savings ↔ Investments unification** — savings section now links to Investments; deeper merge (recurring SIP contribution vs holding) still open. Decide whether `planned_cashflow` savings items should be derived from investment holdings.
- [ ] **OCR statements** — spec in `docs/design/ocr-statements.md`; answer the open questions (provider, on-device vs edge, retention, pilot type) before building.
- [ ] **Currency conversion coverage** — verify insights/statements/goals/budgets all convert; add a par-fallback banner when rates are missing.
- [ ] **Tests** — ✅ EMI paid-map / due-date derivation now unit-tested (`emiDueDate`, `isDuePassed`, `effectivePaidEmis` — 9 tests). Still to do: `cardDueDate`, `useCurrencyBreakdown`, and a Playwright smoke for the new pages (`/loans`, `/loans/[id]`, `/investments` demat flow).
- [ ] **Full monorepo typecheck** — run `pnpm -w typecheck` (all packages) in a real environment before release; the agent only ran `apps/web`.
- [ ] **Drive mirror** — `/docs` markdown partially uploaded to Google Drive (README + 2 architecture docs); finish or drag-drop the rest + binaries.

## 🩹 Known constraints
- Agent git commits blocked by the workspace mount (no unlink); commit locally.
- Chromium unavailable in sandbox → doc PDFs use Graphviz diagrams (Mermaid is the living source).
- Google Drive connector is create/read only (no update/delete, no binary streaming) → treat git as canonical, Drive as a refresh mirror.
