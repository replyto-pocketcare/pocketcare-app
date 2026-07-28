"use client";

/**
 * Scan orchestrator — the pipeline the capture screen drives.
 *
 *   file → preprocess → OCR (or PDF text layer) → parse → reconcile
 *
 * Everything here runs on the device. The AI fallback (`escalate`) is a
 * separate, explicitly-invoked step: `scanReceipt` never sends the image
 * anywhere, it only reports whether escalating would be worth offering.
 */
import {
  parseReceipt,
  parseReceiptText,
  groupIntoLines,
  reconcile,
  shouldEscalate,
  subtotals,
  type ReceiptDraft,
} from "@pocketcare/receipts";

import { insertRow, updateRow } from "../write";
import { extractPdfRows, isEncrypted } from "../statements/parsePdf";
import { aiParseReceipt } from "./aiParse";
import { prepareImage, validateFile, type PreparedImage } from "./image";
import { runOcr } from "./ocr";

export const SCAN_STAGES = {
  preparing: "preparing",
  reading: "reading",
  understanding: "understanding",
  done: "done",
} as const;
export type ScanStage = (typeof SCAN_STAGES)[keyof typeof SCAN_STAGES];

export interface ScanProgress {
  readonly stage: ScanStage;
  /** 0-1 within the current stage, when known. */
  readonly fraction?: number;
}

export class ScanError extends Error {
  /** True when the PDF needs a password before we can read it. */
  readonly needsPassword: boolean;
  constructor(message: string, needsPassword = false) {
    super(message);
    this.name = "ScanError";
    this.needsPassword = needsPassword;
  }
}

export interface ScanResult {
  readonly draft: ReceiptDraft;
  /** Null for PDFs — there is no image to escalate with. */
  readonly image: PreparedImage | null;
  /** Whether to offer "Improve with AI". */
  readonly canEscalate: boolean;
  readonly reconciled: boolean;
}

export interface ScanOptions {
  /** User's base currency, used when the receipt doesn't print one. */
  readonly currency: string;
  readonly minorDigits?: number;
  readonly onProgress?: (p: ScanProgress) => void;
  /** For an encrypted PDF. */
  readonly password?: string;
}

/**
 * Read a receipt from a photo or PDF.
 *
 * PDFs with a text layer skip OCR entirely and are near-perfect — an emailed
 * bill is the single most accurate input this feature accepts, so it is worth
 * the special case.
 */
export async function scanReceipt(file: File, opts: ScanOptions): Promise<ScanResult> {
  const invalid = validateFile(file);
  if (invalid) throw new ScanError(invalid);

  const today = new Date().toISOString().slice(0, 10);
  const parseOpts = {
    currency: opts.currency,
    ...(opts.minorDigits !== undefined ? { minorDigits: opts.minorDigits } : {}),
    today,
  };

  if (file.type === "application/pdf") {
    opts.onProgress?.({ stage: "reading" });
    let rows;
    try {
      if (!opts.password && (await isEncrypted(file))) {
        throw new ScanError("This PDF is password protected.", true);
      }
      rows = await extractPdfRows(file, opts.password);
    } catch (e) {
      if (e instanceof ScanError) throw e;
      const msg = (e as Error).message ?? "";
      if (/password/i.test(msg)) throw new ScanError("This PDF is password protected.", true);
      throw new ScanError(`Couldn't read that PDF: ${msg}`);
    }

    opts.onProgress?.({ stage: "understanding" });
    const text = rows.map((r) => r.map((c) => c.str).join(" ")).join("\n");
    if (text.trim().length < 20) {
      // A scanned-image PDF. We could rasterize and OCR it, but the honest
      // answer is that a photo of the paper works better than a photo of a scan.
      throw new ScanError("That PDF has no readable text — try photographing the receipt instead.");
    }
    const draft = parseReceiptText(text, parseOpts);
    opts.onProgress?.({ stage: "done" });
    return {
      draft,
      image: null,
      canEscalate: false,
      reconciled: reconcile(draft).ok,
    };
  }

  opts.onProgress?.({ stage: "preparing" });
  const image = await prepareImage(file);

  opts.onProgress?.({ stage: "reading", fraction: 0 });
  const ocr = await runOcr(image.blob, (fraction) => opts.onProgress?.({ stage: "reading", fraction }));

  opts.onProgress?.({ stage: "understanding" });
  // Prefer geometry: rebuilding lines from word boxes handles the multi-column
  // layouts that a flattened text dump destroys. Fall back to the raw text if
  // this build of tesseract gave us no boxes.
  const draft =
    ocr.words.length > 0
      ? parseReceipt(groupIntoLines([...ocr.words]), { ...parseOpts, engine: "tesseract" })
      : parseReceiptText(ocr.text, { ...parseOpts, engine: "tesseract" });

  opts.onProgress?.({ stage: "done" });
  return {
    draft,
    image,
    canEscalate: shouldEscalate(draft),
    reconciled: reconcile(draft).ok,
  };
}

