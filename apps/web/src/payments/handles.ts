"use client";

/**
 * Payment handles (UPI IDs) — client side of the `payment-handle` edge function.
 *
 * Handles are NEVER synced and NEVER cached to disk. A counterparty's UPI ID is
 * fetched just-in-time when the user taps Pay, held in React state for that one
 * interaction, and dropped. This is online-only by design — you need a
 * connection to pay anyway.
 */
import { maskVpa } from "@pocketcare/upi";

import { getSupabase } from "../powersync";

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

/** Save (or replace) your own UPI ID. Rejected for guests, server-side too. */
export async function savePaymentHandle(vpa: string, displayName?: string): Promise<string> {
  const res = await callFn({ action: "set", vpa, displayName });
  return res.hint ?? maskVpa(vpa);
}

/** Remove your UPI ID. Existing disclosures stay in the audit trail. */
export async function forgetPaymentHandle(): Promise<void> {
  await callFn({ action: "forget" });
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
