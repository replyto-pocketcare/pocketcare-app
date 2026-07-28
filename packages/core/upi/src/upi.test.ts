import { test } from "node:test";
import assert from "node:assert/strict";

import {
  buildIntentUrl,
  buildQrPayload,
  canPayViaUpi,
  formatAmount,
  isValidRef,
  isValidVpa,
  maskVpa,
  newPaymentRef,
  normalizeVpa,
  UpiError,
} from "./index.ts";

const params = (over: Partial<Parameters<typeof buildIntentUrl>[0]> = {}) => ({
  vpa: "akhilesh@okhdfcbank",
  name: "Akhilesh",
  amountMinor: 43000,
  ref: "PCABC123XYZ",
  ...over,
});

/** Pull one query param back out of a built intent URL. */
function param(url: string, key: string): string | null {
  const q = url.slice(url.indexOf("?") + 1);
  for (const pair of q.split("&")) {
    const [k, v = ""] = pair.split("=");
    if (k === key) return decodeURIComponent(v);
  }
  return null;
}

// ---------------------------------------------------------------------------
// VPA validation
// ---------------------------------------------------------------------------

test("isValidVpa: accepts the handle shapes real PSPs issue", () => {
  for (const v of [
    "akhilesh@okhdfcbank",
    "9876543210@ybl",
    "a.b_c-d@paytm",
    "user123@axl",
    "x@sbi",
    "AKHILESH@OKAXIS",
  ]) {
    assert.equal(isValidVpa(v), true, v);
  }
});

test("isValidVpa: rejects malformed addresses", () => {
  for (const v of [
    "",
    "akhilesh",           // no handle
    "@okhdfcbank",        // no name
    "akhilesh@",          // no handle
    "a@b@c",              // two separators
    "akhilesh @okhdfc",   // space
    ".akhilesh@okhdfc",   // leading dot
    "akhilesh.@okhdfc",   // trailing dot
    "akhi..lesh@okhdfc",  // double dot
    "akhilesh@.okhdfc",   // handle starts with a dot
    "akhilesh@okhdfc.",   // handle ends with a dot
    "akhilesh@1bank",     // handle must start with a letter
  ]) {
    assert.equal(isValidVpa(v), false, v);
  }
});

test("isValidVpa: rejects absurd lengths", () => {
  assert.equal(isValidVpa("a".repeat(200) + "@ybl"), false);
  assert.equal(isValidVpa("a@b"), false); // handle too short to be a real PSP
});

test("normalizeVpa: trims and lowercases so duplicates collapse", () => {
  assert.equal(normalizeVpa("  Akhilesh@OKHDFCBANK "), "akhilesh@okhdfcbank");
});

// ---------------------------------------------------------------------------
// Masking
// ---------------------------------------------------------------------------

test("maskVpa: keeps the handle but hides most of the name", () => {
  assert.equal(maskVpa("akhilesh@okhdfcbank"), "akh••••@okhdfcbank");
});

test("maskVpa: short names don't leak more than their first character", () => {
  assert.equal(maskVpa("ab@ybl"), "a••••@ybl");
});

test("maskVpa: garbage in, no crash and nothing revealed", () => {
  assert.equal(maskVpa("nonsense"), "••••");
  assert.equal(maskVpa(""), "••••");
});

// ---------------------------------------------------------------------------
// Amounts — the highest-consequence conversion in the package
// ---------------------------------------------------------------------------

test("formatAmount: minor units become two-decimal rupees", () => {
  assert.equal(formatAmount(43000), "430.00");
  assert.equal(formatAmount(1), "0.01");
  assert.equal(formatAmount(100), "1.00");
  assert.equal(formatAmount(99), "0.99");
  assert.equal(formatAmount(123456), "1234.56");
});

test("formatAmount: never groups thousands (UPI apps mis-read it)", () => {
  assert.equal(formatAmount(150000000).includes(","), false);
  assert.equal(formatAmount(150000000), "1500000.00");
});

test("formatAmount: rejects zero, negative and non-integer amounts", () => {
  assert.throws(() => formatAmount(0), UpiError);
  assert.throws(() => formatAmount(-100), UpiError);
  assert.throws(() => formatAmount(43.5), UpiError);
});

// ---------------------------------------------------------------------------
// Reference
// ---------------------------------------------------------------------------

test("newPaymentRef: PC-prefixed, alphanumeric, statement-safe", () => {
  const ref = newPaymentRef();
  assert.match(ref, /^PC[A-Z1-9]{10}$/);
  assert.equal(isValidRef(ref), true);
});

test("newPaymentRef: avoids visually ambiguous characters", () => {
  // 0/O confusion turns a support conversation into a guessing game.
  let seq = 0;
  const ref = newPaymentRef(() => { const v = seq / 40; seq++; return v % 1; });
  assert.equal(/[O0]/.test(ref.slice(2)), false);
});

test("isValidRef: rejects punctuation some PSPs silently drop", () => {
  assert.equal(isValidRef("PC-ABC"), false);
  assert.equal(isValidRef("PC ABC"), false);
  assert.equal(isValidRef(""), false);
  assert.equal(isValidRef("A".repeat(36)), false);
});

