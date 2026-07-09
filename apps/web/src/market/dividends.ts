import type { RateLookup } from "@pocketcare/ledger";
import type { CurrencyCode } from "@pocketcare/types";

export interface HoldingLite { symbol: string; exchange: string | null; quantity: number; currency: string }
export interface DivRow { symbol: string; exchange: string | null; ex_date: string; pay_date: string | null; amount: number; currency: string }

/** One dividend payment estimated in the user's base currency (minor units). */
export interface DivEvent { date: string; base: number; upcoming: boolean }

const key = (symbol: string, exchange: string | null) => `${symbol.toUpperCase()}|${(exchange ?? "").toUpperCase()}`;

/**
 * Estimate dividend income per ex-date in base currency: for each dividend row,
 * sum (amount-per-share × shares held) over matching holdings, converted to base.
 * Uses current quantity (a reasonable estimate; historical share counts aren't
 * tracked). Matches on symbol+exchange, falling back to symbol only.
 */
export function computeDividendEvents(holdings: HoldingLite[], dividends: DivRow[], getRate: RateLookup, base: CurrencyCode): DivEvent[] {
  const bySymEx = new Map<string, HoldingLite[]>();
  const bySym = new Map<string, HoldingLite[]>();
  const push = (m: Map<string, HoldingLite[]>, k: string, h: HoldingLite) => {
    const list = m.get(k); if (list) list.push(h); else m.set(k, [h]);
  };
  for (const h of holdings) {
    push(bySymEx, key(h.symbol, h.exchange), h);
    push(bySym, h.symbol.toUpperCase(), h);
  }
  const today = new Date().toISOString().slice(0, 10);
  const events: DivEvent[] = [];
  for (const d of dividends) {
    const matches = bySymEx.get(key(d.symbol, d.exchange)) ?? bySym.get(d.symbol.toUpperCase()) ?? [];
    if (matches.length === 0) continue;
    const shares = matches.reduce((s, h) => s + h.quantity, 0);
    if (shares <= 0) continue;
    const inCcy = d.amount * shares; // minor units in d.currency
    const rate = d.currency === base ? 1 : getRate(d.currency as CurrencyCode, base);
    events.push({ date: d.ex_date, base: Math.round(inCcy * rate), upcoming: d.ex_date >= today });
  }
  return events.sort((a, b) => a.date.localeCompare(b.date));
}

export type Period = "week" | "month" | "quarter" | "year" | "all";

export interface Bucket { label: string; key: string; value: number; upcoming: boolean }

function isoWeek(d: Date): string {
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(t.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((t.getTime() - yearStart.getTime()) / 86400000) + 1) / 7);
  return `${t.getUTCFullYear()}-W${String(week).padStart(2, "0")}`;
}
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Group events into period buckets. Recent windows are capped; "all" spans everything by year. */
export function bucketize(events: DivEvent[], period: Period): Bucket[] {
  const today = new Date();
  const map = new Map<string, Bucket>();
  const put = (k: string, label: string, v: number, upcoming: boolean) => {
    const cur = map.get(k);
    if (cur) { cur.value += v; cur.upcoming = cur.upcoming || upcoming; }
    else map.set(k, { key: k, label, value: v, upcoming });
  };
  for (const e of events) {
    const d = new Date(e.date + "T00:00:00");
    if (period === "week") put(isoWeek(d), `${MONTHS[d.getMonth()]} ${d.getDate()}`, e.base, e.upcoming);
    else if (period === "month") put(`${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`, `${MONTHS[d.getMonth()]} '${String(d.getFullYear()).slice(2)}`, e.base, e.upcoming);
    else if (period === "quarter") { const q = Math.floor(d.getMonth() / 3) + 1; put(`${d.getFullYear()}-Q${q}`, `Q${q} '${String(d.getFullYear()).slice(2)}`, e.base, e.upcoming); }
    else put(String(d.getFullYear()), String(d.getFullYear()), e.base, e.upcoming); // year & all → by year
  }
  const all = [...map.values()].sort((a, b) => a.key.localeCompare(b.key));
  const caps: Record<Period, number> = { week: 12, month: 12, quarter: 8, year: 6, all: 999 };
  return all.slice(-caps[period]);
}

/** Trailing-12-month realized income + projected next-12-month income (from scheduled + trailing run-rate). */
export function dividendSummary(events: DivEvent[]): { trailing12: number; upcoming12: number; total: number } {
  const now = Date.now();
  const yearMs = 365 * 86400000;
  let trailing12 = 0, upcoming12 = 0, total = 0;
  for (const e of events) {
    total += e.base;
    const t = new Date(e.date + "T00:00:00").getTime();
    if (t <= now && t >= now - yearMs) trailing12 += e.base;
    if (t > now && t <= now + yearMs) upcoming12 += e.base;
  }
  return { trailing12, upcoming12, total };
}
