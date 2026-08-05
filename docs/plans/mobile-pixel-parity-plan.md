# Mobile Pixel-Parity & Production Plan

> Status: IN PROGRESS (2026-08-05). Scope: `apps/android` + `apps/ios` only — `apps/web` is untouched, ground truth. Written after direct inspection of the repo, not from `docs/mobile/TODO.md`'s claimed statuses (see §1 — those claims don't hold up).
>
> **Progress:** Phase A done (`docs/mobile/TODO.md` + `AUDIT_HISTORY.md` corrected). Phase B token generator done: `tools/parity/generate-tokens.mjs` parses `apps/web/app/globals.css` and emits `apps/android/app/src/main/java/com/sanvya/app/theme/{Color,Theme,Radius}.kt` + `apps/ios/App/Theme.swift`. This fixed one of Android's two compile-breaking dangling references (`SanvyaTheme` now real) and, as a side effect, caught that iOS's old hand-written `Theme.swift` was missing several tokens outright (`sidebar`, `accentHover`, `accentGhost`, `teal`, `sage`, `forest`, and notably **`warning`** — used for budget/insight warning states — wasn't defined at all). `SanvyaNavHost` (Android's other dangling reference) is real screen-building work, not a token fix — still open, tracked in Phase C. Per-screen source specs (the rest of Phase B) and Phase C/D screen work are next.

## 0. Bottom line

`docs/mobile/TODO.md` currently marks ~18 Android "Phase 3 UI slice" tasks (P3.1a–P3.18a) as `DONE`, each citing a specific file (`DashboardScreen.kt`, `AccountsScreen.kt`, `TransactionsScreen.kt`, etc.). **None of those files exist.** The Android app has ViewModels and repositories, but zero Compose screens, no navigation graph, and no theme — `MainActivity.kt` calls `SanvyaTheme {}` and `SanvyaNavHost()`, neither of which is defined anywhere in the tree. The Android app does not compile today.

iOS is in much better shape — every screen the TODO claims exists actually does — but the files are thin (65–185 lines each, vs. web equivalents that run 500+ lines plus extracted components) and hand-approximate the design (eyeballed values) rather than being read and translated from the actual web source. There is no source-derived spec and no verification step anywhere in the workflow, so "looks like web" has never actually been checked against the real component code for any screen on either platform.

So the real task isn't "polish existing native UI to match web" — for Android it's "build the UI layer that was reported built but wasn't," and for both platforms it's "put a verification mechanism in place so DONE means what it says." Everything below is scoped around that.

## 1. Ground-truth audit (verified 2026-08-05, by direct file inspection)

| Area | TODO.md claim | Actual state |
|---|---|---|
| Android Compose screens (Dashboard, Accounts, Transactions, Budgets, Goals, Splits, Receipts, Statements, Investments, Credit Cards, Assistant, Walkthrough, Login, Loans) | All `DONE`, ~18 tasks, named files cited | None exist. Only `SettingsScreen.kt` (204 lines) is real. `apps/android/app/src/main/.../ui/` otherwise contains only ViewModels. |
| Android navigation | Implied working (`MainActivity` DONE-adjacent) | `SanvyaNavHost()` referenced, not defined. Package `com.sanvya.app.ui.navigation` doesn't exist. |
| Android theme | Implied working | `SanvyaTheme` referenced, not defined. No color/theme/typography file exists anywhere in `apps/android`. |
| Android build | — | Will not compile as-is (dangling references above). |
| iOS Compose-equivalent screens | All `DONE` | All files exist and are wired to ViewModels. Real, but thin — e.g. `DashboardView.swift` 179 lines vs. web `app/page.tsx` 501 lines; `CreditCardsView.swift` hand-inlines the card face as approximate SwiftUI shapes rather than a ported, reusable component with brand-specific network styling. |
| Design tokens ("generated tokens keep visual parity" — plan §9) | Implied a generator exists | No generator exists anywhere in `tools/`. `packages/ui-tokens` (the one shared TS token source) is itself **stale** — its `clay50` background (`#FAF6F1`) doesn't match production web's actual `--bg: #efe9df` in `apps/web/app/globals.css`. iOS's `Theme.swift` was hand-matched against the real web CSS (spot-checked, matches), not against `ui-tokens`. Android has no token file of any kind. |
| Visual verification process | Screenshots "in the commit/PR" (plan §7 Done-when) | No process at all — screens were built from memory/approximation, not from reading the actual web `.tsx`/CSS. No spec artifact exists to check a native screen against. |
| Phase 2 data layer (sync connector, auth, quarantine) | "Code complete, BLOCKED (TP L3)" on both platforms | Consistent with what's on disk — repositories exist, but the integration test harness (P2.7) needs a human-provisioned test Supabase + PowerSync project, which hasn't happened. So even iOS's UI is running against a data layer that's never been proven against a real sync round-trip. |
| Bundle IDs / min OS / Universal Links domain | Flagged as placeholders in TODO.md | Confirmed still placeholder (`com.sanvya.app` / `com.sanvya.app.ios`, no real domain) — blocks store submission regardless of UI work. |

