/**
 * Investments domain model (pure, UI-agnostic).
 *
 * A "holding" is any tracked investment: a listed stock/MF, or a crypto coin,
 * fixed deposit, SIP, or other scheme. Holdings are grouped for display by
 * **exchange** (for listed stocks) and by **asset class** (everything else),
 * each group carrying invested / current / gain subtotals.
 */

export type AssetClass = "stock" | "mf" | "crypto" | "fd" | "sip" | "other";

export const ASSET_CLASSES: { key: AssetClass; label: string; icon: string; unitWord: string; listed: boolean }[] = [
  { key: "stock", label: "Stock", icon: "▤", unitWord: "shares", listed: true },
  { key: "mf", label: "Mutual fund", icon: "◈", unitWord: "units", listed: true },
  { key: "sip", label: "SIP", icon: "↻", unitWord: "units", listed: false },
  { key: "crypto", label: "Crypto", icon: "◇", unitWord: "coins", listed: false },
  { key: "fd", label: "Fixed deposit", icon: "▦", unitWord: "", listed: false },
  { key: "other", label: "Other scheme", icon: "✦", unitWord: "", listed: false },
];

export interface HoldingRow {
  id: string;
  account_id: string;
  symbol: string;
  exchange: string | null;
  quantity: number;
  avg_cost: number | null;
  currency: string;
  auto_fetch: number;
  instrument_type: string | null;
  off_list: number;
  name: string | null;
  asset_class: string | null;
  current_value: number | null;
  annual_rate: number | null;
  maturity_date: string | null;
  source_account_id: string | null;
  planned_id: string | null;
}

/** A minimal live quote (end-of-day price) for a listed instrument. */
export interface QuoteLite { price: number; currency: string; change_pct?: number | null }

export function assetClassOf(h: HoldingRow): AssetClass {
  const c = (h.asset_class || h.instrument_type || "stock") as AssetClass;
  return (["stock", "mf", "crypto", "fd", "sip", "other"] as AssetClass[]).includes(c) ? c : "other";
}

export function classMeta(c: AssetClass) {
  return ASSET_CLASSES.find((a) => a.key === c) ?? ASSET_CLASSES[ASSET_CLASSES.length - 1]!;
}

export function isListed(c: AssetClass): boolean {
  return c === "stock" || c === "mf";
}

/** Display label for a holding. */
export function holdingLabel(h: HoldingRow): string {
  if (h.off_list || !isListed(assetClassOf(h))) return h.name || h.symbol || "Investment";
  return h.symbol || h.name || "Holding";
}

/** Stable grouping key: listed stocks by exchange, everything else by class. */
export function groupKeyOf(h: HoldingRow): string {
  const c = assetClassOf(h);
  if (c === "stock") return `ex:${(h.exchange || "OTHER").toUpperCase()}`;
  return `cls:${c}`;
}

const CLASS_LABEL: Record<AssetClass, string> = {
  stock: "Stocks", mf: "Mutual Funds", crypto: "Crypto", fd: "Fixed Deposits", sip: "SIPs", other: "Other Schemes",
};

/** Human label for a group key. */
export function groupLabel(key: string): string {
  if (key.startsWith("ex:")) {
    const ex = key.slice(3);
    return ex === "OTHER" ? "Stocks (other)" : ex;
  }
  const c = key.slice(4) as AssetClass;
  return CLASS_LABEL[c] ?? "Investments";
}

/** Sort order for group tiles: exchanges first, then MF, SIP, crypto, FD, other. */
export function groupSort(key: string): number {
  if (key.startsWith("ex:")) return 0; // exchanges first (sub-sorted by label)
  const order: Record<string, number> = { mf: 10, sip: 11, crypto: 12, fd: 13, other: 14 };
  return order[key.slice(4)] ?? 20;
}

export interface Valuation { cost: number; value: number; gain: number; gainPct: number }

/**
 * Value a holding in its own currency (minor units).
 * - Listed & priced → live quote × quantity.
 * - Otherwise → the user-supplied current_value, else falls back to cost.
 */
export function valuation(h: HoldingRow, quote?: QuoteLite | null): Valuation {
  const cost = Math.round((h.avg_cost ?? 0) * h.quantity);
  const priced = !h.off_list && isListed(assetClassOf(h)) && quote;
  const value = priced ? Math.round(quote!.price * h.quantity) : (h.current_value ?? cost);
  const gain = value - cost;
  const gainPct = cost > 0 ? (gain / cost) * 100 : 0;
  return { cost, value, gain, gainPct };
}

export interface Group {
  key: string;
  label: string;
  holdings: HoldingRow[];
  cost: number;   // invested, in base currency (minor units)
  value: number;  // current, in base
  gain: number;
  gainPct: number;
}

/**
 * Bucket holdings into display groups with base-currency subtotals.
 * `convert(amountMinor, currency)` converts a holding-currency amount to base.
 * `quoteFor(h)` returns the live quote (or null) for a holding.
 */
export function buildGroups(
  holdings: HoldingRow[],
  convert: (amount: number, currency: string) => number,
  quoteFor: (h: HoldingRow) => QuoteLite | null | undefined,
): Group[] {
  const map = new Map<string, Group>();
  for (const h of holdings) {
    const key = groupKeyOf(h);
    let g = map.get(key);
    if (!g) { g = { key, label: groupLabel(key), holdings: [], cost: 0, value: 0, gain: 0, gainPct: 0 }; map.set(key, g); }
    const v = valuation(h, quoteFor(h));
    g.holdings.push(h);
    g.cost += convert(v.cost, h.currency);
    g.value += convert(v.value, h.currency);
  }
  const groups = [...map.values()];
  for (const g of groups) { g.gain = g.value - g.cost; g.gainPct = g.cost > 0 ? (g.gain / g.cost) * 100 : 0; }
  groups.sort((a, b) => groupSort(a.key) - groupSort(b.key) || a.label.localeCompare(b.label));
  return groups;
}

/** Portfolio grand totals in base currency (minor units). */
export function portfolioTotals(groups: Group[]): { cost: number; value: number; gain: number; gainPct: number } {
  const cost = groups.reduce((s, g) => s + g.cost, 0);
  const value = groups.reduce((s, g) => s + g.value, 0);
  const gain = value - cost;
  return { cost, value, gain, gainPct: cost > 0 ? (gain / cost) * 100 : 0 };
}

// --- Financial-year dividend helpers ---------------------------------------

/** Start (Apr 1) of the Indian financial year containing `d`. */
export function fyStart(d = new Date()): Date {
  const y = d.getMonth() >= 3 ? d.getFullYear() : d.getFullYear() - 1; // months: 0=Jan, 3=Apr
  return new Date(y, 3, 1);
}

/** "FY 2026–27" label for the financial year containing `d`. */
export function fyLabel(d = new Date()): string {
  const s = fyStart(d).getFullYear();
  return `FY ${s}–${String((s + 1) % 100).padStart(2, "0")}`;
}

/** Whether an ISO date string falls in the current financial year, on/before today. */
export function inCurrentFYToDate(iso: string, now = new Date()): boolean {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return false;
  return d >= fyStart(now) && d <= now;
}
