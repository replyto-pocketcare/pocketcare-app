"use client";

/**
 * On-device PDF statement parsing. pdf.js is lazy-loaded from a CDN at runtime
 * (browser-cached, offline after first use) — nothing bundled, the raw statement
 * never leaves the device. Column-aware: we keep each text fragment's x-position
 * so amounts are mapped to the right column (Withdrawal vs Deposit vs Balance) —
 * the way Indian bank PDFs (ICICI/HDFC/SBI/Axis) lay them out — instead of
 * guessing the sign from a flattened line. Falls back to a line heuristic if no
 * header is found. Scanned images still need OCR (later phase).
 */
import type { ParsedStatement, StatementKind, StatementTxn } from "./types";

// Inline date parser (kept self-contained so this module is unit-testable;
// mirrors parseCsv.parseDate). Day-first (India). → ISO YYYY-MM-DD or null.
const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };
const isoD = (y: number, mo: number, d: number) => `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
function parseDate(s: string | undefined): string | null {
  if (!s) return null;
  const v = s.trim();
  let m: RegExpMatchArray | null;
  if ((m = v.match(/^(\d{4})-(\d{2})-(\d{2})/))) return `${m[1]}-${m[2]}-${m[3]}`;
  if ((m = v.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})/))) {
    const d = +m[1]!, mo = +m[2]!, y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return isoD(y, mo, d);
  }
  if ((m = v.match(/^(\d{1,2})[-\s]([A-Za-z]{3})[A-Za-z]*[-\s'](\d{2,4})/))) {
    const d = +m[1]!, mo = MONTHS[m[2]!.toLowerCase()], y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo && d >= 1 && d <= 31) return isoD(y, mo, d);
  }
  return null;
}

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

export interface PdfCell { x: number; str: string }
export type PdfRow = PdfCell[]; // cells ordered left→right

/** Extract page text as rows of positioned cells (grouped by y, sorted by x). */
export async function extractPdfRows(file: File, password?: string): Promise<PdfRow[]> {
  const pdfjs = await loadPdfjs();
  const data = new Uint8Array(await file.arrayBuffer());
  const doc = await pdfjs.getDocument({ data, password }).promise;
  const rows: PdfRow[] = [];
  for (let p = 1; p <= doc.numPages; p++) {
    const page = await doc.getPage(p);
    const content = await page.getTextContent();
    const byY = new Map<number, PdfCell[]>();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    for (const it of content.items as any[]) {
      if (!it.str || !it.str.trim()) continue;
      const y = Math.round(it.transform[5] / 2) * 2; // 2px bucket merges near-equal baselines
      (byY.get(y) ?? byY.set(y, []).get(y)!).push({ x: it.transform[4], str: it.str });
    }
    [...byY.entries()].sort((a, b) => b[0] - a[0]).forEach(([, cells]) => rows.push(cells.sort((a, b) => a.x - b.x)));
  }
  return rows;
}

/** Flatten rows to text lines (fallback / debug). */
export async function extractPdfText(file: File, password?: string): Promise<string> {
  const rows = await extractPdfRows(file, password);
  return rows.map((r) => r.map((c) => c.str).join(" ").replace(/\s+/g, " ").trim()).filter(Boolean).join("\n");
}

export async function isEncrypted(file: File): Promise<boolean> {
  try { await extractPdfRows(file); return false; }
  catch (e) { return /password/i.test((e as Error).message); }
}

// --- column-aware parsing (pure, unit-tested) -------------------------------

type Role = "date" | "desc" | "debit" | "credit" | "amount" | "balance" | "drcr";
const HDR: Record<Role, RegExp> = {
  date: /\bdate\b/i,
  desc: /narration|description|particular|remarks|details|transaction remarks/i,
  debit: /debit|withdrawal|withdrawl/i,
  credit: /credit|deposit/i,
  amount: /^\s*amount\b/i,
  balance: /balance/i,
  drcr: /^(dr\/?cr|type|indicator)$/i,
};
function num(s: string): number {
  const c = s.replace(/[^0-9.\-]/g, "");
  const n = Number.parseFloat(c);
  return Number.isFinite(n) ? n : 0;
}
const isMoney = (s: string) => /\d[\d,]*\.\d{2}\b/.test(s) && !/[a-z]{3,}/i.test(s.replace(/dr|cr/gi, ""));

interface HeaderCol { role: Role; x: number }

/** Find the header row and each detected column's x-position. */
function detectHeader(rows: PdfRow[]): { headerIdx: number; cols: HeaderCol[] } {
  let bestIdx = -1, bestCols: HeaderCol[] = [];
  rows.slice(0, 40).forEach((row, i) => {
    const seen = new Set<Role>();
    const cols: HeaderCol[] = [];
    for (const cell of row) {
      for (const role of Object.keys(HDR) as Role[]) {
        if (!seen.has(role) && HDR[role].test(cell.str)) { seen.add(role); cols.push({ role, x: cell.x }); break; }
      }
    }
    if (cols.length > bestCols.length) { bestCols = cols; bestIdx = i; }
  });
  return { headerIdx: bestIdx, cols: bestCols.sort((a, b) => a.x - b.x) };
}

/** Nearest column (by x) among a candidate set of roles. */
function nearest(cols: HeaderCol[], roles: Role[], x: number): Role | null {
  let best: Role | null = null, bestD = Infinity;
  for (const c of cols) {
    if (!roles.includes(c.role)) continue;
    const d = Math.abs(c.x - x);
    if (d < bestD) { bestD = d; best = c.role; }
  }
  return best;
}

/**
 * Column-aware parse. Assigns each money cell on a transaction row to the
 * nearest numeric column (debit / credit / amount / balance) by x, so credits
 * and debits keep their correct sign. Returns null if no usable header found
 * (caller falls back to the line heuristic).
 */
export function parseStatementRows(rows: PdfRow[], opts: { currency: string; kind: StatementKind }): ParsedStatement | null {
  const { headerIdx, cols } = detectHeader(rows);
  const roles = new Set(cols.map((c) => c.role));
  const hasNumeric = roles.has("debit") || roles.has("credit") || roles.has("amount");
  if (headerIdx < 0 || cols.length < 2 || !hasNumeric) return null;

  const numericRoles: Role[] = (["debit", "credit", "amount", "balance"] as Role[]).filter((r) => roles.has(r));
  const firstNumX = Math.min(...cols.filter((c) => numericRoles.includes(c.role)).map((c) => c.x));
  const drcrX = cols.find((c) => c.role === "drcr")?.x ?? null;

  const txns: StatementTxn[] = [];
  const warnings: string[] = ["PDF parsed with column detection — review a few rows to be sure the debits/credits look right."];
  for (const row of rows.slice(headerIdx + 1)) {
    // A transaction row has a date somewhere near the start.
    const dateCell = row.find((c) => parseDate(c.str));
    const date = dateCell ? parseDate(dateCell.str) : null;
    if (!date) continue;
    let debit = 0, credit = 0, amount = 0, balance = 0, drcr = "";
    const descParts: string[] = [];
    for (const cell of row) {
      if (cell === dateCell) continue;
      if (isMoney(cell.str)) {
        const role = nearest(cols, numericRoles, cell.x);
        const v = num(cell.str);
        if (role === "debit") debit = v;
        else if (role === "credit") credit = v;
        else if (role === "balance") balance = v;
        else if (role === "amount") amount = v;
        if (/\bcr\b/i.test(cell.str)) drcr = "cr"; else if (/\bdr\b/i.test(cell.str)) drcr = "dr";
      } else if (drcrX != null && Math.abs(cell.x - drcrX) < 12 && /^(dr|cr)$/i.test(cell.str.trim())) {
        drcr = cell.str.trim().toLowerCase();
      } else if (cell.x < firstNumX - 4) {
        descParts.push(cell.str); // left of the numeric columns = narration
      }
    }
    let signed = 0;
    if (roles.has("debit") || roles.has("credit")) signed = credit - debit;
    else if (amount) signed = drcr === "cr" ? Math.abs(amount) : drcr === "dr" ? -Math.abs(amount) : -amount;
    if (signed === 0) continue;
    txns.push({
      date,
      description: descParts.join(" ").replace(/\s+/g, " ").trim() || "Transaction",
      amount: Math.round(signed * 100),
      balance: roles.has("balance") && balance ? Math.round(balance * 100) : null,
    });
  }
  if (txns.length === 0) return null;
  const dates = txns.map((t) => t.date).sort();
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

const MONEY = /(?:₹|inr|rs\.?)?\s?(-?\d[\d,]*\.\d{2})(?:\s?(dr|cr))?/gi;

/** Fallback: parse flattened text lines when column detection fails. */
export function parseStatementText(text: string, opts: { currency: string; kind: StatementKind }): ParsedStatement {
  const txns: StatementTxn[] = [];
  const warnings: string[] = ["Couldn't detect statement columns — parsed line-by-line (less reliable). Review amounts, or try the CSV/Excel export."];
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

/** Parse a PDF file: column-aware first, line heuristic as fallback. */
export async function parsePdfStatement(file: File, opts: { currency: string; kind: StatementKind }, password?: string): Promise<ParsedStatement> {
  const rows = await extractPdfRows(file, password);
  const cols = parseStatementRows(rows, opts);
  if (cols && cols.txns.length) return cols;
  const text = rows.map((r) => r.map((c) => c.str).join(" ").replace(/\s+/g, " ").trim()).filter(Boolean).join("\n");
  return parseStatementText(text, opts);
}
