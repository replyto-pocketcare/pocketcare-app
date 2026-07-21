/**
 * Generic bank/card statement CSV/Excel(→CSV) parser. Rather than hard-coding
 * every Indian bank, it auto-detects the header row and maps columns by keyword
 * (date / narration / debit / credit / amount / balance) — which covers the
 * common shape used by HDFC, ICICI, SBI, Axis, Kotak, etc. The mapping is
 * returned so the UI can show it and let the user correct a wrong guess.
 */
import type { ColumnMapping, ParsedStatement, StatementKind, StatementTxn } from "./types";

/** Minimal CSV → rows (quotes, embedded commas/newlines). Auto-detects the
 *  delimiter (comma / semicolon / tab) from the first non-empty line. */
function parseRawCsv(text: string): string[][] {
  const src = text.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  const firstLine = src.split("\n").find((l) => l.trim()) ?? "";
  const delim = firstLine.includes("\t") ? "\t" : (firstLine.split(";").length > firstLine.split(",").length ? ";" : ",");
  const rows: string[][] = [];
  let row: string[] = [], field = "", inQuotes = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]!;
    if (inQuotes) {
      if (ch === '"') { if (src[i + 1] === '"') { field += '"'; i++; } else inQuotes = false; }
      else field += ch;
    } else if (ch === '"') inQuotes = true;
    else if (ch === delim) { row.push(field); field = ""; }
    else if (ch === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
    else field += ch;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

const RX = {
  date: /(^|\b)(date|txn date|value date|transaction date|posting date|tran date)\b/i,
  desc: /(narration|description|particular|remarks|details|transaction remarks|merchant|transaction detail)/i,
  debit: /(debit|withdrawal|withdrawl|paid out|dr amount|amount\s*\(dr\)|withdrawal amt)/i,
  credit: /(credit|deposit|paid in|cr amount|amount\s*\(cr\)|deposit amt)/i,
  amount: /^(amount|txn amount|transaction amount|amount\s*\(inr\))$/i,
  balance: /(balance|closing balance|running balance|available balance)/i,
  drcr: /^(dr\/?cr|type|transaction type|debit\/credit|indicator)$/i,
};

/** Tolerant number: strips symbols/commas, keeps sign + decimal. */
function num(v: string | undefined): number {
  if (!v) return 0;
  const cleaned = v.replace(/[^0-9.,\-]/g, "").replace(/,(?=\d{3}(\D|$))/g, "");
  const norm = cleaned.includes(",") && !cleaned.includes(".") ? cleaned.replace(",", ".") : cleaned.replace(/,/g, "");
  const n = Number.parseFloat(norm);
  return Number.isFinite(n) ? n : 0;
}

const MONTHS: Record<string, number> = { jan: 1, feb: 2, mar: 3, apr: 4, may: 5, jun: 6, jul: 7, aug: 8, sep: 9, oct: 10, nov: 11, dec: 12 };

/** Parse many date formats → ISO YYYY-MM-DD (or null). Assumes day-first (India). */
export function parseDate(s: string | undefined): string | null {
  if (!s) return null;
  const v = s.trim();
  let m: RegExpMatchArray | null;
  if ((m = v.match(/^(\d{4})-(\d{2})-(\d{2})/))) return `${m[1]}-${m[2]}-${m[3]}`;
  if ((m = v.match(/^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})/))) {
    const d = +m[1]!, mo = +m[2]!, y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo >= 1 && mo <= 12 && d >= 1 && d <= 31) return iso(y, mo, d);
  }
  if ((m = v.match(/^(\d{1,2})[-\s]([A-Za-z]{3})[A-Za-z]*[-\s'](\d{2,4})/))) {
    const d = +m[1]!, mo = MONTHS[m[2]!.toLowerCase()], y = m[3]!.length === 2 ? 2000 + +m[3]! : +m[3]!;
    if (mo && d >= 1 && d <= 31) return iso(y, mo, d);
  }
  return null;
}
const iso = (y: number, mo: number, d: number) => `${y}-${String(mo).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

/** Find the header row (most keyword hits) and map its columns. */
function detectMapping(rows: string[][]): { headerRow: number; mapping: ColumnMapping; drcrCol: number | null } {
  let best = -1, bestScore = 0, bestMap: ColumnMapping | null = null, bestDrcr: number | null = null;
  rows.slice(0, 25).forEach((row, i) => {
    const map: ColumnMapping = { date: null, description: null, debit: null, credit: null, amount: null, balance: null };
    let drcr: number | null = null, score = 0;
    row.forEach((cell, ci) => {
      const c = (cell || "").trim();
      const idx = String(ci);
      if (map.date == null && RX.date.test(c)) { map.date = idx; score++; }
      else if (map.description == null && RX.desc.test(c)) { map.description = idx; score++; }
      else if (map.debit == null && RX.debit.test(c)) { map.debit = idx; score++; }
      else if (map.credit == null && RX.credit.test(c)) { map.credit = idx; score++; }
      else if (map.balance == null && RX.balance.test(c)) { map.balance = idx; score++; }
      else if (map.amount == null && RX.amount.test(c)) { map.amount = idx; score++; }
      else if (drcr == null && RX.drcr.test(c)) { drcr = ci; }
    });
    if (score > bestScore) { bestScore = score; best = i; bestMap = map; bestDrcr = drcr; }
  });
  return { headerRow: best, mapping: bestMap ?? { date: null, description: null, debit: null, credit: null, amount: null, balance: null }, drcrCol: bestDrcr };
}

export function parseStatementCsv(text: string, opts: { currency: string; kind: StatementKind }): ParsedStatement {
  const rows = parseRawCsv(text).filter((r) => r.some((c) => (c || "").trim()));
  const warnings: string[] = [];
  const { headerRow, mapping, drcrCol } = detectMapping(rows);
  if (headerRow < 0 || mapping.date == null) {
    return { kind: opts.kind, label: "Statement", currency: opts.currency, period: { from: null, to: null }, txns: [], warnings: ["Couldn't find a transaction table — check the file has a header row with Date, Description and amount columns."], mapping };
  }
  const di = +mapping.date;
  const desci = mapping.description != null ? +mapping.description : -1;
  const dbi = mapping.debit != null ? +mapping.debit : -1;
  const cri = mapping.credit != null ? +mapping.credit : -1;
  const ami = mapping.amount != null ? +mapping.amount : -1;
  const bali = mapping.balance != null ? +mapping.balance : -1;
  if (dbi < 0 && cri < 0 && ami < 0) warnings.push("No amount column detected — pick one in the mapping.");

  const txns: StatementTxn[] = [];
  for (const row of rows.slice(headerRow + 1)) {
    const date = parseDate(row[di]);
    if (!date) continue; // skip preamble / totals / blank rows
    let amount = 0;
    if (dbi >= 0 || cri >= 0) {
      const debit = dbi >= 0 ? num(row[dbi]) : 0;
      const credit = cri >= 0 ? num(row[cri]) : 0;
      amount = credit - debit;
    } else if (ami >= 0) {
      let a = num(row[ami]);
      if (drcrCol != null) { const t = (row[drcrCol] || "").toLowerCase(); if (/dr|debit|w/.test(t)) a = -Math.abs(a); else if (/cr|credit|d(?!r)/.test(t)) a = Math.abs(a); }
      else if (/dr\b/i.test(row[ami] || "")) a = -Math.abs(a);
      amount = a;
    }
    if (amount === 0) continue;
    txns.push({
      date,
      description: (desci >= 0 ? row[desci] : "")?.trim() || "Transaction",
      amount: Math.round(amount * 100),
      balance: bali >= 0 && row[bali]?.trim() ? Math.round(num(row[bali]) * 100) : null,
    });
  }

  const dates = txns.map((t) => t.date).filter(Boolean).sort();
  const openingBalance = txns.find((t) => t.balance != null)?.balance ?? null;
  const closingBalance = [...txns].reverse().find((t) => t.balance != null)?.balance ?? null;
  if (txns.length === 0) warnings.push("No dated transactions found under the detected header.");
  return {
    kind: opts.kind,
    label: opts.kind === "card" ? "Card statement" : "Bank statement",
    currency: opts.currency,
    period: { from: dates[0] ?? null, to: dates[dates.length - 1] ?? null },
    openingBalance,
    closingBalance,
    txns,
    warnings,
    mapping,
  };
}
