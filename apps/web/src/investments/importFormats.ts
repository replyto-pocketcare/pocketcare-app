"use client";

/**
 * Broker holdings/P&L import.
 *
 * Deliberately NOT a set of hard-coded per-broker templates. Broker exports
 * are versioned by the broker, differ per segment (equity / MF / F&O), and
 * their exact headers are not published anywhere we can verify against — they
 * only exist inside a file you download while logged in. Hard-coding column
 * positions against guessed headers would break silently the first time a
 * broker reordered a column, and would be wrong for anyone on an older export.
 *
 * So this works the way `src/statements/parseCsv.ts` already does for banks:
 *   1. Find the header row (broker files carry a preamble of account/date rows).
 *   2. Map columns by KEYWORD, not position, using a synonym list per field.
 *   3. Report the mapping back so the UI can show it and let the user fix a
 *      wrong guess — which is what makes an unknown or changed format
 *      recoverable rather than a dead end.
 * Broker "profiles" below only add a recognisable NAME and a couple of
 * format-specific hints; nothing depends on matching one.
 */
import type { AssetClass } from "./model";

export type HoldingField =
  | "symbol" | "name" | "isin" | "exchange" | "assetClass"
  | "quantity" | "avgCost" | "buyValue" | "currentPrice" | "currentValue";

/** Column synonyms, richest-signal first. Matched case-insensitively against
 *  the header cell; `exact` entries must match the whole cell (so a bare
 *  "Price" never wins over "Average Price"). */
const SYNONYMS: { field: HoldingField; any?: RegExp; exact?: RegExp }[] = [
  { field: "isin", any: /\bisin\b/i },
  { field: "symbol", any: /\b(symbol|ticker|trading\s*symbol|scrip\s*code|instrument)\b/i },
  { field: "name", any: /\b(stock\s*name|scrip\s*name|security\s*name|company|scheme\s*name|fund\s*name|instrument\s*name|particulars)\b/i },
  { field: "exchange", exact: /^(exchange|exch)$/i },
  { field: "assetClass", exact: /^(asset\s*class|type|category|segment|instrument\s*type)$/i },
  { field: "quantity", any: /\b(quantity|qty\.?|units?|shares|balance\s*qty|closing\s*qty|quantity\s*available)\b/i },
  { field: "avgCost", any: /\b(avg\.?\s*(cost|price|buy\s*price|nav)|average\s*(cost|price|buy\s*price|nav)|buy\s*(avg|average)|cost\s*per\s*unit|purchase\s*price)\b/i },
  { field: "buyValue", any: /\b(buy\s*value|purchase\s*value|invested(\s*(value|amount))?|cost\s*value|total\s*cost|amount\s*invested)\b/i },
  { field: "currentPrice", any: /\b(ltp|last\s*traded\s*price|closing\s*price|current\s*price|market\s*price|nav\s*(as\s*on|today)?)\b/i },
  { field: "currentValue", any: /\b(cur\.?\s*val|current\s*value|market\s*value|closing\s*value|present\s*value|valuation)\b/i },
];

export interface BrokerProfile {
  id: string;
  label: string;
  /** Header cells that, seen together, identify this broker's export. Used for
   *  labelling and asset-class hints only — never for column positions. */
  signature: RegExp[];
  hint?: AssetClass;
}

/**
 * Recognised exports. These are best-effort fingerprints: an unrecognised file
 * still imports fine through the generic mapper below, so adding a broker here
 * is a nicety (a name in the UI), not a requirement.
 */
export const BROKERS: BrokerProfile[] = [
  { id: "zerodha", label: "Zerodha (Console)", signature: [/\binstrument\b/i, /\b(avg\.?\s*cost|cur\.?\s*val)\b/i] },
  { id: "zerodha_pnl", label: "Zerodha P&L (tradewise)", signature: [/\bisin\b/i, /\bbuy\s*value\b/i, /\bsell\s*value\b/i] },
  { id: "groww", label: "Groww", signature: [/\bstock\s*name\b/i, /\baverage\s*buy\s*price\b/i] },
  { id: "groww_mf", label: "Groww (mutual funds)", signature: [/\bscheme\s*name\b/i, /\bfolio\b/i], hint: "mf" },
  { id: "paytm", label: "Paytm Money", signature: [/\b(scrip|security)\s*name\b/i, /\b(avg|average)\s*price\b/i] },
  { id: "sanvya", label: "Sanvya template", signature: [/^symbol$/i, /^avg_cost$/i] },
];

export type ColumnMap = Partial<Record<HoldingField, number>>;

