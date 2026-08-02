/**
 * @sanvya/diagnostics — support-log types and redaction.
 *
 * WHY THIS EXISTS: on a laptop you can ask someone to open the console. On a
 * phone you cannot, so a sync failure is invisible to everyone — the user sees
 * "something's wrong with syncing" and we see nothing at all. This package
 * defines the shape of a captured support log and, critically, scrubs it.
 *
 * THE REDACTION IS THE POINT. This is a personal finance app: a support log
 * must never become a leak of someone's spending. The rule is to keep what
 * DIAGNOSES a problem (table names, operations, error codes, row ids, routes)
 * and drop what merely describes a person's life (amounts, merchants,
 * descriptions, emails, payment handles).
 *
 * Erasable TS only, so `node --experimental-strip-types` runs the tests.
 */

export const LOG_LEVELS = { error: "error", warn: "warn", info: "info" } as const;
export type LogLevel = (typeof LOG_LEVELS)[keyof typeof LOG_LEVELS];

export interface LogEntry {
  /** Epoch ms. */
  readonly at: number;
  readonly level: LogLevel;
  /** Where it came from: "sync", "console", "window", "app". */
  readonly scope: string;
  readonly message: string;
  /** Route the user was on, for reproducing. */
  readonly route?: string | undefined;
  /** Structured extras (already redacted). */
  readonly detail?: Record<string, unknown> | undefined;
}

/** Placeholder tokens — deliberately obvious in a log so nothing looks real. */
export const REDACTED = {
  amount: "[amount]",
  email: "[email]",
  vpa: "[upi-id]",
  token: "[token]",
  text: "[text]",
} as const;

/**
 * Keys whose VALUES are never diagnostic and often personal.
 * Matched case-insensitively, on substring, so `merchant_name` and
 * `raw_text` are both caught.
 */
const SENSITIVE_KEYS = [
  "amount", "total", "subtotal", "balance", "price", "share_amount", "paid_amount",
  "description", "note", "merchant", "title", "name", "label",
  "email", "vpa", "handle", "upi",
  "raw_text", "parsed_json", "token", "key", "secret", "password", "authorization",
];

const isSensitiveKey = (key: string): boolean => {
  const k = key.toLowerCase();
  return SENSITIVE_KEYS.some((s) => k.includes(s));
};

/**
 * Keys holding free-form prose. Their values get the full number-scrubbing
 * treatment, because a message can carry an amount anywhere in it — which is
 * exactly what the `expense_items ... total is 1258784` error did.
 */
const FREE_TEXT_KEYS = ["message", "msg", "error", "reason", "stack", "text", "body"];

const isFreeTextKey = (key: string): boolean => {
  const k = key.toLowerCase();
  return FREE_TEXT_KEYS.some((s) => k === s || k.endsWith(`_${s}`));
};

/** Anything that looks like an id stays — it's how we find the row. */
const UUID_RE = /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi;

/** Run `fn` with UUIDs stashed out of harm's way, then restore them. */
function preservingUuids(input: string, fn: (s: string) => string): string {
  const uuids: string[] = [];
  const masked = input.replace(UUID_RE, (m) => {
    uuids.push(m);
    return ` UUID${uuids.length - 1} `;
  });
  return fn(masked).replace(/ UUID(\d+) /g, (_, i) => uuids[Number(i)] ?? "");
}

/**
 * Strip credentials and contact details only. NEVER touches numbers.
 *
 * Used for values under keys we already know aren't money, where guessing from
 * shape would destroy the diagnosis. A PostgREST code like `23514` is
 * indistinguishable from an amount by shape alone — and it is the single most
 * useful thing in a sync failure.
 */
export function redactSecrets(input: string): string {
  if (!input) return "";
  return preservingUuids(input, (s) => {
    let out = s;
    out = out.replace(/\bBearer\s+[A-Za-z0-9._\-]+/gi, `Bearer ${REDACTED.token}`);
    out = out.replace(/\beyJ[A-Za-z0-9._\-]{20,}/g, REDACTED.token);
    out = out.replace(/\b(sk|pk|rzp|whsec)[-_][A-Za-z0-9_\-]{8,}/gi, REDACTED.token);
    // Emails before VPAs — an email is also `x@y` shaped.
    out = out.replace(/\b[\w.+-]+@[\w-]+\.[\w.-]{2,}\b/g, REDACTED.email);
    out = out.replace(/\b[\w.\-]{2,}@[a-z]{2,}\b/gi, REDACTED.vpa);
    return out;
  });
}

/**
 * Scrub a free-text string: secrets AND anything money-shaped.
 *
 * Used for log MESSAGES, where there is no key to say what a number means, so
 * we assume the worst. Losing a diagnostic code here is an acceptable price —
 * it also travels in the structured `detail`, which is scrubbed by key.
 */
