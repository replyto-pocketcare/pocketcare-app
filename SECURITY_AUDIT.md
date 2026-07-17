# PocketCare — Security Audit & Remediation Plan

**Date:** 2026-07-13
**Scope:** monorepo at repo root — `apps/web` (Next.js), `supabase/` (Postgres migrations + Edge Functions), `packages/core/crypto`, `scripts/`, repo config.
**Context:** Financial tracking app handling user PII (emails, names), transactions, balances, payment records, and end-to-end-encrypted fields. Standard: highest bar for data protection.

This file is the security reference/audit for the repo. Each finding has: what/where, why it matters, and a **self-contained fix prompt** written so a lower-capability LLM can execute it without re-deriving context. Work findings top-down (CRITICAL → LOW).

---

## Severity summary

| # | Severity | Finding | Location |
|---|----------|---------|----------|
| C1 | 🔴 CRITICAL | Support private-key Shamir shares committed to git | `support-key/officer-{1,2,3}.share` |
| C2 | 🔴 CRITICAL | Admin server actions have no authorization check | `apps/web/src/admin-actions.ts` |
| H1 | 🟠 HIGH | Wildcard CORS (`*`) on all authenticated Edge Functions | `supabase/functions/*/index.ts` |
| H2 | 🟠 HIGH | `market-sync` has no caller authentication | `supabase/functions/market-sync/index.ts` |
| H3 | 🟠 HIGH | Blanket table grants to `anon` role | `supabase/migrations/0001_init.sql` |
| M1 | 🟡 MEDIUM | Non-atomic quota + credit updates (race → limit bypass) | `assistant`, `razorpay-webhook`, `redeem-coupon` |
| M2 | 🟡 MEDIUM | Promo/coupon redemption TOCTOU (double-redeem) | `supabase/functions/redeem-coupon/index.ts` |
| M3 | 🟡 MEDIUM | Group members can be added without consent | `supabase/fix_rls.sql`, `0014_relax_sgm_rls.sql` |
| M4 | 🟡 MEDIUM | Non-constant-time webhook signature compare | `supabase/functions/razorpay-webhook/index.ts` |
| L1 | 🟢 LOW | `security_audit` allows self-authored rows | `supabase/migrations/0021_security.sql` |
| L2 | 🟢 LOW | Prod build ignores type/lint errors | `apps/web/next.config.js` |
| L3 | 🟢 LOW | Regex-only LLM guardrail (bypassable) | `supabase/functions/assistant/index.ts` |
| L4 | 🟢 LOW | Verify `.env` / secrets never entered git history | repo-wide |

---

## 🔴 C1 — Support private-key Shamir shares are committed to git

**Where:** `support-key/officer-1.share`, `officer-2.share`, `officer-3.share` (all three tracked by git; confirmed via `git ls-files`).

**Why it's critical:** These are the Shamir shares of the SUPPORT private key used to unwrap user DEKs and decrypt user financial fields under consent grants. The key was split with **threshold 2**, and **all 3 shares are in the repo** — anyone with repo read access (past/present collaborators, CI, a leaked clone, a fork) can reconstruct the private key and defeat the entire consented-support encryption model. `scripts/gen-support-key.ts` explicitly says *"NEVER commit the shares"* and *"any M reconstruct the key."* This nullifies the zero-trust design.

**Fix prompt (for the LLM):**
```
The files support-key/officer-1.share, officer-2.share, officer-3.share contain
secret Shamir shares of a private key and must never be in version control.

1. Remove them from tracking without deleting local copies:
     git rm --cached support-key/officer-1.share support-key/officer-2.share support-key/officer-3.share
2. Add to .gitignore a new section:
     # Support key material — NEVER commit
     support-key/
     *.share
3. Commit this change.
4. Print a REQUIRED MANUAL FOLLOW-UP block (do not attempt these yourself), stating:
   - The committed key is permanently compromised. Regenerate a brand-new
     support keypair on an offline machine via scripts/gen-support-key.ts.
   - Rotate NEXT_PUBLIC_SUPPORT_PUBLIC_JWK to the new public key.
   - Because the OLD public key wrapped existing user DEKs-for-support, any
     already-issued support_grants must be revoked/re-issued against the new key.
   - Purge the old shares from git history (git filter-repo or BFG) and force-push,
     since removing from HEAD does not remove them from history.
Do NOT print the contents of any .share file.
```