export interface ParsedHolding {
  symbol: string;
  name: string;
  isin: string | null;
  exchange: string | null;
  assetClass: AssetClass;
  quantity: number;
  /** Per-unit cost in MAJOR units (rupees), or null if the file didn't say. */
  avgCost: number | null;
  /** Whole-holding present value in MAJOR units, or null. */
  currentValue: number | null;
  /** 1-based row number in the source file, for error messages. */
  sourceRow: number;
}

export interface ParseResult {
  broker: BrokerProfile | null;
  headers: string[];
  /** Which source column each field was read from — surfaced for correction. */
  mapping: ColumnMap;
  holdings: ParsedHolding[];
  /** Rows that looked like data but could not be used, with the reason. */
  rejected: { row: number; reason: string }[];
}

/* ------------------------------- parsing -------------------------------- */

/** Split delimited text into rows. Handles quotes, CRLF, and tab/semicolon. */
export function splitRows(text: string): string[][] {
  const src = text.replace(/^﻿/, "").replace(/\r\n/g, "\n");
  const firstLine = src.split("\n").find((l) => l.trim()) ?? "";
  const delim = firstLine.includes("\t") ? "\t"
    : firstLine.split(";").length > firstLine.split(",").length ? ";" : ",";
  const rows: string[][] = [];
  let row: string[] = [], field = "", quoted = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i]!;
    if (quoted) {
      if (ch === '"') { if (src[i + 1] === '"') { field += '"'; i++; } else quoted = false; }
      else field += ch;
    } else if (ch === '"') quoted = true;
    else if (ch === delim) { row.push(field); field = ""; }
    else if (ch === "\n") { row.push(field); rows.push(row); row = []; field = ""; }
    else field += ch;
  }
  if (field || row.length) { row.push(field); rows.push(row); }
  return rows;
}

/** Tolerant number: strips currency symbols and thousands separators, accepts
 *  (1,234.50) as negative, and returns null for anything non-numeric. */
export function num(v: string | undefined): number | null {
  if (v == null) return null;
  const raw = v.trim();
  if (!raw || /^(-|n\/?a|nil|null)$/i.test(raw)) return null;
  const neg = /^\(.*\)$/.test(raw);
  const cleaned = raw.replace(/[()]/g, "").replace(/[^0-9.\-]/g, "");
  if (!cleaned || cleaned === "-" || cleaned === ".") return null;
  const n = Number(cleaned);
  if (!Number.isFinite(n)) return null;
  return neg ? -n : n;
}

function mapHeaders(cells: string[]): ColumnMap {
  const map: ColumnMap = {};
  cells.forEach((cell, i) => {
    const h = cell.trim();
    if (!h) return;
    for (const s of SYNONYMS) {
      if (map[s.field] !== undefined) continue;      // first match wins
      if (s.exact ? s.exact.test(h) : s.any!.test(h)) { map[s.field] = i; return; }
    }
  });
  return map;
}

/** A row is a usable header if it names an identity column AND a quantity. */
function headerScore(map: ColumnMap): number {
  const identity = map.symbol ?? map.name ?? map.isin;
  if (identity === undefined || map.quantity === undefined) return 0;
  return Object.keys(map).length;
}

function detectBroker(headers: string[]): BrokerProfile | null {
  const joined = headers.join(" | ");
  for (const b of BROKERS) {
    if (b.signature.every((rx) => rx.test(joined))) return b;
  }
  return null;
}

const CLASS_WORDS: { rx: RegExp; cls: AssetClass }[] = [
  { rx: /\b(mutual\s*fund|mf|scheme|folio|nav)\b/i, cls: "mf" },
  { rx: /\b(crypto|coin|token)\b/i, cls: "crypto" },
  { rx: /\b(fd|fixed\s*deposit)\b/i, cls: "fd" },
  { rx: /\bsip\b/i, cls: "sip" },
  { rx: /\b(stock|equity|share)\b/i, cls: "stock" },
];

function classFrom(text: string, fallback: AssetClass): AssetClass {
  for (const c of CLASS_WORDS) if (c.rx.test(text)) return c.cls;
  return fallback;
}

/**
 * Parse a broker export into canonical holdings.
 *
 * `override` lets the UI re-parse with a user-corrected mapping, which is the
 * escape hatch for a format we guessed wrong.
 */
export function parseHoldingsFile(text: string, override?: ColumnMap): ParseResult {
  return parseHoldingRows(splitRows(text), override);
}

/** Same parser, fed pre-split rows — the path .xlsx sheets take, since they
 *  arrive as cells already and must not be round-tripped through CSV text
 *  (a name containing a comma would split into two columns). */
