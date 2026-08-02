/**
 * @sanvya/upi — building UPI Intent deep links for peer-to-peer settle-up.
 *
 * WHY THIS IS A PACKAGE: the URL we produce is handed to a third-party UPI app
 * and we never see what happens next. A malformed link fails silently inside
 * someone else's software, where no amount of logging will help us. So the
 * construction is pure, isolated, and tested to death.
 *
 * WHAT THIS IS NOT: a payment integration. Sanvya never touches the money.
 * We hand the payer's own UPI app a prefilled instruction; the transfer is
 * bank-to-bank between two individuals. There is no PSP, no escrow, no merchant
 * account, and consequently **no success callback** — see `docs/features/
 * upi-settle-up.md` §"No payment confirmation exists".
 *
 * Erasable TS only (no `enum`) so `node --experimental-strip-types` runs the
 * tests with no build step.
 */

/** UPI is India-only. Every entry point refuses anything else. */
export const UPI_CURRENCY = "INR";

/** Minor-unit digits for INR. UPI always wants two decimal places. */
const MINOR_DIGITS = 2;

export class UpiError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "UpiError";
  }
}

// ---------------------------------------------------------------------------
// VPA (Virtual Payment Address)
// ---------------------------------------------------------------------------

/**
 * `name@handle`, per NPCI's linking spec.
 *
 * Intentionally permissive on the handle side: PSP handles proliferate
 * (`@okhdfcbank`, `@ybl`, `@paytm`, `@axl`, …) and an allow-list would reject
 * legitimate new ones. We validate SHAPE, not the specific provider — the
 * payer's UPI app does the real resolution and shows them the account name.
 */
const VPA_RE = /^[a-z0-9](?:[a-z0-9._-]{0,60}[a-z0-9])?@[a-z][a-z0-9.-]{1,63}$/i;

export function isValidVpa(value: string): boolean {
  const v = value.trim();
  if (v.length < 3 || v.length > 128) return false;
  // A double dot or a leading/trailing dot in either part is always wrong.
  if (v.includes("..")) return false;
  const [name, handle] = v.split("@");
  if (!name || !handle) return false;
  if (v.split("@").length !== 2) return false;
  if (handle.startsWith(".") || handle.endsWith(".")) return false;
  return VPA_RE.test(v);
}

export function normalizeVpa(value: string): string {
  return value.trim().toLowerCase();
}

/**
 * `akhilesh@okhdfcbank` -> `akh••••@okhdfcbank`.
 *
 * Lets us show the owner which handle is saved, and the payer who they're
 * about to pay, without either screen becoming a place to harvest full VPAs
 * from a shoulder-surf or a screenshot.
 */
export function maskVpa(value: string): string {
  const v = value.trim();
  const at = v.lastIndexOf("@");
  if (at <= 0) return "••••";
  const name = v.slice(0, at);
  const handle = v.slice(at);
  if (name.length <= 3) return `${name[0] ?? ""}••••${handle}`;
  return `${name.slice(0, 3)}••••${handle}`;
}

// ---------------------------------------------------------------------------
// Amounts
// ---------------------------------------------------------------------------

/**
 * Integer minor units -> the decimal string UPI expects ("430.00").
 *
 * Always two decimals, never thousands-grouped. A grouped amount ("1,234.00")
 * is rejected or silently mis-read by UPI apps, which is exactly the kind of
 * failure we can't observe.
 */
export function formatAmount(minor: number): string {
  if (!Number.isInteger(minor)) throw new UpiError(`Amount must be integer minor units, got ${minor}`);
  if (minor <= 0) throw new UpiError("Amount must be greater than zero");
  const sign = minor < 0 ? "-" : "";
  const abs = Math.abs(minor);
  const whole = Math.floor(abs / 10 ** MINOR_DIGITS);
  const frac = String(abs % 10 ** MINOR_DIGITS).padStart(MINOR_DIGITS, "0");
  return `${sign}${whole}.${frac}`;
}

// ---------------------------------------------------------------------------
// Reference
// ---------------------------------------------------------------------------

/**
 * Our own transaction reference, passed as `tr=`.
 *
 * Most UPI apps surface this in the payment record, and banks often carry it
 * into the statement narration — so it's the one thread a user can pull to
 * match a Sanvya settlement against their bank statement when something
 * looks wrong. Alphanumeric only and kept short, because some PSPs quietly
 * truncate or reject punctuation here.
 */
const REF_ALPHABET = "ABCDEFGHIJKLMNPQRSTUVWXYZ123456789"; // no O/0 confusion

