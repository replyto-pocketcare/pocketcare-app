/**
 * @pocketcare/crypto — envelope encryption for the Hybrid zero-trust model.
 *
 * Model:
 *   passphrase --PBKDF2--> KEK  (never leaves the device)
 *   random DEK (encrypts sensitive fields) is wrapped by KEK -> stored server-side
 *   the same DEK is also wrapped by a RECOVERY code (offline backup)
 *   for support: the DEK is re-wrapped for the SUPPORT public key ON USER CONSENT,
 *     time-boxed, and the support private key is Shamir-split (see ./shamir).
 *
 * The server only ever stores wrapped keys + ciphertext, so admins see no
 * plaintext. Uses WebCrypto (available in browsers, Deno, and Node 22+), so this
 * module is pure and runs identically in the app, the edge, and tests.
 */

const subtle = globalThis.crypto.subtle;
// WebCrypto accepts any ArrayBufferView; TS 5.7's Uint8Array<ArrayBufferLike>
// generic is stricter than BufferSource, so normalize at the call boundary.
const bs = (u: Uint8Array): BufferSource => u as unknown as BufferSource;
const PBKDF2_ITERATIONS = 210_000; // OWASP 2023 guidance for PBKDF2-HMAC-SHA256
const ENVELOPE_VERSION = "v1";

// ---- byte / base64 helpers ----
export function toBase64(bytes: Uint8Array): string {
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!);
  return btoa(s);
}
export function fromBase64(b64: string): Uint8Array {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}
const enc = new TextEncoder();
const dec = new TextDecoder();
function randomBytes(n: number): Uint8Array {
  const b = new Uint8Array(n);
  globalThis.crypto.getRandomValues(b);
  return b;
}

// ---- key derivation ----
export function newSalt(): Uint8Array {
  return randomBytes(16);
}