---

## 🔴 C2 — Admin server actions perform no authorization check

**Where:** `apps/web/src/admin-actions.ts` — `getAdminDashboardStats()`, `getAdminUsers()`, `getAdminFeedback()`.

**Why it's critical:** These are Next.js `"use server"` actions that build a **service-role** Supabase client (`SUPABASE_SERVICE_ROLE_KEY`, bypasses RLS) and return every user's email, display name, total income, and all bug-report reporter emails. The **only** admin gate is `AdminShell.tsx`, which runs **client-side** (`"use client"`, `useEffect`). Server actions are directly invokable POST endpoints — an attacker who is merely signed in (or unauthenticated, depending on action exposure) can call the action and exfiltrate the entire user table. Client-side checks are not security.

**Fix prompt (for the LLM):**
```
File: apps/web/src/admin-actions.ts. These "use server" actions use the service
role and currently trust the client to gate access. Add a SERVER-SIDE admin check
to every exported action before any data access.

1. Create an internal async helper `assertAdmin()` in this file that:
   a. Reads the caller's session server-side from the auth cookie. Use the
      @supabase/ssr server client (createServerClient) with Next's cookies(), NOT
      the service-role client, to get the authenticated user via auth.getUser().
      If there is no user, throw new Error("Unauthorized").
   b. Using the service-role client, query pocketcare_admin.admins (or the
      pocketcare.admins view) for a row where user_id = <caller id>. If none,
      throw new Error("Forbidden").
   c. Return the caller's user id.
2. Call `await assertAdmin()` as the FIRST line inside the try block of
   getAdminDashboardStats, getAdminUsers, and getAdminFeedback.
3. Keep the existing fail(e) pattern so errors return {ok:false,error} — but for
   the auth failures, return a generic "Forbidden" without leaking details.
4. Do not remove the client-side AdminShell check; it stays as a UX redirect only.
Requires @supabase/ssr; if not installed, add it to apps/web/package.json.
```

---

## 🟠 H1 — Wildcard CORS on authenticated Edge Functions

**Where:** every `supabase/functions/*/index.ts` uses `"Access-Control-Allow-Origin": "*"` (8 functions).

**Why it matters:** These functions accept a user's `Authorization` bearer token. `*` origin lets any website script call them with a token present in the victim's context and read the JSON response. Combined with tokens in browser storage, this widens CSRF/token-abuse surface. Financial endpoints should allow only the app's own origin(s).

**Fix prompt (for the LLM):**
```
In every file under supabase/functions/*/index.ts that defines a CORS object with
"Access-Control-Allow-Origin": "*", replace the wildcard with an allow-list echo:

1. Add a helper (or inline) that reads an env allow-list:
     const ALLOWED = (Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",").map(s=>s.trim()).filter(Boolean);
2. Compute the response origin from the request:
     const origin = req.headers.get("Origin") ?? "";
     const allowOrigin = ALLOWED.includes(origin) ? origin : (ALLOWED[0] ?? "");
3. Build CORS per-request with:
     "Access-Control-Allow-Origin": allowOrigin,
     "Vary": "Origin",
   keeping the existing Allow-Headers/Allow-Methods.
4. Ensure the OPTIONS preflight and all json() responses use this per-request CORS.
Do this for: assistant, split-invite, split-invite-accept, market-sync,
redeem-coupon, razorpay-webhook, razorpay-subscription, razorpay-credits,
razorpay-cancel. Document ALLOWED_ORIGINS in DEPLOY.md (comma-separated prod +
localhost dev origins). razorpay-webhook is server-to-server and may keep no CORS.
```

---

## 🟠 H2 — `market-sync` has no caller authentication

**Where:** `supabase/functions/market-sync/index.ts`. Unlike `assistant`, it never validates a JWT or a shared secret; it just runs the service-role sync. If deployed with `--no-verify-jwt` (as the webhook is) or callable, anyone can trigger it to burn the shared Alpha Vantage budget (DoS of market data) or probe holdings demand.

