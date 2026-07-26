# Implementation plan — Receipt & bill scanning + itemized split

**Status:** awaiting approval · **Created:** 2026-07-25 · **Owner:** —

Feature: scan/upload a restaurant receipt or grocery bill → OCR → structured line items →
auto-filled transaction, optionally split per-item across a group with tax/service handled
separately.

## Decisions (locked)

| # | Decision | Choice |
|---|----------|--------|
| D1 | OCR engine | **Hybrid** — Tesseract.js on-device first; "Improve with AI" fallback to a Claude-vision edge function when confidence is low or items don't reconcile to the total |
| D2 | Receipt image storage | **Not stored.** Processed in memory, discarded after parse. Schema + code keep a nullable `image_path` seam so a private Supabase Storage bucket can be added later without a rewrite |
| D3 | Split depth | **Full per-item.** New `expense_items` + `expense_item_shares`; per-item modes equal / exact / percent / by-quantity. Tax, service charge, tip are separate splittable lines (default pro-rata). Rolls up into existing `expense_participants` so all balance/settle-up logic is untouched |

---

## Architecture summary

```
FAB (speed-dial)
  ├─ Add transaction        → /transactions/new           (existing)
  └─ Scan bill / receipt    → /receipts/new               (new)
                                  │
                    capture / upload (camera or file)
                                  │
                    client preprocess (downscale, grayscale, deskew)
                                  │
                    ┌─────────────┴─────────────┐
                    │ Tesseract.js (worker)     │  on-device, free, offline
                    └─────────────┬─────────────┘
                                  │ parse → ReceiptDraft
                          reconcile check
                    (Σ items + tax + service + tip ≈ total?)
                                  │
                      ok ─────────┴───────── low confidence
                       │                          │
                       │                  "Improve with AI" (opt-in, Premium/quota)
                       │                          │
                       │              supabase/functions/receipt-scan
                       │              (Claude vision → strict JSON tool schema)
                       │                          │
                       └────────► ReceiptDraft ◄──┘
                                  │
                        /receipts/review  (edit merchant, date, items, tax…)
                                  │
                    ┌─────────────┴─────────────┐
              "Just record it"            "Split this"
                    │                           │
      transactions.create + items      pick/create group → /receipts/split
                                       per-item assignment → createSplitExpenseItemized()
                                                │
                                       expenses + expense_items +
                                       expense_item_shares + expense_participants
                                       + projectPersonal() (unchanged)
```

**Core principle:** the itemized layer is *additive*. `expense_items` / `expense_item_shares`
are the detail; the rolled-up per-person totals still land in `expense_participants`, so
`useGroupBalances`, `useFriendBalances`, `pairwiseEdges`, `settleUp`, and the split-collapse
display logic all keep working with zero changes.

---

## Data model

### New tables (all in `pocketcare` schema, synced)

**`receipt_scans`** — audit/history of a scan, so a draft survives a refresh and we can show
"scanned from a receipt" on a transaction. No image bytes.

| column | type | notes |
|---|---|---|
| `id` | text (uuid) | |
| `user_id` | text | RLS owner |
| `source` | text | `camera` \| `upload` |
| `engine` | text | `tesseract` \| `claude` \| `tesseract+claude` |
| `merchant` | text | null |
| `occurred_at` | text | parsed date, null if unreadable |
| `currency` | text | |
| `subtotal` / `tax` / `service_charge` / `tip` / `discount` / `total` | integer | minor units, nullable |
| `confidence` | integer | 0–100 |
| `raw_text` | text | OCR text, for re-parse & debugging |
| `parsed_json` | text | the full `ReceiptDraft` JSON |
| `transaction_id` | text | null until committed |
| `expense_id` | text | null unless split |
| `image_path` | text | **always null for now** — D2 seam |
| `created_at` / `updated_at` / `deleted_at` | text | |

**`expense_items`** — a line on a split bill.