export function parseHoldingRows(input: string[][], override?: ColumnMap): ParseResult {
  const rows = input.filter((r) => r.some((c) => (c ?? "").trim() !== ""));
  const rejected: { row: number; reason: string }[] = [];
  if (rows.length === 0) {
    return { broker: null, headers: [], mapping: {}, holdings: [], rejected: [{ row: 0, reason: "File is empty" }] };
  }

  // Broker files open with a preamble (client id, period, disclaimers), so the
  // header is "the best-scoring row in the first 30", not "row 0".
  let headerIdx = 0, best = 0, mapping: ColumnMap = {};
  const limit = Math.min(rows.length, 30);
  for (let i = 0; i < limit; i++) {
    const m = mapHeaders(rows[i]!);
    const score = headerScore(m);
    if (score > best) { best = score; headerIdx = i; mapping = m; }
  }
  // A user-supplied mapping is authoritative and must be applied even when
  // auto-detection found nothing — rescuing an unreadable file is the whole
  // point of the override, so bailing out before merging it would defeat it.
  if (override) mapping = { ...mapping, ...override };
  // Drop "not in file" selections (-1) so they don't read column -1.
  for (const k of Object.keys(mapping) as HoldingField[]) {
    if ((mapping[k] ?? -1) < 0) delete mapping[k];
  }

  const headers = (rows[headerIdx] ?? []).map((h) => h.trim());
  if (headerScore(mapping) === 0) {
    return {
      broker: null, headers, mapping: {}, holdings: [],
      rejected: [{ row: headerIdx + 1, reason: "No column holding a name or symbol, paired with a quantity" }],
    };
  }

  const broker = detectBroker(headers);
  const fileHint: AssetClass = broker?.hint ?? classFrom(headers.join(" "), "stock");

  const at = (r: string[], f: HoldingField): string | undefined => {
    const i = mapping[f];
    return i === undefined ? undefined : r[i];
  };

  const holdings: ParsedHolding[] = [];
  for (let i = headerIdx + 1; i < rows.length; i++) {
    const r = rows[i]!;
    const rowNo = i + 1;
    const symbol = (at(r, "symbol") ?? "").trim();
    const name = (at(r, "name") ?? "").trim();
    const isin = (at(r, "isin") ?? "").trim();
    if (!symbol && !name && !isin) continue;                 // blank/spacer row

    // Broker files end with totals ("Total", "Grand Total") — same shape as a
    // data row but meaningless as a holding, and they'd double the portfolio.
    if (/^\s*(grand\s*)?total\b/i.test(symbol || name)) continue;

    const quantity = num(at(r, "quantity"));
    if (quantity === null || quantity === 0) {
      rejected.push({ row: rowNo, reason: `No usable quantity for "${symbol || name || isin}"` });
      continue;
    }

    let avgCost = num(at(r, "avgCost"));
    if (avgCost === null) {
      // Fall back to buy value / quantity — how most P&L (rather than holdings)
      // exports express cost.
      const buy = num(at(r, "buyValue"));
      if (buy !== null && quantity !== 0) avgCost = Math.abs(buy / quantity);
    }

    let currentValue = num(at(r, "currentValue"));
    if (currentValue === null) {
      const px = num(at(r, "currentPrice"));
      if (px !== null) currentValue = px * quantity;
    }

    holdings.push({
      symbol: symbol || isin || name,
      name: name || symbol || isin,
      isin: isin || null,
      exchange: (at(r, "exchange") ?? "").trim().toUpperCase() || null,
      assetClass: classFrom(`${at(r, "assetClass") ?? ""} ${name}`, fileHint),
      quantity: Math.abs(quantity),
      avgCost,
      currentValue,
      sourceRow: rowNo,
    });
  }

  return { broker, headers, mapping, holdings, rejected };
}

/* ------------------------------- template ------------------------------- */

export const TEMPLATE_HEADERS = ["symbol", "name", "isin", "exchange", "asset_class", "quantity", "avg_cost", "current_value"];

/**
 * The fill-in-yourself file, for a broker we can't read (or a PDF-only export).
 * Ships with two example rows so the expected shape is obvious without docs —
 * they're clearly marked and the importer drops them if left in.
 */
export function templateCsv(): string {
  const rows = [
    TEMPLATE_HEADERS,
    ["EXAMPLE-INFY", "Infosys Ltd", "INE009A01021", "NSE", "stock", "25", "1450.50", "39250"],
    ["EXAMPLE-PPFAS", "Parag Parikh Flexi Cap", "INF879O01027", "", "mf", "310.482", "62.15", "21500"],
  ];
  return rows.map((r) => r.map((c) => (/[",\n]/.test(c) ? `"${c.replace(/"/g, '""')}"` : c)).join(",")).join("\r\n");
}

/** Example rows are dropped so a user who downloads, adds their own rows and
 *  uploads without deleting ours doesn't silently import fake holdings. */
export const isExampleRow = (h: ParsedHolding): boolean => /^EXAMPLE-/i.test(h.symbol);
