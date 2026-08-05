# Screen spec — Transactions (list, new, edit)

> Source: `apps/web/app/transactions/page.tsx` (88 lines), `.../new/page.tsx` (664 lines), `.../[id]/edit/page.tsx` (449 lines), `apps/web/src/ui/TransactionTile.tsx` (274 lines, the shared row component used here + Search + Statements + Dashboard) — read 2026-08-05.

## Scope of this pass

Ported: transaction list (search + type filter, `TransactionTile`-equivalent rows), create flow for **expense/income/transfer** (multi-item breakdown, account, category, payment method, labels, note, date, cross-currency transfer amount, investment-accounts-force-transfer rule), edit flow (same fields + `intent` Need/Greed chip + delete with a single confirm).

**Deferred, tracked separately (new TODO.md rows):**
- **Split-expense creation** (`new/page.tsx`'s "Split this expense" toggle — group/trip picker, participant selection, equal/exact/percent modes, multi-payer, `createSplitExpense`) and the **SplitBanner** read-only summary on the edit page (shown when a transaction is one leg of an existing split). Both belong to the Splits feature (already tracked at P3.6/P3.10), not Transactions — building a second, disconnected copy of group/participant UI here would fork logic that Splits needs to own.
- **Templates / "Quick Apply"** (`new/page.tsx`'s template dropdown, `applyTemplate`, `saveAsTemplate`, `FREE_TEMPLATE_LIMIT` paywall). A distinct, self-contained feature (its own data — `templates` table, `useTemplates`/`createTemplate`) that both platforms currently have zero support for; not required for a transaction to be creatable.
- **AI auto-categorization** (`useAutoCategorize`/`useLearnCategory`, entitlement-gated, calls an edge function to suggest + learn categories from free text). Category picking still works fully — the user just always picks manually this pass, same as a non-premium web user typing past the suggestion.
- **Edit-history audit modal** (`KebabMenu` → "View history", reads `transaction_audit`). The underlying data already exists (`updateTransaction` already writes audit rows on both platforms, verified in `LedgerRepository`), so this is a pure-UI follow-up, not blocked on any data-layer work — smaller than the others, worth a quick pass once the core CRUD is verified.
- **Deep-link prefill** (`?type=&amount=&desc=`, `?template=`, `?split=` query params on `new/page.tsx`). Web-only navigation convenience; native prefill from a notification/shortcut is its own concern (P4.4 Quick capture), not this screen.

## List (`transactions/page.tsx`)

- Header: h1 "Transactions" + "+ Add" button (→ new).
- Controls: a search input (matches note text OR any label name, case-insensitive `LIKE`) + a 4-way type filter chip row: All / Income / Expense / Transfer.
- Query (mirror, not literal SQL): all non-deleted transactions except `type = 'opening_balance'`, filtered by the search text and type, newest first, capped at 200 rows.
- Row = `TransactionTile` (see below), `href` to the edit screen. Empty state: "No matching transactions" (muted, in a card). Loading: skeleton rows.
- **Split rows are collapsed** on web (`collapseSplitRows`) so a split expense's per-leg ledger rows show as one tile with a paid/share badge — that collapsing logic belongs to the Splits feature (deferred above); this pass shows the raw per-account ledger rows uncollapsed, which is correct/faithful for non-split transactions (the overwhelming majority) and only visually differs for split expenses, which are their own deferred feature anyway.

### `TransactionTile` (shared row, port the logic not the exact CSS)

- **Avatar**: a filled circle, background = `avatarColor(seed)` (deterministic hash of the *title* string into a 7-color palette: `#b06a4f #5f7a52 #c08a3e #7a4a6b #2f6f6a #7c4a3a #9cae8e`), content = the title's first character, uppercased.
- **Title**: `merchantTitle(raw)` — if `raw` looks like a bank/UPI narration (`UPI/ASHISH ALA/1234/Payment`, i.e. splits on `/` and the first segment matches `upi|imps|neft|ach|bil|inft|rtgs|nach|pos` case-insensitively), extract the first alphabetic-looking segment after the prefix (max 34 chars); otherwise the raw string truncated to 40 chars. `raw` itself is `(description || labels || categoryName).trim()` from the list query, falling back to the transaction `type` if all empty.
- **Subtitle**: the full raw narration when it differs from the extracted title (wraps, never truncated); empty otherwise (tags fill that role instead).
- **Tags** (`txTags`): category name (skipped if "Uncategorised" AND there are labels), then each label — each rendered with a small icon (category vs label glyph is cosmetic, a single icon per tag is enough).
- **Account line**: the account name, its own line below tags (not inlined with the tags).
- **Amount**: sign is `−` for expense, `+` for income, none for transfer; color is positive-green for income, otherwise default text color; formatted through the hide-amounts-aware money formatter (same one used everywhere else — `useMoneyFmt`/`Prefs.amountsHidden`/`prefs.amountsHidden`).
- **Meta** (top-right, under amount): the date, short format (e.g. "Aug 5").

## New (`transactions/new/page.tsx`)

- If there are zero real accounts: show "Add an account first" + a link to Accounts' new screen, instead of a broken form.
- Type toggle: Expense / Income / Transfer, single-select chips. **Investment accounts** (`account.type` is `stocks` or `mutual_funds`) can only do transfers — if the selected account is an investment account, force `type = transfer` and disable the other two chips (with an explanatory line).
- **Amount / items**: for expense/income, a repeatable list of `{description, amount}` line items (default 1 row) — "Add item" appends a row; 2+ rows shows a running total above and a per-row remove (×) button. This is a **breakdown of one transaction's total into named parts** (e.g. splitting a grocery receipt into "Snacks" + "Vegetables"), unrelated to the deferred split-*expense* (multi-person) feature — don't conflate the two. For transfer, a single amount field (no items). Total = sum of item amounts (or the single transfer amount), shown large, colored by type (negative-red/positive-green/forest for transfer).
- **Account** chips (source account for expense/income, "from" for transfer) — every non-archived real account, each showing name + currency.
- **To account** chips (transfer only) — every other real account.
- **Cross-currency transfer**: if the to-account's currency differs from the from-account's, show a second amount field ("Amount received in {toCurrency}") — this is `to_amount` on the transaction, independent of the source amount; `fx_rate` is derived server/repo-side from the two (already implemented in `createTransaction`).
- **Category** (expense/income only): flat searchable list of categories filtered to the type's `kind` (income categories for income, expense categories for expense), parent categories with children shown as "Parent › Child". A plain filterable list/picker is a faithful port of `SearchSelect` here — it doesn't need to be the exact same fuzzy-match widget.
- **Payment method** (expense/income only, only shown if the selected account's type has any): chips, options = `account_type_payment_methods` joined to `payment_methods`, filtered to the selected account's `type`, defaults to the first one whenever the account changes.
- **Labels**: multi-select chip picker over existing labels, allowing free-text new ones (matches `LabelPicker` — type a name, press enter/comma to add if it doesn't already exist).
- **Note**: optional free text (encrypted at rest on web via `encryptForWrite` — that's a web-only field-level-crypto concern tracked under P4.5, not re-implemented here; store the plaintext note directly, matching how this codebase's existing `note` fields already work on mobile pre-P4.5).
- **Date**: date+time picker, defaults to now.
- Save: disabled unless an account is selected, total > 0, and (for transfer) a different-from-source to-account is selected. Calls `createTransaction` — transfer path passes `toAccountId`/`toAmount`; expense/income path passes `items` only when there are 2+ non-zero rows (a single row's amount goes on the transaction directly, matching `payload.length > 1 ? {items: payload} : {}}`). On success, go back to the list.

## Edit (`transactions/[id]/edit/page.tsx`)

- Loads the transaction by id, its existing `transaction_items` (falls back to a single synthetic item from `description`+`amount` if none exist — so the item-editor always has something to show), and its label names.
- Editable: type, account, amount/items (same item-editor as New; transfer edits a plain amount field instead), category, payment method, labels, **intent** (expense only — 3-way chip: Untagged / Need / Greed, stored on `transactions.intent`; this field does NOT appear on the New flow, only Edit — matches web exactly, don't add it to Create), note, date.
- Save calls `updateTransaction` with the changed fields (the repository's existing `Map<String,Any?>`/`[String: Sendable?]` patch convention — key presence, not just non-null value, decides whether a field is touched — already implemented and matches this exactly on both platforms).
- Row of actions: Save changes / Cancel (back to list) / Delete (destructive, confirm first — **single confirm, no cascade choice** here, unlike Accounts' delete: a transaction has no children to cascade, `removeTransaction` already soft-deletes the row + its items/labels together). Matches `useConfirm()`'s plain yes/no, not Accounts' two-button cascade-or-keep dialog.

## Data layer — gaps found 2026-08-05 (both platforms need these added; write logic already exists and is solid)

Both `LedgerRepository`s already have `watchAllTransactions()`, `createTransaction()`, `updateTransaction()` (full undefined-vs-null patch semantics + audit trail), `removeTransaction()` (soft-delete + items/labels) — this is real, already-correct Phase 2 work, not something this pass needs to fix. **Missing, needed for this screen:**
- `watchCategories()` — reactive `SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name`.
- `watchLabels()` — reactive `SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name`.
- `watchPaymentMethods()` — reactive join `account_type_payment_methods` × `payment_methods`, filtered client-side to the selected account's type (small, static-ish lookup table — no per-account-type parameterized watch needed).
- `watchTransactionLabelNames()` — reactive `transaction_id → [label names]` map (join `transaction_labels`×`labels`), used both by the list (tags) and by Edit (seeding the label picker).
- `items(transactionId)` already exists (one-shot); Edit needs it to seed the item editor.
