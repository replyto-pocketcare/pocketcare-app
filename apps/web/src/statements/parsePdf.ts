"use client";

/**
 * On-device PDF text extraction for statements. pdf.js is lazy-loaded from a CDN
 * at runtime (browser-cached, offline after first use) — same pattern as the
 * semantic categoriser and the instruments catalog — so nothing is bundled and
 * the raw statement never leaves the device. Best-effort: digital (text-layer)
 * PDFs parse well; scanned images won't (needs OCR — a later phase).
 */
import { parseDate } from "./parseCsv";
import type { ParsedStatement, StatementKind, StatementTxn } from "./types";

const PDFJS_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.4.168/build/pdf.min.mjs";
const WORKER_URL = "https://cdn.jsdelivr.net/npm/pdfjs-dist@4.4.168/build/pdf.worker.min.mjs";

// eslint-disable-next-line @typescript-eslint/no-explicit-any
let pdfjsLib: any = null;
async function loadPdfjs() {
  if (pdfjsLib) return pdfjsLib;
  const mod = await import(/* webpackIgnore: true */ PDFJS_URL);
  mod.GlobalWorkerOptions.workerSrc = WORKER_URL;
  pdfjsLib = mod;
  return mod;
}

/** Extract text as lines (grouped by y-position, ordered left-to-right). */
export async function extractPdfText(file: File, password?: string): Promise<string> {
  const pdfjs = await loadPdfjs();
  const data = new Uint8Array(await file.arrayBuffer());
  const doc = await pdfjs.getDocument({ data, password }).promise;
  const lines: string[] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const content = await page.getTextContent();
    const byRow = new Map<number, { x: number; s: string }[]>();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    for (const it of content.items as any[]) {
      if (!it.str) continue;
      const y = Math.round(it.transform[5]); // vertical position
      (byRow.get(y) ?? byRow.set(y, []).get(y)!).push({ x: it.transform[4], s: it.str });
    }
    [...byRow.entries()].sort((a, b) => b[0] - a[0]).forEach(([, cells]) => {
      lines.push(cells.sort((a, b) => a.x - b.x).map((c) => c.s).join(" ").replace(/\s+/g, " ").trim());
    });
  }
  return lines.filter(Boolean).join("\n");
}

/** True if the PDF is password-protected (so the UI can prompt). */
export async function isEncrypted(file: File): Promise<boolean> {
  try { await extractPdfText(file); return false; }
  catch (e) { return /password/i.test((e as Error).message); }
}

const MONEY = /(?:₹|inr|rs\.?)?\s?(-?\d[\d,]*\.\d{2})(?:\s?(dr|cr))?/gi;

/**
 * Best-effort parse of extracted statement TEXT (one row per line). For each
 * line that starts with a date, the trailing money tokens are the amount and
 * (optionally) the running balance; Dr/Cr markers or credit keywords set the
 * sign. Loses column fidelity, so it's a starting point users can review.
 */
export function parseStatementText(text: string, opts: { currency: string; kind: StatementKind }): ParsedStatement {
  const txns: StatementTxn[] = [];
  const warnings: string[] = ["PDF parsing is best-effort — review the transactions and amounts before importing."];
  for (const line of text.split("\n")) {
    const dm = line.match(/^\s*(\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}|\d{4}-\d{2}-\d{2}|\d{1,2}[-\s][A-Za-z]{3}[A-Za-z]*[-\s']\d{2,4})/);
    if (!dm) continue;
    const date = parseDate(dm[1]);
    if (!date) continue;
    const monies = [...line.matchAll(MONEY)];
    if (monies.length === 0) continue;
    const nums = monies.map((m) => ({ val: Number(m[1]!.replace(/,/g, "")), drcr: (m[2] || "").toLowerCase() }));
    const balance = nums.length >= 2 ? nums[nums.length - 1]!.val : null;
    const amtTok = nums.length >= 2 ? nums[nums.length - 2]! : nums[0]!;
    const rest = line.slice(dm[0].length).replace(MONEY, "").replace(/\s+/g, " ").trim();
    const credit = amtTok.drcr === "cr" || /salary|refund|reversal|received|credit|cashback|interest|neft cr|imps cr/i.test(rest);
    const signed = credit ? Math.abs(amtTok.val) : -Math.abs(amtTok.val);
    txns.push({ date, description: rest || "Transaction", amount: Math.round(signed * 100), balance: balance != null ? Math.round(balance * 100) : null });
  }
  const dates = txns.map((t) => t.date).sort();
  if (txns.length === 0) warnings.push("Couldn't read any transactions — this may be a scanned image (needs OCR) or an unusual layout. Try the CSV/Excel export instead.");
  return {
    kind: opts.kind,
    label: opts.kind === "card" ? "Card statement" : "Bank statement",
    currency: opts.currency,
    period: { from: dates[0] ?? null, to: dates[dates.length - 1] ?? null },
    openingBalance: txns.find((t) => t.balance != null)?.balance ?? null,
    closingBalance: [...txns].reverse().find((t) => t.balance != null)?.balance ?? null,
    txns,
    warnings,
  };
}