**Fix prompt (for the LLM):**
```
File: supabase/functions/market-sync/index.ts. It is a scheduled/cron job that
must not be publicly triggerable. Add a shared-secret gate:

1. Near the top of the handler (after OPTIONS handling), read:
     const cronSecret = Deno.env.get("MARKET_SYNC_SECRET");
     const provided = req.headers.get("x-cron-secret");
   If cronSecret is unset OR provided !== cronSecret, return
   json({ error: "Unauthorized" }, 401) immediately.
2. Use a constant-time comparison for the secret (compare equal-length byte
   arrays; if lengths differ, still return 401).
3. Update DEPLOY.md and the scheduler config to send the x-cron-secret header,
   and note to set MARKET_SYNC_SECRET. Recommend deploying with default
   verify_jwt ON as defense-in-depth unless the scheduler cannot send a JWT.
```

---

## 🟠 H3 — Blanket table grants to the `anon` role

**Where:** `supabase/migrations/0001_init.sql` (and several later migrations): `grant all on all tables in schema pocketcare to anon, authenticated, service_role;` plus per-table `grant all ... to anon`.

**Why it matters:** RLS is the only thing standing between the `anon` (pre-login) API role and every row. That's a single-control design: any table shipped **without** an RLS policy, or any policy regression, is instantly world-readable/writable through PostgREST. For financial data, `anon` should have no table reach at all unless a feature explicitly needs it.

**Fix prompt (for the LLM):**
```
Goal: remove standing table privileges from the `anon` Postgres role in the
pocketcare schema, since anonymous (pre-auth) users should not reach user data.
Create a NEW migration file supabase/migrations/0029_tighten_anon_grants.sql:

1. set search_path to pocketcare, public;
2. REVOKE ALL on all tables and sequences in schema pocketcare FROM anon.
   (revoke all on all tables in schema pocketcare from anon; same for sequences.)
3. Also revoke execute on all functions in schema pocketcare from anon, EXCEPT
   any function that genuinely must run pre-login (e.g. invite/join flows). List
   each retained grant explicitly with a comment justifying it.
4. Keep grants for `authenticated` and `service_role` unchanged.
5. Before finalizing, search the codebase for supabase clients created WITHOUT a
   user session (anon key, no auth) that hit pocketcare tables; list them so a
   human can confirm nothing legitimately depends on anon table access. Guest
   mode uses Supabase anonymous AUTH (a real authenticated user), so it is
   unaffected by revoking the `anon` role — call that out.
Do not weaken any existing RLS policy; this migration only narrows GRANTs.
```

---

## 🟡 M1 — Non-atomic counter updates enable limit bypass

**Where:**
- `supabase/functions/assistant/index.ts` — reads `monthly_quota_used`, then `update(used + 1)`.
- `supabase/functions/razorpay-webhook/index.ts` — reads `purchased_quota_remaining`, then upserts `current + credits`.
- `supabase/functions/redeem-coupon/index.ts` — `applyComp` reads then writes entitlements.

**Why it matters:** Read-modify-write over network races. Concurrent assistant calls can each read the same `used` value and both succeed past quota; concurrent webhook deliveries (Razorpay retries) can double-count or lose credits.

**Fix prompt (for the LLM):**
```
Replace read-then-write counter updates with atomic DB operations.

1. Create migration supabase/migrations/0030_atomic_counters.sql defining
   security-definer RPCs in schema pocketcare:
   - increment_quota_used(p_user uuid) returns void: UPDATE entitlements
     SET monthly_quota_used = monthly_quota_used + 1 WHERE user_id = p_user;
   - add_purchased_credits(p_user uuid, p_delta int): UPDATE ... SET
     purchased_quota_remaining = coalesce(purchased_quota_remaining,0) + p_delta
     WHERE user_id = p_user;
   Grant execute to service_role only.
2. In assistant/index.ts, replace the .update({ monthly_quota_used: used+1 }) with
   a call to supabase.rpc("increment_quota_used", { p_user: user.id }).
   Also enforce quota atomically: the SELECT-check-then-increment should be a
   single RPC that decrements and returns whether the call was allowed; refuse if
   not allowed. Implement that as a consume_quota(p_user) RPC returning boolean.
3. In razorpay-webhook credits handling, replace the read + upsert with
   supabase.rpc("add_purchased_credits", { p_user: row.user_id, p_delta: credits }).
Keep existing idempotency guards (the payments status flip) intact.
```

