"use client";

/**
 * The opt-in AI fallback: send the receipt photo to the `receipt-scan` edge
 * function and map its structured reply into a `ReceiptDraft`.
 *
 * Only ever called after the user explicitly taps "Improve with AI" on a scan
 * that on-device OCR could not reconcile. This is the ONLY code path in the
 * feature where the image leaves the device.
 */
import type { ReceiptDraft, ReceiptLine, ReceiptLineKind } from "@pocketcare/receipts";
import { QTY_SCALE } from "@pocketcare/receipts";

import { getSupabase } from "../powersync";

/** Shape returned by the edge function's `emit_receipt` tool. */
interface AiLine {
  kind?: string;
  description?: string;
  quantity?: number | null;
  unit?: string | null;
  unit_price?: number | null;
  amount?: number;
}
interface AiReceipt {
  merchant?: string | null;
  date?: string | null;
  currency?: string;
  total?: number | null;
  confidence?: number;
  lines?: AiLine[];
}

export class AiScanError extends Error {
  /** Set when the user is out of credits, so the UI can offer the upgrade path. */
  readonly quotaExceeded: boolean;
  constructor(message: string, quotaExceeded = false) {
    super(message);
    this.name = "AiScanError";
    this.quotaExceeded = quotaExceeded;
  }
}

const VALID_KINDS: readonly string[] = ["item", "tax", "service_charge", "tip", "discount"];

/**
 * Major units to integer minor units.
 *
 * The model returns decimals as printed ("1234.56"), which is far more reliable
 * than asking it for minor units — but decimals must not survive contact with
 * the ledger, so they are converted here and nowhere else.
 */
function toMinor(value: number, minorDigits: number): number {
  return Math.round(value * 10 ** minorDigits);
}

function mapLine(raw: AiLine, index: number, minorDigits: number): ReceiptLine | null {
  if (typeof raw.amount !== "number" || !Number.isFinite(raw.amount)) return null;
  const kind: ReceiptLineKind = (VALID_KINDS.includes(String(raw.kind)) ? raw.kind : "item") as ReceiptLineKind;
  const amount = toMinor(raw.amount, minorDigits);
  return {
    id: `ai${index}`,
    kind,
    description: String(raw.description ?? "").trim() || kind.replace("_", " "),
    quantity:
      typeof raw.quantity === "number" && Number.isFinite(raw.quantity) && raw.quantity > 0
        ? Math.round(raw.quantity * QTY_SCALE)
        : null,
    unit: raw.unit ? String(raw.unit).trim().toLowerCase() : null,
    unitPrice:
      typeof raw.unit_price === "number" && Number.isFinite(raw.unit_price)
        ? toMinor(raw.unit_price, minorDigits)
        : null,
    // Belt and braces: the prompt asks for negative discounts, but a model that
    // forgets must not silently inflate the bill.
    amount: kind === "discount" ? -Math.abs(amount) : amount,
    confidence: 90,
  };
}

export interface AiScanOptions {
  readonly base64: string;
  readonly mediaType: string;
  readonly currencyHint: string;
  readonly minorDigits?: number;
  readonly today?: string;
  /** Raw OCR text from the on-device attempt, preserved on the returned draft. */
  readonly rawText?: string;
}

export async function aiParseReceipt(opts: AiScanOptions): Promise<ReceiptDraft> {
  const minorDigits = opts.minorDigits ?? 2;

  const { data, error } = await getSupabase().functions.invoke("receipt-scan", {
    body: {
      image: opts.base64,
      mediaType: opts.mediaType,
      currencyHint: opts.currencyHint,
      today: opts.today ?? new Date().toISOString().slice(0, 10),
    },
  });

  if (error) throw new AiScanError(await edgeFnMessage(error));

  const body = data as { error?: string; code?: string; receipt?: AiReceipt } | null;
  if (body?.error) throw new AiScanError(body.error, body.code === "quota_exceeded");
  if (!body?.receipt) throw new AiScanError("The scan came back empty. Try a clearer photo.");

  const r = body.receipt;
  const lines = (r.lines ?? [])
    .map((l, i) => mapLine(l, i, minorDigits))
    .filter((l): l is ReceiptLine => l !== null);

  return {
    merchant: r.merchant ? String(r.merchant).trim() : null,
    occurredAt: typeof r.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(r.date) ? r.date : null,
    currency: (r.currency ?? opts.currencyHint).toUpperCase(),
    lines,
    total: typeof r.total === "number" && Number.isFinite(r.total) ? toMinor(r.total, minorDigits) : null,
    confidence: typeof r.confidence === "number" ? Math.max(0, Math.min(100, Math.round(r.confidence))) : 80,
    engine: "claude",
    ...(opts.rawText ? { rawText: opts.rawText } : {}),
  };
}

/**
 * supabase-js collapses any non-2xx edge-function response into the opaque
 * "Edge Function returned a non-2xx status code". The real reason ({ error })
 * is in the response body, reachable via FunctionsHttpError.context.
 * Same unwrapping as `splits/write.ts` — see the note there.
 */
async function edgeFnMessage(error: unknown): Promise<string> {
  const ctx = (error as { context?: unknown }).context;
  if (ctx instanceof Response) {
    try {
      const body = await ctx.clone().json();
      if (body && typeof body.error === "string") return body.error;
    } catch {
      /* body wasn't JSON */
    }
    if (ctx.status === 401) return "Please sign in to use AI receipt reading.";
  }
  return (error as Error).message || "Couldn't reach the scanner. Check your connection.";
}