| column | type | notes |
|---|---|---|
| `id`, `expense_id`, `group_id` | text | |
| `kind` | text | `item` \| `tax` \| `service_charge` \| `tip` \| `discount` |
| `description` | text | |
| `quantity` | integer | qty × 1000 (milli-units, so 0.5 kg works) |
| `unit` | text | `pcs`, `kg`, `l`, … nullable |
| `unit_price` | integer | minor units, nullable |
| `amount` | integer | minor units — line total, authoritative |
| `split_mode` | text | `equal` \| `exact` \| `percent` \| `quantity` \| `proportional` |
| `sort` | integer | |
| `created_at`/`updated_at`/`deleted_at` | | |

**`expense_item_shares`** — who's on the hook for each line.

| column | type | notes |
|---|---|---|
| `id`, `item_id`, `expense_id`, `group_id`, `user_id` | text | |
| `weight` | integer | mode-dependent: qty milli-units, percent×100, or exact minor |
| `share_amount` | integer | resolved minor units (largest-remainder allocated) |

Also: `expenses` gains `has_items integer` (0/1) and `transactions` gains **nothing** —
receipt line items for a *non-split* transaction reuse existing `transaction_items`
(which already carries `description` + `amount`; qty/unit go into the description string
to avoid a schema change — see Task 3 note if you'd rather add columns).

### Invariants
- `Σ expense_items.amount == expenses.amount` (client assert + Postgres check trigger).
- `Σ expense_item_shares.share_amount == expense_items.amount`, per item.
- `Σ expense_participants.share_amount == expenses.amount` (already enforced).
- Allocation always via `splitByWeights` (largest remainder) so no rupee is lost.

---

## Tasks

### Phase A — Foundations

**A1. Types + math package** (`packages/core/receipts`, new)
- `ReceiptDraft`, `ReceiptLine`, `ReceiptTotals` types (erasable TS, const-object unions).
- `reconcile(draft)` → `{ ok, delta, reason }` — Σ lines + tax + service + tip − discount vs total.
- `allocateItem(item, shares, mode)` → per-user minor units, wraps `splitByWeights`.
- `allocateProportional(chargeAmount, subtotalByUser)` → pro-rata tax/service allocation.
- `rollUp(items, shares)` → `Map<userId, shareAmount>` for `expense_participants`.
- **Tests** (`node:test`): reconciliation tolerance, rounding never loses/creates money,
  quantity mode with fractional qty, proportional tax with a zero-subtotal participant,
  100% single-payer item, discount lines (negative amounts).
- Add `@pocketcare/receipts` to `pnpm-workspace` + web deps + `test:core`.

**A2. Migration `0040_receipts_and_expense_items.sql`**
- Create the three tables above + `expenses.has_items`.
- RLS owner policies (`user_id = auth.uid()`) on `receipt_scans`; for `expense_items` /
  `expense_item_shares` mirror the **existing `expenses` group-membership policy** (a member
  of the group can read/write) — copy the pattern from `0001_init.sql`'s expense policies.
- Grants to `authenticated`.
- Sum-check trigger for `expense_items` → `expenses.amount`.
- Validate with pglast before committing.

**A3. Client schema + sync**
- Add all three tables to `AppSchema` (`packages/db/src/index.ts`) with indexes
  (`by_expense`, `by_group`, `by_item`).
- Add to `packages/db/sync-streams.yaml`: `receipt_scans` in `user_data`;
  `expense_items` + `expense_item_shares` in whichever stream currently carries `expenses`
  (group-scoped) — must match, or split members won't see each other's items.
- ⚠️ Requires `supabase db push` **and** a PowerSync dashboard sync-rule redeploy.

### Phase B — OCR pipeline

**B1. Image capture + preprocess** (`apps/web/src/receipts/image.ts`)
- `<input type="file" accept="image/*" capture="environment">` → camera on mobile, picker on desktop.
  Also accept `application/pdf` (some bills are emailed as PDF) and reuse `src/statements/parsePdf.ts`
  to rasterize page 1 / pull the embedded text layer — a text-layer PDF skips OCR entirely and is
  the highest-accuracy path.
- Downscale to max 2000px on the long edge, EXIF-orient, grayscale + adaptive threshold,
  output JPEG blob + a data URL for preview. Canvas only, no new deps.
- Never write the blob to disk/IndexedDB (D2).

**B2. On-device OCR** (`apps/web/src/receipts/ocr.ts`)
- Add `tesseract.js` dep; run in a Web Worker with `eng` traineddata self-hosted under
  `public/tesseract/` (no CDN at runtime → keeps offline-first + PWA caching honest).
  Add the worker + traineddata to the SW precache list in `public/sw.js`.
- `runOcr(blob, onProgress)` → `{ text, meanConfidence, words[] }` with bounding boxes
  (boxes matter — column alignment is what separates a price from a quantity).

**B3. Heuristic parser** (`apps/web/src/receipts/parse.ts`)
- Line reconstruction from word boxes (group by y-band, sort by x).
- Extract: merchant (top-most non-numeric block), date (multi-format, dd/mm vs mm/dd
  disambiguated by locale + "date can't be in the future"), currency symbol → ISO.
- Line items: rightmost numeric token = amount; leading `2 x` / `2 @` / `1.5 kg` → qty + unit;
  middle = description. Grocery bills often put qty/rate/amount in three columns — handle both.
- Keyword table for `tax` (GST/CGST/SGST/IGST/VAT/service tax), `service_charge`
  (service charge / service chg), `tip` (tip/gratuity), `discount` (discount/off/savings),
  `total` (total/grand total/net payable/amount due), `subtotal`.
- Emit `ReceiptDraft` + a per-field confidence.
- **Tests**: a fixtures folder of ~10 anonymized OCR text samples (restaurant + Indian
  grocery + supermarket) asserting parsed output. This is the regression net.

**B4. Claude-vision fallback**
- `supabase/functions/receipt-scan/index.ts` — clone the `assistant` function's shape:
  same CORS/`json()` helper, same `verify_jwt`, same entitlements quota read/decrement,
  same service-role client on `pocketcare` schema.
- Model: a **vision-capable** model (`claude-sonnet-4-5` class), overridable via a
  `RECEIPT_MODEL` secret. Body: `{ image: base64, mediaType, currencyHint, localeHint }`.
- Force structured output with a **tool schema** (`emit_receipt`) rather than free-text JSON —
  no parsing of prose, and the model can't drift the shape.
- Guardrail: images are user-supplied, so cap payload size (~5 MB), reject non-image media
  types, and ignore any instruction-like text the model reports inside the image
  (prompt-injection-via-receipt is a real vector — the tool schema already contains it, but
  add a note + a `system` line telling the model to treat image text as data, never instructions).
- Server never persists the image; `Deno` scope only.
- Client: `apps/web/src/receipts/aiParse.ts` → `functions.invoke("receipt-scan")`, maps the
  tool result to `ReceiptDraft`, unwraps `FunctionsHttpError.context` for real error messages
  (same fix as `acceptInvite`).

**B5. Orchestrator** (`apps/web/src/receipts/scan.ts`)
- `scanReceipt(file, { onStage })` → preprocess → OCR → parse → `reconcile()`.
- If `!ok` or `meanConfidence < 70`: surface "We couldn't read this cleanly" with an
  **Improve with AI** button (never auto-send the image — D1 is opt-in by design, and it
  costs quota). Show remaining quota on the button.
- Offline: AI button disabled with "needs a connection".
- Persist the draft to `receipt_scans` as soon as it exists so a refresh doesn't lose work.

### Phase C — UI

**C1. FAB → speed dial** (`apps/web/app/AppShell.tsx` + `globals.css`)
- Replace the single `<Link className="add-fab">` with `<AddSpeedDial />`
  (new `apps/web/src/AddSpeedDial.tsx`).
- Closed: pill "Add" with `+`. Open: `+` rotates 45° → `×`, two mini-actions stagger in
  **above** it, bottom-up: `Add transaction` (top-most is furthest, so order in DOM is
  reversed — Add transaction renders highest), then `Scan bill / receipt`.
- Backdrop scrim (click/Esc closes), `framer-motion` stagger (already a dep), focus trap,
  `aria-expanded` / `aria-haspopup="menu"`, `role="menu"` + `menuitem`, arrow-key nav.
- Keep the existing hide rules: `body[data-dash-edit]`, `body[data-dash-empty]`.
- `prefers-reduced-motion` → no rotate/stagger, just show/hide.

**C2. `/receipts/new`** — capture screen
- Two big targets: **Take photo** / **Upload file**; drag-and-drop on desktop.
- Live stage indicator (preprocessing → reading → understanding) with the Tesseract progress %.
- Preview thumbnail + "retake". Privacy line: *"Read on your device. Nothing is uploaded
  unless you tap Improve with AI."*

**C3. `/receipts/review`** — the draft editor
- Header: merchant, date, currency, account picker, category (prefill via the existing
  `suggestCategory` engine on the merchant string), payment method.
- Editable item table: description · qty · unit price · amount · delete; "Add line".
- Charges block: subtotal (computed), tax, service charge, tip, discount, **total**.
- Live reconciliation strip: *"Items + charges = ₹1,240 · receipt says ₹1,240 ✓"* /
  red with a one-tap "Add ₹12 as an unlabelled line" fix.
- Split toggle: **Just record it** / **Split this**.
  - Just record it → `transactions.create({ …, items })` (items must sum exactly — the
    reconciler guarantees it) → navigate to the transaction. Stamp `receipt_scans.transaction_id`.
  - Split this → group picker (existing `useGroups`) + **Create new group** inline
    (existing `createGroup`) → `/receipts/split`.

**C4. `/receipts/split`** — per-item assignment (the centrepiece)
- Member chips rail at the top (avatars/initials, tap to toggle "select-all for this item").
- One card per line item: description · qty · amount, then a participant row.
  - Default: everyone in the group, equal.
  - Per-item mode chips: **Equal · Quantity · Amount · Percent** (only Quantity shown when
    qty > 1). Quantity mode = steppers per person that must sum to the line qty.
  - Per-item live validation line, mirroring the copy patterns already in `transactions/new`.
- Charges cards (tax / service / tip): same control set **plus** a `Proportional` mode which
  is the default — allocated by each person's item subtotal.
- Sticky footer: per-person running totals + "You: ₹430" and a Save button disabled until
  every line validates.
- Bulk helpers: "Everyone on everything", "Only me", "Split evenly" reset.
- Mobile: cards stack, chips wrap, steppers are 44px targets; respect the no-horizontal-scroll
  invariants (`min-width:0` on grid children).

**C5. Write path** (`apps/web/src/splits/writeItemized.ts`)
- `createSplitExpenseItemized(input)`:
  1. `allocateItem` per line → `expense_item_shares`.
  2. `allocateProportional` for charge lines flagged proportional.
  3. `rollUp` → per-user totals → assert `Σ == total`.
  4. Insert `expenses` (`has_items = 1`, `split_mode = "itemized"`) → `expense_items` →
     `expense_item_shares` → `expense_participants`.
  5. Call the **existing** `projectPersonal(...)` unchanged for the private ledger legs.
  6. Also write `transaction_items` on your own-share transaction so your personal breakdown
     shows the lines you're paying for.
  7. Stamp `receipt_scans.expense_id`.
- Add `"itemized"` to `SplitMode` and make `computeShares` throw if called with it
  (itemized always goes through the new path).

**C6. Read/display**
- `useExpenseItems(expenseId)` + `useExpenseItemShares(expenseId)` in `src/splits/hooks.ts`.
- Group expense detail: itemized breakdown table when `has_items`, with a per-person tab.
- `SplitBanner` (transaction detail) gains "View items" → the breakdown.
- `collapse.ts` needs **no change** (roles are unchanged).
- Transactions list: a small "Scanned" chip when `receipt_scans.transaction_id` matches
  (cheap join in the existing list query).

### Phase D — Cross-cutting

**D1. Entitlements / quota**
- On-device OCR: **free, unlimited** (it costs us nothing).
- "Improve with AI": consumes the existing `entitlements` quota (`monthly_quota_total −
  monthly_quota_used + purchased_quota_remaining`), shared with the assistant. No new table.
- Free tier: keep OCR free (it's the hook), gate only the AI fallback. Show the quota chip
  on the button and route to the existing upgrade/top-up flow at zero.

**D2. i18n**
- New namespace `receipts` (`packages/core/i18n/src/locales/receipts/{en,hi,nl}.json`),
  registered in `resources` + `NAMESPACES`.
- Covers: FAB labels, capture screen, stages, errors, review editor, reconciliation copy,
  split screen (modes, validation lines, per-person summary), AI-fallback + quota copy.
- Mark hi/nl for native review, per the existing rollout convention.

**D3. Accessibility & responsive**
- Speed dial: keyboard-operable, focus-trapped, `Esc` closes, reduced-motion respected.
- Item table: real `<table>` semantics with a card layout at ≤700px via CSS only.
- Every numeric input `inputMode="decimal"`, steppers ≥44px.
- Contrast on validation red/green against `--surface` in both themes.

**D4. Docs (mandatory per CLAUDE.md)**
- `docs/features/receipt-scanning.md` — overview, user-flow + sequence Mermaid diagrams,
  data touched, key files, gating, edge cases.
- Update `docs/architecture/02-data-model.md` ER diagram (3 new tables).
- Update `docs/architecture/03-sync-and-offline.md` (new stream entries + `receipt-scan` fn).
- Update `docs/architecture/04-security-and-privacy.md` — the image-leaves-device path, the
  opt-in consent, the no-storage decision, and receipt-text prompt-injection handling.
- Update `docs/features/README.md`, `docs/features/splits.md` (itemized mode).
- Dated entry in `PROJECT_REFERENCE.md`.
- Regenerate the docs PDF (`scripts/build-docs-pdf.sh`).

**D5. Verification**
- `pnpm --filter @pocketcare/web typecheck`
- `pnpm test:core` (new `@pocketcare/receipts` suite must pass alongside the existing 49)
- Playwright e2e: upload a fixture image → review → save as plain transaction; and
  → split across 3 members → assert per-person totals.
- Manual matrix: crumpled restaurant bill, thermal grocery bill (faded), a PDF bill,
  a non-receipt photo (must fail gracefully), airplane mode (OCR works, AI disabled).

---

## Sequencing & effort

| Order | Tasks | Ships |
|---|---|---|
| 1 | A1, A2, A3 | Schema + math + tests. Nothing user-visible. |
| 2 | B1, B2, B3 | On-device OCR working, verifiable against fixtures. |
| 3 | C1, C2, C3 (record-only path) | **Milestone 1: scan → transaction.** Genuinely shippable alone. |
| 4 | B4, B5 | AI fallback + quota. |
| 5 | C4, C5, C6 | **Milestone 2: itemized split.** |
| 6 | D1–D5 | Gating, i18n, docs, verification. |

Milestone 1 is a real release on its own — worth shipping before starting the split work.

## Risks

- **OCR accuracy on thermal receipts** is the whole feature's ceiling. Mitigation: the fixture
  test suite is built in Phase B and treated as the acceptance bar; the AI fallback is the
  escape hatch. Expect to iterate on `parse.ts` after real-world use.
- **Tesseract bundle weight** (~2 MB wasm + ~10 MB traineddata). Mitigation: lazy-load the
  worker only on `/receipts/*`, cache via the SW, never in the main bundle.
- **Rounding across two allocation stages** (per item, then proportional charges) can drift.
  Mitigation: allocate once against the grand total at the end and assert equality; tests cover it.
- **PowerSync sync-rule redeploy is a manual dashboard step** — if forgotten, split members
  silently see no items. Call it out in the PR description.
- **Prompt injection via receipt text** ("ignore previous instructions…" printed on a bill).
  Mitigation: tool-schema-forced output + an explicit system instruction that image text is data.

## Open questions

1. Should grocery line items map to **sub-categories** (produce/dairy/household) automatically?
   Doable by extending `categorize/seeds.ts` with item-level terms, but it's a meaningful add —
   suggest deferring to a follow-up.
2. Multi-currency: if a receipt's currency ≠ the account's currency, do we prompt for an FX
   rate (the `transactions/new` cross-currency flow) or block? Suggest: reuse the existing flow.
3. Should a scanned receipt be able to create a **new group** from detected names? No — too speculative.