---

## 🟡 M2 — Promo/coupon redemption is TOCTOU-racy

**Where:** `supabase/functions/redeem-coupon/index.ts`. It checks `promo_redemptions` for an existing row, then inserts, then increments `redeemed_count` with a plain read-free update — but the existence check and insert aren't atomic, and `max_redemptions` is checked before a non-atomic count bump. Concurrent requests can double-redeem or exceed the cap.

**Fix prompt (for the LLM):**
```
File: supabase/functions/redeem-coupon/index.ts. Make redemption atomic and
idempotent at the database level.

1. Add a UNIQUE constraint on promo_redemptions(code, user_id) and on coupons
   redeemed state, via a new migration, if not already present.
2. Rely on the unique constraint instead of the SELECT-then-INSERT check: attempt
   the INSERT and treat a unique-violation error as "already redeemed" (return the
   friendly message). Remove the pre-check SELECT race window.
3. For max_redemptions, replace the read-free increment with a conditional atomic
   update via RPC: UPDATE promo_codes SET redeemed_count = redeemed_count + 1
   WHERE code = p_code AND (max_redemptions IS NULL OR redeemed_count < max_redemptions)
   RETURNING 1; if no row returned, the cap was hit — refuse and roll back the
   redemption insert.
4. Wrap the per-user reward-coupon path the same way (single-flight update guarded
   by redeemed_at IS NULL).
```

---

## 🟡 M3 — Group members can be added without their consent

**Where:** `supabase/fix_rls.sql` and `0014_relax_sgm_rls.sql` relaxed the `split_group_members` INSERT policy to allow the group creator to add **any** `user_id`. `split-invite` also directly adds a found user to a group (no accept step). For a shared-finance app, being force-joined into a group exposes the joinee to the group's shared expenses and connects them to the inviter without opt-in.

**Fix prompt (for the LLM):**
```
Restore consent to group membership for split groups.

1. Review supabase/fix_rls.sql, 0014_relax_sgm_rls.sql, and 0011/0012/0013 to
   understand the current split_group_members INSERT policy. Document the intended
   rule: a user may be added to a group ONLY (a) by adding themselves, or (b) via
   an invite THEY accepted (split-invite-accept), not by a creator unilaterally.
2. Create a new migration that replaces the permissive sgm_insert policy so INSERT
   with check is: user_id = auth.uid()  (self-join only through RLS).
   Creator-initiated adds must go through the service-role edge function AFTER the
   invitee accepts.
3. In supabase/functions/split-invite/index.ts, change the "email belongs to a
   registered user" branch: instead of directly upserting them into
   split_group_members, create a PENDING invitation for that user and require
   split-invite-accept. Only connect users after acceptance.
Provide the migration + function diff; do not break the accept flow.
```

---

## 🟡 M4 — Webhook signature comparison is not constant-time

**Where:** `supabase/functions/razorpay-webhook/index.ts`: `if (signature !== expected)`. String `!==` short-circuits and is timing-observable.

**Fix prompt (for the LLM):**
```
File: supabase/functions/razorpay-webhook/index.ts. Replace the direct
`signature !== expected` HMAC comparison with a constant-time compare:

1. Add a helper timingSafeEqual(a: string, b: string): boolean that returns false
   immediately if lengths differ, else XORs all bytes and checks the accumulator
   is 0 (iterate the full length regardless of mismatch).
2. Use it: if (!timingSafeEqual(signature, expected)) return 401.
Keep everything else identical. Apply the same helper to any other HMAC/secret
comparison you find in supabase/functions (e.g. the market-sync cron secret from H2).
```

---

## 🟢 L1 — `security_audit` accepts self-authored rows

**Where:** `supabase/migrations/0021_security.sql`: the insert policy allows a user to insert audit rows where `subject_user = auth.uid()` or `actor = 'user:'||uid`. A user can forge audit entries about their own account, muddying the tamper-evident log. The hash chain detects edits/deletes but not authorized-but-spurious inserts.

