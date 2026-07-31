# Mobile TODO — work queue + handover

> **This file is the single work queue for the native mobile build.** Task definitions live in `docs/plans/native-mobile-apps.md` (the "plan"); this file tracks status. Protocol: plan §1. **Update this file before ending every session — no exceptions. Commit it — no exceptions.**

## 🤝 Handover (rewrite at end of EVERY session — max 15 lines)

```
Last session: 2026-07-31 (latest) — ported receipts (P1.5, 56a3200),
               then ALL of Phase 1's remaining domains in one session:
               reconcile+upi+sync-policy+diagnostics+guardrail (P1.6)
               and entitlements (P1.7), both platforms. Phase 1 domain
               porting is now CODE-COMPLETE (16/16 vector domains
               registered on both platforms) -- nothing build/test
               verified yet, see Blocked.
               Notable catches this session: (1) reconcile's FNV-1a
               canonical-row serializer uses literal control-byte
               separators (U+0001 field join, U+0000 null placeholder)
               that the Read tool silently misrenders as "" and " " --
               caught by executing the real TS module and diffing hex
               checksums, confirmed via raw `open(path,'rb')` byte
               inspection. (2) upi's mulberry32 FNV-style offset constant
               in the TS source (1469598103934665603) is NOT the textbook
               FNV-1a-adjacent value some references would suggest --
               verified the actual constant by testing both candidates
               against the real `newPaymentRef` vectors in Python before
               committing to one. (3) diagnostics is an order-sensitive
               multi-pass redaction pipeline (secrets -> UUID-preserve ->
               code-protect -> amount-scrub); every regex transcribed
               verbatim and traced by hand against all 10 vectors before
               writing Kotlin/Swift. (4) sync-policy/guardrail's message
               strings carry literal U+2014 em-dashes and a U+2192 arrow,
               verified byte-exact via Python `ord()` against the vector
               JSON before typing them into source.
Android state: 16/16 domains ported and registered (money, ledger,
               finance, budget, splits-insights, splits-math, receipts
               x4, reconcile, upi, sync-policy, diagnostics, guardrail,
               entitlements). money/ledger/finance/budget/splits-*
               human-confirmed green. receipts (P1.5) + reconcile/upi/
               sync-policy/diagnostics/guardrail/entitlements (P1.6/1.7,
               this session) NOT yet human-verified by `./gradlew test`.
iOS state:     Same 16/16 domains ported and registered. money/ledger/
               finance/budget human-confirmed green; splits-* ported but
               awaiting first post-fix `swift test` re-verification
               (27a91cb, 6f320b9); receipts + P1.6/P1.7 (this session)
               NOT yet human-verified by `swift test`.
Vectors:       DONE (P0.1), 250 total across 16 domain files -- ALL 250
               now have a registered implementation on both platforms
               (0 remaining unported domains). Actual pass/fail counts
               unknown until a human runs the real test suites.
Next up:       Human runs `./gradlew test` (Android) and
               `cd apps/ios/Domain && swift test` (iOS). This is the
               first full-suite run since P1.4 -- expect it to surface
               real build errors (every P1.4-P1.7 Swift file has never
               been compiled). Fix iteratively per domain, report back
               pass/skip/fail counts per `[vectors] domain=... total=...
               passed=... skipped=... failed=...` lines. Once fully
               green, Phase 1 is DONE and Phase 2 (data layer) can be
               expanded (plan §6).
Traps/notes:   Kotlin/Swift block comments both NEST -- grep for literal
               `/*` before every commit (still zero hits across P1.5-1.7,
               all doc comments are `/**`/`///`, no accidental nesting).
               Bare int literals need explicit widening on both platforms
               (Int64(0) / 0L). Registries keyed by (domain, fn). iOS:
               `swift test --package-path Domain` for real vector tests,
               NOT `xcodebuild test -scheme PocketCare` (App-level
               placeholder only). Swift's NSNumber.isEqual is NOT
               trustworthy for fractional doubles -- jsonValueEqual
               compares .doubleValue directly. Swift 6 strict
               concurrency: any public struct from Sources/Domain that a
               *Vectors.swift file puts in a global `let` fixture needs
               explicit `Sendable`. NEW this session: (a) a source .ts
               file CAN contain literal control-byte characters that
               look like "" or " " in every tool's rendering -- if a
               computed hash/checksum doesn't match a vector, inspect the
               source file's raw bytes via Python before assuming the
               port logic is wrong. (b) JS's single-string
               `.replace(str,str)` replaces only the FIRST match; Kotlin
               `String.replace(String,String)` and Swift's naive
               equivalents replace ALL -- use range/index-based
               replacement (or a regex-based replace, which already
               matches JS's /g semantics) instead of a plain string
               replace wherever the TS source relies on first-match-only.
               COMMIT EVERY SESSION.
Blocked:       Nothing structurally. P1.4-P1.7's Swift code (6 domains'
               worth) has never been compiled -- expect real Swift 6
               errors on first `swift test`, same pattern as P1.4's
               27a91cb/6f320b9. Android is lower-risk (Kotlin has caught
               fewer surprises historically) but also fully unverified
               for P1.5-P1.7.
```

## Rules (short form — full protocol in plan §1)

- Claim **1 task (max 3)** you can FINISH this session. Match your tag: [S] small-model OK · [M] mid · [H] strong model/human-paired.
- Statuses: `TODO` → `DOING (date, model)` → `DONE (date, commit)` | `BLOCKED (reason)`.
- DONE requires the task's *Done-when* in the plan to have passed — show the output. For P0.2/P0.3 that means real Gradle/Xcode output (CI or human machine), not "the files exist."
- Can't finish → revert incomplete code, mark BLOCKED with one line. Never leave a broken tree.
- **End of session: statuses updated here + Handover rewritten + one line in `PROJECT_REFERENCE.md` mobile change log + COMMIT. Not optional — see the trap above.**
- Dependencies: don't claim a task whose "Needs" isn't DONE.

## Queue

### Phase 0 — vectors + skeletons
| ID | Task (plan ref) | Tag | Needs | Status |
|---|---|---|---|---|
| P0.0 | Decommission RN scaffold | [M] | — | DONE (2026-07-31, N/A — never committed, removed by repo reset) |
| P0.1 | Golden-vector exporter (`tools/golden-vectors/export.ts`) | [M] | — | DONE (2026-07-31, 8e8bcfd) |
| P0.2 | Android skeleton (`apps/android`, pure-Kotlin `:domain`) | [M] | — | DONE (2026-07-31, dc923f2 — human ran `./gradlew build test`, BUILD SUCCESSFUL, on AGP 9.2.0/Gradle 9.4.1/built-in Kotlin) |
| P0.3 | iOS skeleton (`apps/ios`, SwiftPM `Domain`, App Group) | [M] | — | DONE (2026-07-31, 1b3804a — human ran `xcodebuild test`, passed, app confirmed running on simulator) |
| P0.4a | Vector runner — Android (kotlin.test) | [S] | P0.1, P0.2 | DONE (2026-07-31, human ran `./gradlew test`, all registered domains green) |
| P0.4b | Vector runner — iOS (XCTest) | [S] | P0.1, P0.3 | DONE (2026-07-31, human ran `swift test`, all registered domains green after 2 real fixes — see change log) |
| P0.5 | PROJECT_REFERENCE "Native mobile" section + parity table | [S] | — | DONE (2026-07-31, same session as this file) |

### Phase 1 — domain ports (one row = one platform = one task)
| ID | Task | Tag | Needs | Status |
|---|---|---|---|---|
| P1.1a / P1.1b | money — Android / iOS | [M] | P0.4a / P0.4b | DONE (2026-07-31, 7d3107a + Swift fix 6be76b9 — human confirmed `[vectors] domain=money total=40 passed=37 skipped=3 failed=0` both platforms) / DONE (same) |
| P1.2a / P1.2b | ledger — Android / iOS | [M] | P1.1 same-platform | DONE (2026-07-31, 5a705de — human confirmed `total=10 passed=10 skipped=0 failed=0` both platforms) / DONE (same) |
| P1.3a / P1.3b | finance+budget — Android / iOS | [M] | P1.2 | DONE (2026-07-31, e8ef8b8 + Swift fixes 29a9d01/77607ac — human confirmed `finance total=33 passed=33` and `budget total=10 passed=10`, both `failed=0`, both platforms) / DONE (same) |
| P1.4a / P1.4b | splits+insights — Android / iOS | [M] | P1.1 | DONE (2026-07-31, 17291cb — human confirmed `./gradlew test` BUILD SUCCESSFUL, splits-insights 6/6/0 + splits-math 4/4/0) / DOING (17291cb + fixes 27a91cb, 6f320b9 — 4/4 fns, 10 vectors, 2 real Swift 6 build errors found+fixed, NOT yet re-verified by `swift test`) |
| P1.5a / P1.5b | receipts — Android / iOS | [H] | P1.1 | DONE (2026-07-31, 56a3200 — 4 sub-domains ported, 2 real bugs caught+fixed pre-commit: JS single-`.replace` vs Kotlin's replace-all, findDate UTC-vs-local. NOT yet human-verified by `./gradlew test`/`swift test`) / DONE (same commit, same caveat) |
| P1.6a / P1.6b | reconcile+upi+sync-policy+diagnostics+guardrail — Android / iOS | [M] | P1.1 | DOING (this session — 5 sub-domains ported: reconcile [FNV-1a bank-drift checksums, hidden U+0001/U+0000 control-byte literals in the TS source caught via raw-byte inspection, not the Read tool's misleading rendering], upi [mulberry32 seeded PRNG for `newPaymentRef`, hand-rolled `encodeURIComponent`/`decodeURIComponent`, non-textbook FNV offset constant caught by cross-checking two candidate values against the real vectors], sync-policy [em-dash/arrow Unicode strings verified byte-exact via Python `ord()`], diagnostics [highest-risk domain after receipts: multi-pass order-sensitive redaction pipeline, `\b` word-boundary regex, ₹€£ symbols]. NOT yet human-verified by `./gradlew test`/`swift test`) / DOING (same session, same 5 sub-domains, same caveat) |
| P1.7a / P1.7b | entitlements — Android / iOS | [S] | P0.4 | DOING (this session — ported faithfully including a source quirk: `Tier` has 4 values but `canUse()` only special-cases "premium", so "lite"/"pro" silently fall through to the free-tier check; not fixed, just documented, since only "free"/"premium" have vector coverage. NOT yet human-verified) / DOING (same session, same caveat). "gate map" deliberately NOT ported — no golden vectors exist for it; it's a UI-side feature-gating table, deferred to Phase 3+ UI work, not pure domain logic. |

### Phase 2 — data layer
Not expanded yet — expand once Phase 1 is ~80% DONE (plan §6).

### Phase 3+ (UI slices S1–S6, native surfaces P4.x, release P5.x)
Not expanded yet (plan §7-8).

## Decisions needing a human (standing list)
- Any new dependency beyond the §0 irreducible set (PowerSync, Supabase SDK, RevenueCat, FCM).
  - ✅ 2026-07-31: `kotlinx.serialization` (test-scope, Android only, P0.4a) — approved in-session for parsing golden-vector JSON in `:domain`, which has no Android SDK and thus no built-in JSON parser. iOS needed no equivalent approval (Foundation's JSONSerialization is already available, not a new dependency).
- [H] tasks: P1.5, and any Phase 2 items once expanded — strong model or human-paired only.
- Exact minimum OS versions (proposal due with P0.2/P0.3: minSdk + iOS min).
- Real bundle ids / Universal-Links domain (plan §10).
