# 04 — Security & Privacy

PocketCare handles sensitive financial data. Security rests on four pillars: **authentication**, **row-level security**, **zero-trust encryption of sensitive fields**, and **auditable support access**. See also `SECURITY_AUDIT.md` and `SECURITY_ENCRYPTION_PLAN.md` at the repo root.

## Authentication

- Supabase Auth with **anonymous guest** identities and **email/password** registration.
- A guest is a real user (`is_anonymous = true`); registration upgrades the **same UID** (see [03 — Sync & Offline](03-sync-and-offline.md#identity-anonymous-guest--registered-user-same-uid)).
- JWTs authorise every PostgREST/RPC/Edge-Function call; PowerSync uses the same JWT for sync.

## Row-Level Security (RLS)

Every owner-scoped table enables RLS with an owner policy:

```sql
create policy <name>_owner on pocketcare.<table>
  using (user_id = auth.uid()) with check (user_id = auth.uid());
```

The **shared ledger** uses membership-based policies (helper functions `is_group_member`, `is_group_creator`, `is_connected`) so a member can read a group's expenses/settlements but only write their own rows.

```mermaid
flowchart TB
    Req["Authenticated request (JWT → auth.uid())"] --> P{"RLS policy"}
    P -->|"owner tables"| O["user_id = auth.uid()"]
    P -->|"splits tables"| M["is_group_member(group_id, auth.uid())"]
    P -->|"reference/market"| G["read-only, global"]
    O --> Allow["row visible / writable"]
    M --> Allow
    G --> Allow
    P -->|"else"| Deny["denied"]
```

## Zero-trust encryption (sensitive fields)

The server only ever holds **wrapped keys + ciphertext** — it cannot read protected values. Implemented with WebCrypto in `@pocketcare/crypto` and the `user_keys` table.

```mermaid
flowchart LR
    PW["User passphrase"] --> KDF["PBKDF2/Argon2 + salt"]
    KDF --> KEK["Key-Encryption Key (in memory only)"]
    DEK["Data-Encryption Key (random)"] -->|encrypt fields| CT["ciphertext → Postgres"]
    KEK -->|wrap| WDEK["wrapped_dek_passphrase → Postgres"]
    RK["Recovery key"] -->|wrap| WDEK2["wrapped_dek_recovery → Postgres"]
    Note["Server stores wrapped keys + ciphertext only —<br/>never the KEK or plaintext DEK"]
```

- `user_keys` holds: `salt`, `wrapped_dek_passphrase`, `wrapped_dek_recovery`, a signing keypair (`signing_public_jwk`, `wrapped_signing_private`).
- The **DEK never leaves the client in plaintext**; it is unwrapped in memory from the passphrase-derived KEK.
- A hash-chained `security_audit` table records privileged actions (tamper-evident via `prev_hash` → `row_hash`).

## Support access (Shamir-split custody)

Support can be granted **time-bound, consented** access to a user's DEK without any single party holding it. Support-key material is split (Shamir) and stored out-of-band (never committed; `support-key/` is git-ignored).

```mermaid
sequenceDiagram
    actor User
    participant App
    participant PG as Postgres
    participant Support
    User->>App: grant support access (scope, expiry)
    App->>App: wrap DEK for support public key
    App->>PG: insert support_grants (wrapped_dek_for_support, signature, expires_at)
    Support->>PG: read grant (if unexpired, unrevoked)
    Support->>Support: reconstruct support key from Shamir shares (M-of-N)
    Support->>Support: unwrap DEK → time-boxed access
    Note over PG: security_audit hash-chain records the grant
```

## Account deletion

Self-serve deletion removes the identity and **all** associated data and frees the email for re-registration.

```mermaid
sequenceDiagram
    actor User
    participant UI as Settings
    participant RPC as pocketcare.delete_user_account()
    participant PG as Postgres
    User->>UI: Delete everything
    UI->>RPC: supabase.schema('pocketcare').rpc('delete_user_account')
    RPC->>PG: clear splits rows (no-cascade FKs) in FK-safe order
    RPC->>PG: delete owner tables (accounts, transactions, planned_cashflow, …)
    RPC->>PG: delete profiles, entitlements
    RPC->>PG: delete auth.users (cascades the rest)
    RPC-->>UI: success
    UI->>UI: disconnectAndClear() local DB → signOut()
```

**Two historical bugs, both fixed:**

1. **404 / silent no-op** — the RPC lives in the `pocketcare` schema but was called via `supabase.rpc()` (which targets `public`). Fixed by schema-qualifying the call **and** checking the returned `error` (migration `0030`, `apps/web/app/settings/page.tsx`).
2. **FK violation on `auth.users`** — the multi-user splits tables reference `auth.users` **without** `ON DELETE CASCADE`, so the final delete failed. Fixed by clearing splits rows first (migration `0031`). A full-schema scan confirmed those 7 columns are the only non-cascade FKs to `auth.users`.

## Threat-model highlights

- **Data at rest (server):** RLS + wrapped keys; a DB compromise yields ciphertext for protected fields, not plaintext.
- **Data in transit:** TLS; JWT-scoped access.
- **Offline device:** local SQLite is unencrypted at the SQLite layer today — mitigations tracked in `SECURITY_ENCRYPTION_PLAN.md` (device-level encryption + optional app lock).
- **Billing integrity:** Razorpay webhooks are **HMAC-verified and idempotent**; entitlement writes use `upsert(onConflict: user_id)` (a prior bug where `.update().eq()` silently no-opped for users without an entitlements row is fixed).
- **Auto-categorisation model** is loaded from a CDN at runtime and runs **on-device** (no transaction text leaves the client).
