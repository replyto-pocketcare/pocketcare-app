"use client";

/**
 * Field-level encryption service. Backward-compatible by design: values written
 * while the session is unlocked become ciphertext envelopes; anything else
 * (legacy plaintext, or writes while locked/unset) is stored as-is and rendered
 * as-is. `useDecrypted` transparently decrypts envelopes for display.
 */
import { useEffect, useState } from "react";
import { encryptField, decryptField, isEncrypted } from "@pocketcare/crypto";
import { getDek } from "./session";

// ciphertext -> plaintext, primed on write and filled on read (envelopes are stable).
const cache = new Map<string, string>();

/** Encrypt a value for storage if the session is unlocked; otherwise pass through. */
export async function encryptForWrite(plaintext: string | null | undefined): Promise<string | null> {
  const v = plaintext ?? null;
  if (v === null || v === "") return v;
  if (isEncrypted(v)) return v; // already an envelope
  const dek = getDek();
  if (!dek) return v; // locked / not set up → store plaintext (Hybrid opt-in)
  const env = await encryptField(v, dek);
  cache.set(env, v);
  return env;
}

async function decryptToCache(value: string): Promise<string> {
  if (!isEncrypted(value)) return value;
  const hit = cache.get(value);
  if (hit !== undefined) return hit;
  const dek = getDek();
  if (!dek) return "•••••"; // locked — masked
  try { const p = await decryptField(value, dek); cache.set(value, p); return p; }
  catch { return "⚠︎ unreadable"; }
}

/** Reactive decrypted view of a possibly-encrypted value. Plaintext passes through. */
export function useDecrypted(value: string | null | undefined): string {
  const v = value ?? "";
  const [out, setOut] = useState(() => (isEncrypted(v) ? (cache.get(v) ?? "") : v));
  useEffect(() => {
    let live = true;
    if (!isEncrypted(v)) { setOut(v); return; }
    const hit = cache.get(v);
    if (hit !== undefined) { setOut(hit); return; }
    void decryptToCache(v).then((p) => { if (live) setOut(p); });
    return () => { live = false; };
  }, [v]);
  return out;
}