export function newPaymentRef(random: () => number = Math.random): string {
  let out = "PC";
  for (let i = 0; i < 10; i++) {
    out += REF_ALPHABET[Math.floor(random() * REF_ALPHABET.length)] ?? "X";
  }
  return out;
}

export function isValidRef(ref: string): boolean {
  return /^[A-Za-z0-9]{1,35}$/.test(ref);
}

// ---------------------------------------------------------------------------
// Intent URL
// ---------------------------------------------------------------------------

export interface IntentParams {
  /** Payee VPA. */
  readonly vpa: string;
  /** Payee display name, shown in the UPI app. */
  readonly name: string;
  /** Amount in integer minor units (paise). */
  readonly amountMinor: number;
  // `| undefined` on each optional: the repo runs `exactOptionalPropertyTypes`,
  // so callers spreading a partial override need to be able to pass undefined.
  /** Free-text note shown to both parties. */
  readonly note?: string | undefined;
  /** Our reference; generated by `newPaymentRef()` if omitted. */
  readonly ref?: string | undefined;
  readonly currency?: string | undefined;
}

/**
 * UPI notes are short and punctuation-hostile. Strip anything that could break
 * a PSP's parser rather than trusting percent-encoding to save us — some apps
 * decode the query string loosely.
 */
function sanitizeNote(note: string): string {
  return note
    .replace(/[&?#=%]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 50);
}

function sanitizeName(name: string): string {
  const cleaned = name.replace(/[&?#=%]/g, " ").replace(/\s+/g, " ").trim().slice(0, 50);
  return cleaned || "Sanvya";
}

export interface BuiltIntent {
  readonly url: string;
  /** The reference actually used, to store on the settlement. */
  readonly ref: string;
}

/**
 * Build a `upi://pay?…` Intent URL.
 *
 * Only the parameters NPCI defines are emitted, in the conventional order:
 * `pa` payee address, `pn` payee name, `am` amount, `cu` currency,
 * `tn` note, `tr` reference.
 */
export function buildIntentUrl(params: IntentParams): BuiltIntent {
  const currency = params.currency ?? UPI_CURRENCY;
  if (currency !== UPI_CURRENCY) {
    throw new UpiError(`UPI only supports ${UPI_CURRENCY}, got ${currency}`);
  }

  const vpa = normalizeVpa(params.vpa);
  if (!isValidVpa(vpa)) throw new UpiError(`Not a valid UPI ID: ${params.vpa}`);

  const ref = params.ref ?? newPaymentRef();
  if (!isValidRef(ref)) throw new UpiError(`Invalid payment reference: ${ref}`);

  const amount = formatAmount(params.amountMinor);

  // Built by hand rather than with URLSearchParams: that encodes spaces as "+",
  // which several UPI apps render literally in the note.
  const parts = [
    `pa=${encodeURIComponent(vpa)}`,
    `pn=${encodeURIComponent(sanitizeName(params.name))}`,
    `am=${amount}`,
    `cu=${currency}`,
    `tr=${encodeURIComponent(ref)}`,
  ];
  const note = params.note ? sanitizeNote(params.note) : "";
  if (note) parts.push(`tn=${encodeURIComponent(note)}`);

  return { url: `upi://pay?${parts.join("&")}`, ref };
}

/**
 * The same string, for rendering as a QR the payer scans on desktop.
 *
 * Identical payload by design: one code path, so a bug can't affect only one
 * of the two surfaces.
 */
export function buildQrPayload(params: IntentParams): BuiltIntent {
  return buildIntentUrl(params);
}

/** Whether to offer UPI at all for this balance. */
export function canPayViaUpi(opts: { currency: string; amountMinor: number; hasHandle: boolean }): boolean {
  return opts.currency === UPI_CURRENCY && opts.amountMinor > 0 && opts.hasHandle;
}

// ---------------------------------------------------------------------------
// Reading a UPI target: a typed VPA, or a QR someone else produced.
// ---------------------------------------------------------------------------

/**
 * What a scanned QR / typed string resolved to.
 *
 * SECURITY: every field here is ATTACKER-CONTROLLED. A QR sticker can be
 * swapped on a shop counter, and it decides the payee, the displayed name and
 * the amount. So:
 *  - `name` is whatever the code *claims*; it is never evidence of identity.
 *    The UI must show the VPA, and the payer's own UPI app shows the real
 *    registered account name before they confirm — that is the verification.
 *  - `amountMinor` is a SUGGESTION. It must land in an editable field, never be
 *    paid silently.
 *  - Nothing here may be auto-submitted.
 */
export interface UpiTarget {
  vpa: string;
  /** Name claimed by the code. Not verified — see the note above. */
  name?: string | undefined;
  /** Suggested amount in minor units, when the code carried one. */
  amountMinor?: number | undefined;
  note?: string | undefined;
}

/** Why a scanned/typed string couldn't be used. */
export type UpiParseFailure =
  | "empty"
  | "not_upi"          // a URL/text that isn't a UPI payment target
  | "emvco"            // a Bharat QR / EMVCo TLV code — valid, but not upi://
  | "bad_vpa"          // looked like UPI but the payee id is malformed
  | "unsupported_currency";

export type UpiParseResult =
  | { ok: true; target: UpiTarget }
  | { ok: false; reason: UpiParseFailure };

/** UPI-intent query params also appear under app-specific schemes. */
const UPI_SCHEMES = ["upi:", "tez:", "phonepe:", "paytmmp:", "bhim:", "gpay:"];

/** EMVCo/Bharat QR starts with payload-format-indicator "000201". */
const looksEmvco = (s: string): boolean => /^000201/.test(s) && /^[0-9A-Za-z.\-\s]+$/.test(s.slice(0, 32));

/**
 * Parse major-unit money text ("1234.50") into minor units, strictly.
 *
 * Rejects negatives, non-finite values, >2dp, and absurd magnitudes. A QR that
 * says `am=1e9` or `am=-5` is malformed or hostile, and either way must not
 * pre-fill a payment box.
 */
function parseAmountMajor(raw: string): number | undefined {
  const s = raw.trim();
  if (!s || !/^\d{1,9}(\.\d{1,2})?$/.test(s)) return undefined;
  const minor = Math.round(Number(s) * 100);
  if (!Number.isFinite(minor) || minor <= 0) return undefined;
  return minor;
}

/**
 * Turn a typed UPI ID or a scanned QR payload into a payable target.
 *
 * Accepts a bare VPA (`someone@bank`) and the UPI intent URL that virtually
 * every Indian payment QR encodes (`upi://pay?pa=…`), including the
 * app-specific scheme variants. Everything else is refused with a reason the
 * UI can explain, rather than being coerced into a payment.
 */
export function parseUpiTarget(input: string): UpiParseResult {
  const raw = (input ?? "").trim();
  if (!raw) return { ok: false, reason: "empty" };

  // EMVCo first: a Bharat QR payload contains no "://" or "?", so it would
  // otherwise fall into the bare-VPA branch and be reported as a malformed
  // UPI ID — true but useless, when we can name what it actually is.
  if (looksEmvco(raw)) return { ok: false, reason: "emvco" };

  // Bare VPA, the typed case.
  if (!raw.includes("://") && !raw.includes("?")) {
    const vpa = normalizeVpa(raw);
    return isValidVpa(vpa) ? { ok: true, target: { vpa } } : { ok: false, reason: "bad_vpa" };
  }

  const lower = raw.toLowerCase();
  const scheme = UPI_SCHEMES.find((s) => lower.startsWith(s));
  if (!scheme) return { ok: false, reason: "not_upi" };

  // Parse by hand rather than with `new URL()`: custom schemes aren't
  // consistently parsed across engines, and we only need the query string.
  const q = raw.slice(raw.indexOf("?") + 1);
  if (raw.indexOf("?") === -1) return { ok: false, reason: "not_upi" };

  const params = new Map<string, string>();
  for (const pair of q.split("&")) {
    const eq = pair.indexOf("=");
    if (eq <= 0) continue;
    const k = pair.slice(0, eq).toLowerCase();
    if (params.has(k)) continue; // first wins; a duplicated `pa` is a spoof attempt
    try {
      params.set(k, decodeURIComponent(pair.slice(eq + 1).replace(/\+/g, " ")));
    } catch {
      params.set(k, pair.slice(eq + 1));
    }
  }

  const cu = params.get("cu");
  if (cu && cu.toUpperCase() !== UPI_CURRENCY) return { ok: false, reason: "unsupported_currency" };

  const vpa = normalizeVpa(params.get("pa") ?? "");
  if (!vpa) return { ok: false, reason: "not_upi" };
  if (!isValidVpa(vpa)) return { ok: false, reason: "bad_vpa" };

  const amountMinor = parseAmountMajor(params.get("am") ?? "");
  const name = (params.get("pn") ?? "").trim() || undefined;
  const note = (params.get("tn") ?? "").trim() || undefined;

  return { ok: true, target: { vpa, ...(name ? { name } : {}), ...(amountMinor ? { amountMinor } : {}), ...(note ? { note } : {}) } };
}
