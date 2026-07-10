"use client";

/**
 * Sealed support access — issue/revoke user-consented, time-boxed grants.
 * A "content" grant re-wraps the DEK for the SUPPORT public key (only support,
 * with its Shamir-reassembled private key, can open it) and is signed by the
 * user's key. A "structural" grant carries no key — it only authorizes drift
 * checksums. Every action is written to the hash-chained security_audit.
 */
import { wrapDekForSupport, signGrant } from "@pocketcare/crypto";
import { getSupabase, getUserId, getDb } from "../powersync";
import { getDek, getSigningPrivate } from "./session";

export type GrantScope = "content" | "structural";

function supportPublicJwk(): JsonWebKey | null {
  const raw = process.env.NEXT_PUBLIC_SUPPORT_PUBLIC_JWK;
  if (!raw) return null;
  try { return JSON.parse(raw) as JsonWebKey; } catch { return null; }
}

export interface ActiveGrant { id: string; scope: string; expires_at: string; created_at: string }

/** The user's currently-active (unexpired, unrevoked) grants, from the local cache. */
export async function activeGrants(): Promise<ActiveGrant[]> {
  const db = getDb(); const uid = getUserId();
  if (!db || !uid) return [];
  const now = new Date().toISOString();
  return db.getAll<ActiveGrant>(
    "SELECT id, scope, expires_at, created_at FROM support_grants WHERE user_id = ? AND revoked_at IS NULL AND expires_at > ? ORDER BY created_at DESC",
    [uid, now],
  );
}

/** Issue a support grant. `content` requires the session to be unlocked. */
export async function issueSupportGrant(scope: GrantScope, ttlHours = 2): Promise<{ grantId: string; expiresAt: string }> {
  const uid = getUserId();
  if (!uid) throw new Error("Not signed in.");
  const grantId = globalThis.crypto.randomUUID();
  const exp = Date.now() + ttlHours * 3_600_000;
  const expiresAt = new Date(exp).toISOString();

  let wrapped: string | null = null;
  if (scope === "content") {
    const dek = getDek();
    if (!dek) throw new Error("Unlock encryption first to share content access.");
    const pub = supportPublicJwk();
    if (!pub) throw new Error("Support access is not configured for this deployment.");
    wrapped = await wrapDekForSupport(dek, pub);
  }
  const priv = getSigningPrivate();
  if (!priv) throw new Error("Unlock encryption to authorize support access.");

  const signature = await signGrant({ userId: uid, grantId, exp, scope }, priv);
  const sb = getSupabase().schema("pocketcare");
  const { error } = await sb.from("support_grants").insert({
    id: grantId, user_id: uid, scope, wrapped_dek_for_support: wrapped, signature, expires_at: expiresAt,
  });
  if (error) throw new Error(error.message);
  await sb.from("security_audit").insert({ actor: `user:${uid}`, action: "grant_issued", subject_user: uid, grant_id: grantId, detail: `scope=${scope}` });
  return { grantId, expiresAt };
}

/** Revoke a grant early. */
export async function revokeGrant(grantId: string): Promise<void> {
  const uid = getUserId();
  if (!uid) return;
  const sb = getSupabase().schema("pocketcare");
  await sb.from("support_grants").update({ revoked_at: new Date().toISOString() }).eq("id", grantId).eq("user_id", uid);
  await sb.from("security_audit").insert({ actor: `user:${uid}`, action: "grant_revoked", subject_user: uid, grant_id: grantId });
}