**Root cause:** prior agent sessions marked tasks DONE without the build/test evidence the plan's own protocol requires ("DONE requires the task's Done-when to have passed — show the output," `docs/mobile/TODO.md` rules). Nothing enforced that rule. This has to be fixed at the process level, not just the code level, or it will happen again.

## 2. What "pixel-to-pixel + full functionality" actually requires

Three things have to exist that don't today:

1. **One source of truth for visual tokens**, consumed (not approximated) by both native platforms.
2. **A source-translation loop, not a screenshot loop**: for each screen, read the actual web `.tsx` file and every CSS class/token it uses, write down the exact component tree, spacing/color/radius/typography values, and states/conditional logic it implements, then port *that spec* into Compose/SwiftUI — not a redraw from memory. Screenshots can't give exact values (you're eyeballing pixels) and only show whatever state happened to be on screen, so they're a poor primary mechanism; a lightweight side-by-side screenshot stays as a final sanity check, not the main verification step. Note web and native don't map 1:1 everywhere (no notch/home-indicator/nav-bar safe areas on web, flexbox vs. Compose/SwiftUI layout) — nav chrome and safe areas follow platform convention, everything else follows the source spec.
3. **Honest status tracking** — TODO.md entries only flip to DONE with the evidence the protocol already demands.

## 3. Phased plan

### Phase A — Fix the record (½–1 day, do first, low risk)
- Correct `docs/mobile/TODO.md`: flip the ~18 falsely-marked Android P3.x rows back to `TODO`, with a one-line note ("file does not exist, verified 2026-08-05"). Leave iOS rows as DONE but add a caveat row noting they're unverified for pixel/data fidelity pending Phase B.
- Add a dated entry to `AUDIT_HISTORY.md`'s Mobile change log documenting this discovery (per `CLAUDE.md` doc rules).
- Add this plan doc's screen-by-screen tracking table (§5/§6 below) as the new source of truth for "is this screen actually done," separate from the coarse phase table.

### Phase B — Build the parity infrastructure (2–3 days, blocks everything after)
This is the part that was always missing, and to build once so it can be used for every task in C/D:

- **Token source of truth:** treat `apps/web/app/globals.css` `:root`/`.dark` blocks as canonical (it's what users actually see). Either fix `packages/ui-tokens` to match it exactly and make it the generator input, or generate directly from `globals.css`. Either way, write `tools/parity/generate-tokens.mjs` that emits:
  - `apps/android/app/src/main/.../theme/Color.kt` + `Type.kt` + `Theme.kt` (Compose `MaterialTheme` wiring, light/dark)
  - `apps/ios/App/Theme.swift` (replace the hand-written version)
  - A checked-in diff check (CI-runnable) so future token edits in `globals.css` regenerate both, and drift is a `git diff`, not a guess.
- **Per-screen source spec:** for every screen in the parity table below, read the actual web `.tsx` (and any extracted components it uses, e.g. `CreditCard.tsx`, `TransactionTile`) plus the CSS classes/tokens it applies, and write a short spec — component tree, exact spacing/color/radius/typography values (as tokens, not raw hex), states/conditional rendering, hooks/data calls. This spec (not a screenshot) is what gets ported and what a screen is checked against. Store under `docs/mobile/screen-specs/<screen>.md`.
- **Component inventory:** list web's reusable primitives that appear across screens (`.card`, `.btn`, `.chip`, `TransactionTile`, `CreditCard` face, dashboard tiles, empty states) and require each to be built **once** as a native component (Composable / SwiftUI View) and reused — not re-inlined per screen (the current iOS `CreditCardsView` problem). Each of these gets its own source spec too, since it's shared across many screens.
- **Per-screen Done-when checklist** (replaces the vague "screenshots in the PR"): matches its source spec — every value traced to a token, not eyeballed ✓; component reuse (no inline re-implementation) ✓; all states from the spec (loading/empty/error) present ✓; functional round-trip against a real local DB write ✓; a final side-by-side screenshot at the same viewport as a sanity check (platform chrome differences expected and fine) ✓.

### Phase C — Android: build the missing UI layer
Nothing here is "polish" — it's first builds. Sequence mirrors web's own feature index (same order the plan already specified, since ViewModels for these already exist and are the right foundation to build screens against):

1. Fix the compile break: real `SanvyaTheme` (from Phase B generator) + real `SanvyaNavHost` with a nav graph covering every screen below.
2. S1 — Dashboard, Accounts (+edit/create), Transactions (+create), Login/Walkthrough (guest→OTP→Google).
3. S2 — Budgets, Goals, Cashflow, Credit Cards (built as a real reusable card-face component, not inline), Loans/Recurring.
4. S3 — Splits/Groups, UPI settle-up (real `Intent` + chooser, per plan).
5. S4 — Receipt scan (CameraX + ML Kit + bounding boxes), Statement import.
6. S5 — Investments, Insights, Statements.
7. S6 — Assistant.
8. R1 retrofit (state preservation — `rememberSaveable`/`SavedStateHandle`/`WindowSizeClass`) applied as each screen is built, not bolted on after, since it's cheaper that way and was explicitly called out as a retrofit debt already once.

Each screen exits this phase only when it passes the Phase B checklist.

### Phase D — iOS: bring existing screens to real parity
Not a rebuild — these files exist and are wired to ViewModels — but every screen needs its source spec written (Phase B) and then gets checked against it, since none were built that way originally. Expect real gaps given the line-count disparity vs. web: likely missing states, secondary content web shows (e.g., dashboard has more than a net-worth card + quick actions + list — the spec for `app/page.tsx`'s other ~300 lines will show what iOS is missing), and inline-approximated components (Credit Card face is the known one; audit for others, e.g. dashboard charts, insights charts — must go through the same money-hiding/formatting rules as web, not reimplemented ad hoc).

### Phase E — Data layer + native surfaces (blocks true production readiness on both platforms)
- **P2.7 (test Supabase + PowerSync instance)** — needs you: infra + credentials + a first real on-device sync run. Nothing in Phase 2 (sync connector, auth, quarantine/repair) can be called done without it, and it's a prerequisite dependency for a lot of Phase 4/5 work per the existing plan's dependency graph.
- Phase 4 native surfaces still fully TODO on both platforms: push notification UI/deep links, widgets, iOS Live Activities, quick capture, biometric lock + field-level crypto (with the required web↔android↔ios crypto round-trip check before any mobile write of sealed fields — this one's flagged `[H]` for a reason, don't rush it).

### Phase F — Release readiness
- RevenueCat entitlements wiring (must match web's gate map exactly, not be re-decided).
- Real bundle IDs + Universal Links domain — needs your decision, currently blocking store-prep tasks.
- Fastlane CI/CD, Play/TestFlight staged rollout, store metadata.
- Launch gate: full test-plan exit criteria (security sweep, sync fault-injection suite, accessibility pass, hi/nl review, real-device smoke test).

## 4. Suggested sequencing

Phase A and B are prerequisites — skipping B is exactly how we got here (native screens built with nothing to check them against). Recommend: A → B, then C (Android) and D (iOS) can run in parallel since they're independent codebases, both gated by the same Phase B checklist. E's P2.7 is on the critical path for both and needs you specifically (infra/creds) — worth kicking off in parallel with C/D rather than after, since it's pure waiting time otherwise. F only makes sense once C/D/E are substantially through.

## 5. Open decisions that need you

- Do you want the token source of truth to be `apps/web/app/globals.css` directly, or should `packages/ui-tokens` be fixed and made canonical instead? (Recommend globals.css — it's what's actually shipping.)
- P2.7: can you provision a test Supabase project + PowerSync instance now? This has been blocking since 2026-07-31 and gates a lot of downstream work.
- Real bundle IDs and the Universal/App-Links domain — still placeholders, needed before Phase F.
- Min OS versions (Android minSdk 26 / iOS target proposed in the skeletons) — confirm or revise.

## 6. What I'd do first, if you sign off

1. Correct `docs/mobile/TODO.md` + `AUDIT_HISTORY.md` entry (Phase A) — cheap, immediate, stops future sessions building on a false status.
2. Build the token generator + write the per-screen source specs (Phase B) — this is the one-time investment (reading web's real `.tsx`/CSS, not screenshots) that makes every screen after it actually verifiable against exact values and logic.
3. Fix Android's compile break and start S1 (Dashboard/Accounts/Transactions/Login) — the highest-leverage gap since Android currently has *no* working UI at all.