export function redactText(input: string): string {
  if (!input) return "";
  return preservingUuids(redactSecrets(input), (s) => {
    let out = s;
    // Protect SQLSTATE / error codes before the money passes run. A serialised
    // PostgREST error arrives here as free text (`{"code":"42501",...}`) where
    // the 5-digit code is shape-identical to an amount — and it is the single
    // most useful field in the whole message.
    const codes: string[] = [];
    out = out.replace(/((?:"|')?\bcode(?:"|')?\s*[:=]\s*(?:"|')?)([A-Za-z0-9]{2,10})/gi, (_m, lead: string, code: string) => {
      codes.push(code);
      return `${lead} CODE${codes.length - 1} `;
    });
    // Symbol-prefixed, or a bare number with a decimal or thousands group.
    out = out.replace(/(?:₹|Rs\.?|INR|\$|€|£)\s*-?[\d,]+(?:\.\d{1,2})?/gi, REDACTED.amount);
    out = out.replace(/\b-?\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?\b/g, REDACTED.amount);
    out = out.replace(/\b-?\d+\.\d{1,2}\b/g, REDACTED.amount);
    // Long bare integers are minor-unit amounts (1258784 = ₹12,587.84).
    out = out.replace(/\b\d{4,}\b/g, REDACTED.amount);
    return out.replace(/ CODE(\d+) /g, (_, i) => codes[Number(i)] ?? "");
  });
}

/**
 * Scrub a structured object.
 *
 * Key-based rather than value-based wherever possible: knowing that
 * `share_amount` was present is diagnostic, knowing it was ₹4,284.90 is not.
 */
export function redactDetail(input: unknown, depth = 0): unknown {
  if (input === null || input === undefined) return input;
  if (depth > 4) return "[deep]";

  // Secrets-only here: `redactDetail` is called on values whose KEY already
  // told us they are not money, so the aggressive number pass would only
  // destroy diagnostic data (error codes, row counts, status codes).
  if (typeof input === "string") return redactSecrets(input);
  if (typeof input === "number" || typeof input === "boolean") return input;

  if (Array.isArray(input)) {
    // Cap arrays: a 200-row upload batch is noise, its length is the signal.
    const capped = input.slice(0, 10).map((v) => redactDetail(v, depth + 1));
    return input.length > 10 ? [...capped, `…+${input.length - 10} more`] : capped;
  }

  if (typeof input === "object") {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(input as Record<string, unknown>)) {
      out[k] = isSensitiveKey(k)
        ? redactedPlaceholderFor(v)
        : isFreeTextKey(k) && typeof v === "string"
          ? redactText(v)
          : redactDetail(v, depth + 1);
    }
    return out;
  }
  return String(input);
}

/** Keep the SHAPE of a redacted value — null vs missing vs present matters. */
function redactedPlaceholderFor(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === "number") return REDACTED.amount;
  return REDACTED.text;
}

/** Build a fully-scrubbed entry. The only supported way to create one. */
export function makeEntry(
  level: LogLevel,
  scope: string,
  message: string,
  opts: { route?: string | undefined; detail?: Record<string, unknown> | undefined; at?: number } = {},
): LogEntry {
  return {
    at: opts.at ?? Date.now(),
    level,
    scope,
    // Cap length: a stack trace or a giant JSON blob crowds out everything else.
    message: redactText(String(message)).slice(0, 500),
    ...(opts.route ? { route: opts.route } : {}),
    ...(opts.detail ? { detail: redactDetail(opts.detail) as Record<string, unknown> } : {}),
  };
}

/**
 * Render the log as plain text for copy/share.
 *
 * Plain text on purpose: it survives being pasted into WhatsApp, an email or a
 * GitHub issue, which is how it will actually reach us.
 */
export function formatLog(entries: readonly LogEntry[], context: Record<string, unknown> = {}): string {
  const head = Object.entries(context)
    .map(([k, v]) => `${k}: ${v ?? "—"}`)
    .join("\n");

  const body = entries.length === 0
    ? "(no events captured)"
    : entries
        .map((e) => {
          const time = new Date(e.at).toISOString().slice(11, 19);
          const detail = e.detail && Object.keys(e.detail).length > 0 ? ` ${JSON.stringify(e.detail)}` : "";
          const route = e.route ? ` (${e.route})` : "";
          return `${time} ${e.level.toUpperCase().padEnd(5)} [${e.scope}]${route} ${e.message}${detail}`;
        })
        .join("\n");

  return `Sanvya diagnostics\n${head}\n\n--- events (newest last, ${entries.length}) ---\n${body}`;
}