**Fix prompt (for the LLM):**
```
File: supabase/migrations/0021_security.sql (add a follow-up migration; don't edit
applied migrations). Tighten security_audit inserts so only the server writes them:
1. Drop the user-facing insert policy; grant INSERT on security_audit to
   service_role only, and route all audit writes through service-role code/RPC.
2. Keep the SELECT policy (users read rows where subject_user = auth.uid()).
3. If clients must trigger audited events, expose a security-definer RPC that
   validates the event and inserts with a server-set actor. Verify no client path
   depends on direct inserts before removing the policy.
```

---

## 🟢 L2 — Production build ignores type and lint errors

**Where:** `apps/web/next.config.js`: `eslint.ignoreDuringBuilds: true`, `typescript.ignoreBuildErrors: true`. Type errors are a common source of security bugs (unchecked nulls, wrong auth branches) shipping silently.

**Fix prompt (for the LLM):**
```
Goal: stop shipping with type/lint errors suppressed, without blocking work today.
1. Add a CI job (.github/workflows) that runs `pnpm -w typecheck` and `pnpm -w lint`
   and fails the PR on errors — this catches issues even while the flags remain.
2. Fix outstanding type errors incrementally, then set typescript.ignoreBuildErrors
   to false and eslint.ignoreDuringBuilds to false in apps/web/next.config.js.
3. If a full fix is too large now, at minimum flip typescript.ignoreBuildErrors to
   false first (types matter most for correctness) and report remaining errors.
```

---

## 🟢 L3 — LLM guardrail is regex-only

**Where:** `supabase/functions/assistant/index.ts` `GUARDRAIL_RULES`. Regex prompt-injection/exfiltration filters are trivially bypassed (unicode, spacing, paraphrase). It's fine as defense-in-depth but must not be the primary control. The real protection is that the function only sends an **aggregated** summary and executes tools client-side with confirmation — keep that invariant.

**Fix prompt (for the LLM):**
```
File: supabase/functions/assistant/index.ts. Do not rely on GUARDRAIL_RULES regex
as a security boundary. Verify and harden the real controls:
1. Confirm the server never forwards raw per-transaction rows to Anthropic — only
   an aggregated summary provided by the client. Add a server-side assertion/limit
   on payload size and reject requests whose messages contain obvious raw-table
   dumps beyond a threshold.
2. Confirm all tool_use blocks are executed CLIENT-side against the local DB with
   user confirmation for writes (RLS still applies to those DB calls). Document
   this trust boundary in a comment at the top of the file.
3. Keep the regex screen as a cheap pre-filter only; add a comment saying it is
   NOT a security boundary. No behavioral change required beyond the size guard.
```

---

## 🟢 L4 — Confirm no secrets ever entered git history

**Where:** repo-wide. `.env` is correctly gitignored and not currently tracked, but C1 proves secret material has been committed before. Verify history is clean of `.env`, service-role keys, API keys, and the `.share` files across **all** commits.

**Fix prompt (for the LLM):**
```
Audit git history for leaked secrets (read-only; report, don't rewrite history
without human sign-off):
1. Run: git log --all --oneline -- .env ".env.*" support-key/ "*.share"
   and report any commits touching them.
2. Run a regex scan across all history for high-signal patterns:
   git grep -nIE "(service_role|SUPABASE_SERVICE_ROLE_KEY|sk-ant-|rzp_(live|test)_|-----BEGIN)" $(git rev-list --all) 2>/dev/null | head
   Report matches with commit + file (do NOT print the secret values themselves —
   redact to first/last 4 chars).
3. If anything is found, produce a REMEDIATION block recommending: rotate each
   exposed secret at its provider, then purge with git filter-repo/BFG and
   force-push after coordinating with the team.
Output a short PASS/FAIL summary.
```

---

## Suggested execution order

1. **C1** (rotate & purge key material) and **C2** (admin authz) — these are actively exploitable data-exposure paths; do them first.
2. **H1–H3** — narrow the attack surface (CORS, market-sync auth, anon grants).
3. **M1–M4** — integrity/consent races.
4. **L1–L4** — hardening and hygiene.

Each fix should ship as its own commit/PR with the finding ID in the title (e.g. `security(C2): server-side admin authorization`) so the audit stays traceable.