/** Derive a wrapping key (AES-GCM 256) from a passphrase or recovery code. */
export async function deriveKek(passphrase: string, salt: Uint8Array, iterations = PBKDF2_ITERATIONS): Promise<CryptoKey> {
  const base = await subtle.importKey("raw", bs(enc.encode(passphrase)), "PBKDF2", false, ["deriveKey"]);
  return subtle.deriveKey(
    { name: "PBKDF2", salt: bs(salt), iterations, hash: "SHA-256" },
    base,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

// ---- data encryption key (DEK) ----
/** A fresh 256-bit data encryption key (raw bytes). */
export function generateDek(): Uint8Array {
  return randomBytes(32);
}

async function importAesKey(raw: Uint8Array): Promise<CryptoKey> {
  return subtle.importKey("raw", bs(raw), "AES-GCM", false, ["encrypt", "decrypt"]);
}

// ---- generic AES-GCM envelope ----
async function aesEncrypt(key: CryptoKey, plaintext: Uint8Array): Promise<string> {
  const iv = randomBytes(12);
  const ct = new Uint8Array(await subtle.encrypt({ name: "AES-GCM", iv: bs(iv) }, key, bs(plaintext)));
  return `${ENVELOPE_VERSION}.${toBase64(iv)}.${toBase64(ct)}`;
}
async function aesDecrypt(key: CryptoKey, envelope: string): Promise<Uint8Array> {
  const parts = envelope.split(".");
  if (parts.length !== 3 || parts[0] !== ENVELOPE_VERSION) throw new Error("bad envelope");
  const iv = fromBase64(parts[1]!);
  const ct = fromBase64(parts[2]!);
  return new Uint8Array(await subtle.decrypt({ name: "AES-GCM", iv: bs(iv) }, key, bs(ct)));
}

/** Wrap the DEK under a KEK (from passphrase or recovery code). */
export async function wrapDek(dek: Uint8Array, kek: CryptoKey): Promise<string> {
  return aesEncrypt(kek, dek);
}
/** Unwrap the DEK. Throws if the KEK is wrong or the envelope was tampered. */
export async function unwrapDek(wrapped: string, kek: CryptoKey): Promise<Uint8Array> {
  return aesDecrypt(kek, wrapped);
}

// ---- field-level encryption (what the repos call) ----
export async function encryptField(plaintext: string, dek: Uint8Array): Promise<string> {
  return aesEncrypt(await importAesKey(dek), enc.encode(plaintext));
}
export async function decryptField(envelope: string, dek: Uint8Array): Promise<string> {
  return dec.decode(await aesDecrypt(await importAesKey(dek), envelope));
}
/** True if a stored value looks like one of our ciphertext envelopes. */
export function isEncrypted(value: unknown): value is string {
  return typeof value === "string" && value.startsWith(`${ENVELOPE_VERSION}.`);
}

// ---- recovery code ----
/** A human-transcribable recovery code (base32-ish, grouped). */
export function generateRecoveryCode(): string {
  const alphabet = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // no ambiguous chars
  const raw = randomBytes(20);
  let out = "";
  for (let i = 0; i < raw.length; i++) {
    out += alphabet[raw[i]! % alphabet.length];
    if ((i + 1) % 4 === 0 && i < raw.length - 1) out += "-";
  }
  return out;
}

// ---- support grant (asymmetric, on user consent) ----
export interface SupportKeypair { publicJwk: JsonWebKey; privateJwk: JsonWebKey }

/** Generate the SUPPORT keypair. The private key is Shamir-split among officers. */
export async function generateSupportKeypair(): Promise<SupportKeypair> {
  const pair = await subtle.generateKey({ name: "RSA-OAEP", modulusLength: 3072, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["encrypt", "decrypt"]);
  return {
    publicJwk: await subtle.exportKey("jwk", pair.publicKey),
    privateJwk: await subtle.exportKey("jwk", pair.privateKey),
  };
}

/** Re-wrap the DEK for support (only the support private key can open it). */
export async function wrapDekForSupport(dek: Uint8Array, supportPublicJwk: JsonWebKey): Promise<string> {
  const pub = await subtle.importKey("jwk", supportPublicJwk, { name: "RSA-OAEP", hash: "SHA-256" }, false, ["encrypt"]);
  const ct = new Uint8Array(await subtle.encrypt({ name: "RSA-OAEP" }, pub, bs(dek)));
  return toBase64(ct);
}
/** Support side: recover the DEK from a consent grant using the (reassembled) private key. */
export async function unwrapDekFromSupport(wrapped: string, supportPrivateJwk: JsonWebKey): Promise<Uint8Array> {
  const priv = await subtle.importKey("jwk", supportPrivateJwk, { name: "RSA-OAEP", hash: "SHA-256" }, false, ["decrypt"]);
  return new Uint8Array(await subtle.decrypt({ name: "RSA-OAEP" }, priv, bs(fromBase64(wrapped))));
}

// ---- consent-token signing (proves the USER authorized the grant) ----
export interface SigningKeypair { publicJwk: JsonWebKey; privateJwk: JsonWebKey }
export async function generateSigningKeypair(): Promise<SigningKeypair> {
  const pair = await subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  return { publicJwk: await subtle.exportKey("jwk", pair.publicKey), privateJwk: await subtle.exportKey("jwk", pair.privateKey) };
}
export async function signGrant(payload: object, privateJwk: JsonWebKey): Promise<string> {
  const key = await subtle.importKey("jwk", privateJwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const sig = new Uint8Array(await subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, bs(enc.encode(canonical(payload)))));
  return toBase64(sig);
}
export async function verifyGrant(payload: object, signature: string, publicJwk: JsonWebKey): Promise<boolean> {
  const key = await subtle.importKey("jwk", publicJwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  return subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, bs(fromBase64(signature)), bs(enc.encode(canonical(payload))));
}

// ---- security audit hash-chain (mirror of the 0021 DB trigger) ----
export interface AuditRow {
  id: string; actor: string; action: string;
  subject_user?: string | null; grant_id?: string | null; detail?: string | null;
  created_at: string; prev_hash?: string | null; row_hash?: string;
}

async function sha256Hex(s: string): Promise<string> {
  const d = new Uint8Array(await subtle.digest("SHA-256", bs(enc.encode(s))));
  let out = "";
  for (const b of d) out += b.toString(16).padStart(2, "0");
  return out;
}

/** Compute a row's chain hash from the previous row's hash (same field order as the trigger). */
export async function auditRowHash(prevHash: string, r: AuditRow): Promise<string> {
  const s = prevHash + (r.actor ?? "") + (r.action ?? "") + (r.subject_user ?? "") +
    (r.grant_id ?? "") + (r.detail ?? "") + r.id + r.created_at;
  return sha256Hex(s);
}

/** Verify an ordered audit chain; returns the id of the first tampered/broken row if any. */
export async function verifyAuditChain(rows: AuditRow[]): Promise<{ ok: boolean; brokenAt?: string }> {
  let prev = "";
  for (const r of rows) {
    const expected = await auditRowHash(prev, r);
    if (r.row_hash !== undefined && r.row_hash !== expected) return { ok: false, brokenAt: r.id };
    prev = r.row_hash ?? expected;
  }
  return { ok: true };
}

/** Stable JSON (sorted keys) so signatures are deterministic. */
function canonical(obj: unknown): string {
  if (obj === null || typeof obj !== "object") return JSON.stringify(obj);
  if (Array.isArray(obj)) return `[${obj.map(canonical).join(",")}]`;
  const keys = Object.keys(obj as Record<string, unknown>).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${canonical((obj as Record<string, unknown>)[k])}`).join(",")}}`;
}