// ---------------------------------------------------------------------------
// Intent URL
// ---------------------------------------------------------------------------

test("buildIntentUrl: emits the NPCI parameters with correct values", () => {
  const { url, ref } = buildIntentUrl(params());
  assert.ok(url.startsWith("upi://pay?"));
  assert.equal(param(url, "pa"), "akhilesh@okhdfcbank");
  assert.equal(param(url, "pn"), "Akhilesh");
  assert.equal(param(url, "am"), "430.00");
  assert.equal(param(url, "cu"), "INR");
  assert.equal(param(url, "tr"), "PCABC123XYZ");
  assert.equal(ref, "PCABC123XYZ");
});

test("buildIntentUrl: generates a reference when none is supplied", () => {
  const { url, ref } = buildIntentUrl(params({ ref: undefined }));
  assert.match(ref, /^PC[A-Z1-9]{10}$/);
  assert.equal(param(url, "tr"), ref);
});

test("buildIntentUrl: the note is included and percent-encoded", () => {
  const { url } = buildIntentUrl(params({ note: "Dinner at Spice Garden" }));
  assert.equal(param(url, "tn"), "Dinner at Spice Garden");
  // Spaces must be %20, never "+", which some apps render literally.
  assert.equal(url.includes("+"), false);
  assert.ok(url.includes("%20"));
});

test("buildIntentUrl: strips characters that would break the query string", () => {
  const { url } = buildIntentUrl(params({ note: "A&B=C?D#E 100%" }));
  const tn = param(url, "tn")!;
  for (const ch of ["&", "=", "?", "#", "%"]) {
    assert.equal(tn.includes(ch), false, `note should not contain ${ch}`);
  }
  // And the URL still parses back into exactly the parameters we set.
  assert.equal(param(url, "pa"), "akhilesh@okhdfcbank");
  assert.equal(param(url, "am"), "430.00");
});

test("buildIntentUrl: an injected note cannot forge another parameter", () => {
  const { url } = buildIntentUrl(params({ note: "x&am=1.00&pa=attacker@ybl" }));
  // Exactly one am= and one pa=, still holding our values.
  assert.equal(url.split("am=").length - 1, 1);
  assert.equal(url.split("pa=").length - 1, 1);
  assert.equal(param(url, "am"), "430.00");
  assert.equal(param(url, "pa"), "akhilesh@okhdfcbank");
});

test("buildIntentUrl: a name with punctuation is sanitised, not dropped", () => {
  const { url } = buildIntentUrl(params({ name: "Priya & Co." }));
  assert.equal(param(url, "pn"), "Priya Co.");
});

test("buildIntentUrl: an empty name falls back rather than sending pn=", () => {
  const { url } = buildIntentUrl(params({ name: "   " }));
  assert.equal(param(url, "pn"), "PocketCare");
});

test("buildIntentUrl: unicode names survive encoding", () => {
  const { url } = buildIntentUrl(params({ name: "अखिलेश" }));
  assert.equal(param(url, "pn"), "अखिलेश");
});

test("buildIntentUrl: long notes and names are truncated to PSP-safe lengths", () => {
  const { url } = buildIntentUrl(params({ note: "x".repeat(200), name: "y".repeat(200) }));
  assert.equal(param(url, "tn")!.length, 50);
  assert.equal(param(url, "pn")!.length, 50);
});

test("buildIntentUrl: no note means no tn parameter at all", () => {
  const { url } = buildIntentUrl(params({ note: "   " }));
  assert.equal(param(url, "tn"), null);
});

test("buildIntentUrl: refuses a non-INR currency", () => {
  assert.throws(() => buildIntentUrl(params({ currency: "USD" })), UpiError);
});

test("buildIntentUrl: refuses an invalid VPA", () => {
  assert.throws(() => buildIntentUrl(params({ vpa: "not-a-vpa" })), UpiError);
});

test("buildIntentUrl: refuses a zero or negative amount", () => {
  assert.throws(() => buildIntentUrl(params({ amountMinor: 0 })), UpiError);
  assert.throws(() => buildIntentUrl(params({ amountMinor: -100 })), UpiError);
});

test("buildIntentUrl: normalises the VPA before embedding it", () => {
  const { url } = buildIntentUrl(params({ vpa: "  Akhilesh@OKHDFCBANK  " }));
  assert.equal(param(url, "pa"), "akhilesh@okhdfcbank");
});

test("buildQrPayload: identical to the intent URL (one code path)", () => {
  const p = params();
  assert.equal(buildQrPayload(p).url, buildIntentUrl(p).url);
});

// ---------------------------------------------------------------------------
// Gate
// ---------------------------------------------------------------------------

test("canPayViaUpi: only for INR, a real amount, and a saved handle", () => {
  assert.equal(canPayViaUpi({ currency: "INR", amountMinor: 100, hasHandle: true }), true);
  assert.equal(canPayViaUpi({ currency: "EUR", amountMinor: 100, hasHandle: true }), false);
  assert.equal(canPayViaUpi({ currency: "INR", amountMinor: 0, hasHandle: true }), false);
  assert.equal(canPayViaUpi({ currency: "INR", amountMinor: 100, hasHandle: false }), false);
});
