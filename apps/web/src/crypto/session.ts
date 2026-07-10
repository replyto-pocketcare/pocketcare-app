"use client";

/**
 * Client-side encryption session — the key lifecycle for the Hybrid zero-trust
 * model. The DEK lives ONLY in memory while unlocked; the server stores wrapped
 * keys + ciphertext. See SECURITY_ENCRYPTION_PLAN.md.
 *
 * Writes to `user_keys` go straight to Supabase (server holds only wrapped
 * material); reads come from the offline-synced local copy.
 */
import { useSyncExternalStore } from "react";
import {
  deriveKek, newSalt, generateDek, wrapDek, unwrapDek, encryptField, decryptField,
  generateRecoveryCode, generateSigningKeypair, toBase64, fromBase64,
} from "@pocketcare/crypto";
import { getSupabase, getUserId, getDb } from "../powersync";

export type CryptoStatus = "loading" | "unset" | "locked" | "unlocked";

interface KeyRow {
  user_id: string; salt: string; wrapped_dek_passphrase: string; wrapped_dek_recovery: string | null;
  signing_public_jwk: string | null; wrapped_signing_private: string | null;
}

// In-memory only — never persisted.
let dek: Uint8Array | null = null;
let signingPrivate: JsonWebKey | null = null;
let hasKeys: boolean | null = null; // null = not yet checked
const listeners = new Set<() => void>();
const notify = () => listeners.forEach((l) => l());

function status(): CryptoStatus {
  if (hasKeys === null) return "loading";
  if (!hasKeys) return "unset";
  return dek ? "unlocked" : "locked";
}

async function readKeyRow(): Promise<KeyRow | null> {
  const db = getDb();
  const uid = getUserId();
  if (!db || !uid) return null;
  return db.getOptional<KeyRow>("SELECT * FROM user_keys WHERE user_id = ?", [uid]);
}

/** Load whether this user has set up encryption (drives the status hook). */
export async function refreshKeyState(): Promise<void> {
  const row = await readKeyRow();
  hasKeys = !!row;
  notify();
}

/** First-time setup. Returns the one-time recovery code (show it once, never stored plaintext). */
export async function setupEncryption(passphrase: string): Promise<string> {
  const uid = getUserId();
  if (!uid) throw new Error("Not signed in.");
  const salt = newSalt();
  dek = generateDek();
  const kek = await deriveKek(passphrase, salt);
  const wrapped_dek_passphrase = await wrapDek(dek, kek);

  const recoveryCode = generateRecoveryCode();
  const wrapped_dek_recovery = await wrapDek(dek, await deriveKek(recoveryCode, salt));

  const signing = await generateSigningKeypair();
  signingPrivate = signing.privateJwk;
  const wrapped_signing_private = await encryptField(JSON.stringify(signing.privateJwk), dek);

  const { error } = await getSupabase().schema("pocketcare").from("user_keys").upsert({
    user_id: uid,
    salt: toBase64(salt),
    wrapped_dek_passphrase,
    wrapped_dek_recovery,
    signing_public_jwk: signing.publicJwk,
    wrapped_signing_private,
    updated_at: new Date().toISOString(),
  });
  if (error) { dek = null; signingPrivate = null; throw new Error(error.message); }

  hasKeys = true;
  notify();
  return recoveryCode;
}

async function unwrapWith(passphraseOrCode: string, which: "passphrase" | "recovery"): Promise<void> {
  const row = await readKeyRow();
  if (!row) throw new Error("Encryption is not set up on this account.");
  const salt = fromBase64(row.salt);
  const wrapped = which === "passphrase" ? row.wrapped_dek_passphrase : row.wrapped_dek_recovery;
  if (!wrapped) throw new Error("No recovery key on file.");
  const kek = await deriveKek(passphraseOrCode, salt);
  dek = await unwrapDek(wrapped, kek); // throws on wrong key / tamper
  if (row.wrapped_signing_private) {
    try { signingPrivate = JSON.parse(await decryptField(row.wrapped_signing_private, dek)) as JsonWebKey; } catch { signingPrivate = null; }
  }
  notify();
}

/** Unlock with the passphrase. Throws on a wrong passphrase. */
export const unlock = (passphrase: string) => unwrapWith(passphrase, "passphrase");
/** Unlock with the recovery code (forgotten passphrase path). */
export const unlockWithRecovery = (code: string) => unwrapWith(code.trim().toUpperCase(), "recovery");

/** Drop keys from memory (sign-out / manual lock). */
export function lock(): void {
  dek = null;
  signingPrivate = null;
  notify();
}

/** The DEK, if unlocked (used by the field-encryption service). */
export const getDek = (): Uint8Array | null => dek;
export const getSigningPrivate = (): JsonWebKey | null => signingPrivate;
export const isUnlocked = (): boolean => dek !== null;

export function useCryptoStatus(): CryptoStatus {
  return useSyncExternalStore(
    (cb) => { listeners.add(cb); return () => listeners.delete(cb); },
    status,
    () => "loading",
  );
}
