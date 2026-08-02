"use client";

/**
 * Payment handles (UPI IDs) — client side of the `payment-handle` edge function.
 *
 * Handles are NEVER synced and NEVER cached to disk. A counterparty's UPI ID is
 * fetched just-in-time when the user taps Pay, held in React state for that one
 * interaction, and dropped. This is online-only by design — you need a
 * connection to pay anyway.
 */
import { maskVpa } from "@sanvya/upi";

import { getSupabase, getUserId } from "../powersync";

export class HandleError extends Error {
  /** Machine-readable reason, so the UI can offer the right next step. */
  readonly code: string | undefined;
  constructor(message: string, code?: string) {
    super(message);
    this.name = "HandleError";
    this.code = code;
  }
}

interface FnResult {
  error?: string;
  code?: string;
  ok?: boolean;
  hint?: string;
  vpa?: string;
  displayName?: string | null;
}

async function callFn(body: Record<string, unknown>): Promise<FnResult> {
  const { data, error } = await getSupabase().functions.invoke("payment-handle", { body });
  if (error) throw new HandleError(await edgeFnMessage(error));
  const res = (data ?? {}) as FnResult;
  if (res.error) throw new HandleError(res.error, res.code);
  return res;
}

/**
 * The masked hint for your OWN handle, or null if you haven't added one.
 *
 * Read directly from the table rather than via the edge function: the owner RLS
 * policy already permits it, and `handle_hint` is masked by construction —
 * `akh••••@okhdfcbank` — so nothing secret crosses the wire. The ciphertext in
 * `handle_enc` stays useless to the client either way, since only the function
 * holds the key.
 *
 * Schema-qualified, per golden rule #3 — a bare `.from()` resolves to `public`
 * and 404s.
 */
export async function getMyPaymentHandle(): Promise<string | null> {
  let userId: string;
  try {
    userId = getUserId();
  } catch {
    return cachedHint();
  }

  const { data, error } = await getSupabase()
    .schema("sanvya")
    .from("payment_handles")
    .select("handle_hint")
    .eq("user_id", userId)
    .is("deleted_at", null)
    .maybeSingle();

  // Offline, or the 0041 migration isn't applied yet. Fall back to the cached
  // hint rather than claiming they have no UPI ID — telling someone their saved
  // details are gone because the network blinked is worse than showing a stale
  // mask.
  if (error) return cachedHint();

  const hint = (data as { handle_hint?: string } | null)?.handle_hint ?? null;
  rememberHint(hint);
  return hint;
}

/**
 * Locally cached copy of the masked hint.
 *
 * Only ever the mask, never the VPA — the real handle is deliberately never
 * persisted on a device. This exists so the Settings panel can show "you have
 * one" while offline instead of an empty form.
 */
const HINT_KEY = "pc_upi_hint";

function cachedHint(): string | null {
  try {
    return localStorage.getItem(HINT_KEY);
  } catch {
    return null;
  }
}

function rememberHint(hint: string | null): void {
  try {
    if (hint) localStorage.setItem(HINT_KEY, hint);
    else localStorage.removeItem(HINT_KEY);
  } catch {
    /* private mode — the panel just refetches next time */
  }
}

/** Save (or replace) your own UPI ID. Rejected for guests, server-side too. */
export async function savePaymentHandle(vpa: string, displayName?: string): Promise<string> {
  const res = await callFn({ action: "set", vpa, displayName });
  const hint = res.hint ?? maskVpa(vpa);
  rememberHint(hint);
  return hint;
}

/** Remove your UPI ID. Existing disclosures stay in the audit trail. */
export async function forgetPaymentHandle(): Promise<void> {
  await callFn({ action: "forget" });
  rememberHint(null);
}

export interface CounterpartyHandle {
  readonly vpa: string;
  readonly displayName: string | null;
}

/**
 * Fetch someone's UPI ID in order to pay them.
 *
 * Throws `HandleError` with a `code` the caller should branch on:
 *  - `no_handle`   they haven't added one
 *  - `no_group`    you don't share a group (should be unreachable from the UI)
 *  - `no_balance`  nothing to settle
 *  - `rate_limited`
 */
export async function fetchCounterpartyHandle(counterpartyId: string): Promise<CounterpartyHandle> {
  const res = await callFn({ action: "get", counterpartyId });
  if (!res.vpa) throw new HandleError("They haven't added a UPI ID yet.", "no_handle");
  return { vpa: res.vpa, displayName: res.displayName ?? null };
}

/**
 * Same unwrapping as splits/write.ts — supabase-js collapses non-2xx into an
 * opaque message and hides the real `{ error }` body in FunctionsHttpError.context.
 */
async function edgeFnMessage(error: unknown): Promise<string> {
  const ctx = (error as { context?: unknown }).context;
  if (ctx instanceof Response) {
    try {
      const body = await ctx.clone().json();
      if (body && typeof body.error === "string") return body.error;
    } catch {
      /* not JSON */
    }
    if (ctx.status === 401) return "Please sign in to use payments.";
  }
  return (error as Error).message || "Couldn't reach the payments service. Check your connection.";
}
