# Security — Hybrid zero-trust encryption + sealed support access

Chosen model: **Hybrid**. Encrypt the truly sensitive *content* client-side (so admins see only ciphertext); keep numeric amounts/tickers readable so server features (assistant aggregation, market-sync) keep working. Support is **structural-by-default** (drift-fixing, no plaintext) and can see content **only on the user's explicit, time-boxed, audited consent**.

## What gets encrypted (client-side, E2E)

Sensitive free-text / identifiers → ciphertext at rest, key never on server:
`transactions.description`, `transactions.note`, `transaction_items.description`, `accounts.name`, `credit_card_details.card_last4` (and any future full PAN), `labels.name` (optional), goal/subscription names.

Stays plaintext (server must compute on it): `amount`, `currency`, `occurred_at`, `account_id`, `category_id`, `symbol`. (Amounts are numbers, not identifying on their own; this is the pragmatic Hybrid tradeoff.)

## Key model (envelope encryption) — `@pocketcare/crypto`

```
passphrase --PBKDF2(210k, SHA-256, per-user salt)--> KEK   (client only)
DEK = random 256-bit                                        (encrypts fields)
wrapped_dek_passphrase = AES-GCM(KEK, DEK)                  (stored server-side)
wrapped_dek_recovery   = AES-GCM(recoveryKey, DEK)          (offline backup code)
```
Server stores only `wrapped_dek_*` + salt + ciphertext envelopes (`v1.<iv>.<ct>`), never the DEK or KEK. Unlock at login derives KEK from the passphrase and unwraps the DEK into memory; fields decrypt on read, encrypt on write. Tested: round-trip, wrong-key rejection, GCM tamper detection, recovery path.

## Sealed support access

1. **Structural (default, no plaintext).** Support runs the `@pocketcare/reconcile` checksum validators (local SQLite vs remote Supabase) to detect/repair sync drift by id + per-row checksum. No field is ever decrypted.
2. **Consent grant (content, rare).** User flips "Grant Temporary Support Access" → client unwraps its DEK locally and **re-wraps it for the SUPPORT public key** (`wrapDekForSupport`), producing a grant valid **2 hours**. The grant payload (`{ userId, grantId, exp, scope }`) is **signed by the user's ECDSA key** (`signGrant`) proving they authorized it. Support cannot decrypt without a live, unexpired, user-signed grant.
3. **No single-insider decryption.** The SUPPORT private key is **Shamir-split M-of-N** (`./shamir`, GF(256)) across support officers; e.g. 2-of-3 must combine shares to open any grant.
4. **Immutable audit.** Every grant issue/expire and every support decrypt/drift-fix is appended to a hash-chained `security_audit` table (each row stores `prev_hash` + `row_hash`), so tampering is detectable.

## Schema (next migrations)

- `user_keys` (per user): `salt`, `wrapped_dek_passphrase`, `wrapped_dek_recovery`, `signing_public_jwk`, `created_at`. RLS owner-only; server can't derive keys from these.
- `support_grants`: `id`, `user_id`, `wrapped_dek_for_support`, `signature`, `scope`, `expires_at`, `revoked_at`, `created_at`. Owner can insert/revoke; support role reads only unexpired rows.
- `security_audit` (append-only): `id`, `actor`, `action`, `subject_user`, `grant_id`, `detail`, `prev_hash`, `row_hash`, `created_at`. Insert-only (no update/delete policy); hash-chained.

## Build phases

1. ✅ `@pocketcare/crypto` (envelope + recovery + support grant + Shamir) + tests. `@pocketcare/reconcile` (drift checksums) + tests.
2. Schema migrations (`user_keys`, `support_grants`, `security_audit`) + RLS + streams.
3. Client key lifecycle: setup (passphrase + recovery code), unlock at login, lock on sign-out; store `user_keys`.
4. Field encryption through the repos (encrypt on write / decrypt on read for the listed fields); migration/backfill for existing rows.
5. "Grant Temporary Support Access" switch in profile settings (issue signed, time-boxed grant).
6. Headless **Support Admin** script: reconcile drift-fix (default) + consented decrypt (Shamir-combine support key → `unwrapDekFromSupport`) → all actions hash-chained into `security_audit`.

## Operational notes

- Support keypair generated once offline; private key Shamir-split and distributed to officers; **public key ships in config**. Rotating it re-issues future grants only.
- Losing the passphrase requires the recovery code; losing both = unrecoverable (by design — that's what zero-trust means). The UI must make the recovery code impossible to skip at setup.
