/**
 * Text normalization and tokenization for the auto-categorization engine.
 *
 * Bank statement descriptions are noisy: UPI/IMPS/NEFT strings, POS terminal
 * dumps, long reference numbers, bank codes and VPA handles. Naively splitting
 * on spaces buries the one useful token — the merchant — under boilerplate, so
 * everything lands in "Uncategorized". We first strip the transport/rail noise
 * and pull out the merchant segment, then tokenize that.
 */

const STOP_WORDS = new Set([
  "the", "and", "or", "to", "for", "in", "on", "at", "with", "a", "an", "is", "of",
]);

/**
 * Payment-rail and bank boilerplate tokens that carry no categorization signal.
 * These appear in nearly every Indian bank/UPI/card line and would otherwise
 * pollute the token set (and occasionally false-match a seed).
 */
const NOISE_TOKENS = new Set([
  // rails / instruments
  "upi", "imps", "neft", "rtgs", "ach", "ecs", "pos", "atm", "emi", "nach", "vps", "mmt",
  "ift", "inb", "chq", "cheque", "clg", "int", "intl", "txn", "trf", "transfer", "tfr",
  "payment", "paytm", "gpay", "phonepe", "bhim", "razorpay", "billdesk", "payu",
  // direction / status
  "dr", "cr", "debit", "credit", "debited", "credited", "paid", "recd", "received",
  "rev", "reversal", "refund", "charge", "charges", "fee", "gst", "tax",
  // bank short codes (very common issuers/acquirers embedded in UPI strings)
  "hdfc", "hdfcbank", "icic", "icici", "sbin", "sbi", "axis", "axisbank", "kkbk", "kotak",
  "yesb", "pnb", "boi", "cnrb", "canara", "utib", "idfb", "idfc", "fdrl", "federal",
  "indb", "indus", "indusind", "barb", "baroda", "ubin", "union", "bank",
  // VPA suffixes / providers
  "ybl", "okhdfcbank", "okicici", "oksbi", "okaxis", "apl", "ibl", "axl", "paytmqr",
  "waaxis", "wahdfcbank", "yapl", "airtel", "freecharge", "jupiteraxis", "fam",
  // misc filler
  "ref", "refno", "no", "id", "num", "number", "acct", "account", "ac", "info", "rrn",
  "www", "com", "in", "ltd", "limited", "pvt", "private", "india", "online", "order",
  "purchase", "spent", "transaction", "vpa", "collect", "req", "mandate", "autopay",
]);

export interface NormalizedResult {
  /** Full cleaned phrase (used for exact learned-phrase lookups). */
  phrase: string;
  /** Signal tokens + bigrams for scoring (noise removed). */
  tokens: string[];
  /** Best-guess merchant blob for substring matching (letters only, no spaces). */
  merchant: string;
}

/** True if a token is pure noise (rail code, bank, ref word, or all-digits). */
function isNoise(tok: string): boolean {
  if (!tok) return true;
  if (NOISE_TOKENS.has(tok)) return true;
  if (STOP_WORDS.has(tok)) return true;
  // Reference numbers / long alphanumerics with lots of digits carry no signal.
  if (/\d/.test(tok) && tok.replace(/\D/g, "").length >= 4) return true;
  return false;
}

/**
 * Normalizes a description: lowercases, splits on the many delimiters banks use
 * (/, -, *, :, |, spaces), drops noise + reference tokens, and returns the
 * surviving merchant tokens plus a concatenated merchant blob for substring
 * matching. Digits inside merchant names (e.g. "5paisa") are preserved.
 */
export function normalizeText(text: string): NormalizedResult {
  if (!text) return { phrase: "", tokens: [], merchant: "" };

  const lower = text.toLowerCase();

  // A cleaned phrase (letters/digits/space) for exact learned-phrase matching —
  // keep this stable so previously learned phrase rules still resolve.
  const phrase = lower
    .replace(/[^\p{L}\p{N}\s]/gu, " ")
    .replace(/\s+/g, " ")
    .trim();

  // Split aggressively on every delimiter banks jam merchants between.
  const parts = lower
    .split(/[\s/\-*:|.,;#@()\[\]]+/u)
    .map((p) => p.trim())
    .filter(Boolean);

  // Keep tokens with signal: at least 3 letters, not pure noise/ref.
  const signal: string[] = [];
  for (const p of parts) {
    const letters = p.replace(/[^\p{L}]/gu, "");
    if (letters.length < 3) continue;
    if (isNoise(p)) continue;
    signal.push(p);
  }

  const tokenSet = new Set<string>();
  for (const w of signal) tokenSet.add(w);
  // Bigrams over surviving tokens capture "uber eats", "amazon prime", etc.
  for (let i = 0; i < signal.length - 1; i++) tokenSet.add(`${signal[i]} ${signal[i + 1]}`);

  // Merchant blob: letters-only concat of the signal tokens. Lets a contains
  // match catch "swiggylimited" / "amazonin" / "netflixcom" against a seed.
  const merchant = signal.map((s) => s.replace(/[^\p{L}]/gu, "")).join("");

  return { phrase, tokens: Array.from(tokenSet), merchant };
}