/**
 * Send the ORIGINAL photo for AI extraction. Called only from an explicit user
 * action; `scanReceipt` never calls this itself.
 */
export async function escalateToAi(
  image: PreparedImage,
  opts: { currency: string; minorDigits?: number; rawText?: string },
): Promise<ReceiptDraft> {
  return aiParseReceipt({
    base64: await image.base64(),
    mediaType: image.mediaType,
    currencyHint: opts.currency,
    ...(opts.minorDigits !== undefined ? { minorDigits: opts.minorDigits } : {}),
    ...(opts.rawText ? { rawText: opts.rawText } : {}),
    today: new Date().toISOString().slice(0, 10),
  });
}

// ---------------------------------------------------------------------------
// Persistence
//
// The draft is written to `receipt_scans` as soon as it exists so a refresh,
// a dropped tab or a navigation away doesn't lose the work. NO IMAGE BYTES are
// stored — `image_path` stays null (see docs/features/receipt-scanning.md).
// ---------------------------------------------------------------------------

export async function saveScan(
  draft: ReceiptDraft,
  source: "camera" | "upload",
): Promise<string> {
  const s = subtotals(draft.lines);
  return insertRow("receipt_scans", {
    source,
    engine: draft.engine,
    merchant: draft.merchant,
    occurred_at: draft.occurredAt,
    currency: draft.currency,
    subtotal: s.items,
    tax: s.tax,
    service_charge: s.serviceCharge,
    tip: s.tip,
    discount: s.discount,
    total: draft.total,
    confidence: draft.confidence,
    // Cap the raw text: a long grocery bill's OCR dump is not worth syncing in
    // full, and it is only ever used for re-parsing and debugging.
    raw_text: draft.rawText ? draft.rawText.slice(0, 8000) : null,
    parsed_json: JSON.stringify(draft),
    transaction_id: null,
    expense_id: null,
    image_path: null,
  });
}

/** Update a stored scan after re-parsing (e.g. the AI fallback replaced it). */
export async function updateScanDraft(scanId: string, draft: ReceiptDraft): Promise<void> {
  const s = subtotals(draft.lines);
  await updateRow("receipt_scans", scanId, {
    engine: draft.engine,
    merchant: draft.merchant,
    occurred_at: draft.occurredAt,
    currency: draft.currency,
    subtotal: s.items,
    tax: s.tax,
    service_charge: s.serviceCharge,
    tip: s.tip,
    discount: s.discount,
    total: draft.total,
    confidence: draft.confidence,
    parsed_json: JSON.stringify(draft),
  });
}

/** Link a scan to what it became, so the UI can badge it later. */
export async function linkScan(
  scanId: string,
  link: { transactionId?: string; expenseId?: string },
): Promise<void> {
  await updateRow("receipt_scans", scanId, {
    ...(link.transactionId ? { transaction_id: link.transactionId } : {}),
    ...(link.expenseId ? { expense_id: link.expenseId } : {}),
  });
}
