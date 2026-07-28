/**
 * @pocketcare/upi — building UPI Intent deep links for peer-to-peer settle-up.
 *
 * WHY THIS IS A PACKAGE: the URL we produce is handed to a third-party UPI app
 * and we never see what happens next. A malformed link fails silently inside
 * someone else's software, where no amount of logging will help us. So the
 * construction is pure, isolated, and tested to death.
 *
 * WHAT THIS IS NOT: a payment integration. PocketCare never touches the money.
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
 * match a PocketCare settlement against their bank statement when something
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
  return cleaned || "PocketCare";
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
