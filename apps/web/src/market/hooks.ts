"use client";

import { useQuery } from "@powersync/react";

export interface Quote { symbol: string; exchange: string | null; price: number; currency: string; change_abs: number | null; change_pct: number | null; as_of: string }
export interface Overview { symbol: string; exchange: string | null; dividend_yield: number | null; dividend_per_share: number | null; ex_dividend_date: string | null; pe: number | null }
export interface DividendRow { symbol: string; exchange: string | null; ex_date: string; pay_date: string | null; amount: number; currency: string }

const key = (symbol: string, exchange: string | null | undefined) => `${symbol.toUpperCase()}|${(exchange ?? "").toUpperCase()}`;

/** Look a value up by exact symbol+exchange, falling back to symbol-only. */
function lookup<T extends { symbol: string; exchange: string | null }>(bySymEx: Map<string, T>, bySym: Map<string, T>, symbol: string, exchange: string | null | undefined): T | undefined {
  return bySymEx.get(key(symbol, exchange)) ?? bySym.get(symbol.toUpperCase());
}

/** Global Alpha Vantage market data, indexed for holding lookups. */
export function useMarketData() {
  const { data: quotes = [] } = useQuery<Quote>("SELECT symbol, exchange, price, currency, change_abs, change_pct, as_of FROM market_quotes");
  const { data: overview = [] } = useQuery<Overview>("SELECT symbol, exchange, dividend_yield, dividend_per_share, ex_dividend_date, pe FROM market_overview");
  const { data: dividends = [] } = useQuery<DividendRow>("SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends");

  const qSymEx = new Map<string, Quote>(); const qSym = new Map<string, Quote>();
  for (const q of quotes) { qSymEx.set(key(q.symbol, q.exchange), q); qSym.set(q.symbol.toUpperCase(), q); }
  const oSymEx = new Map<string, Overview>(); const oSym = new Map<string, Overview>();
  for (const o of overview) { oSymEx.set(key(o.symbol, o.exchange), o); oSym.set(o.symbol.toUpperCase(), o); }

  // Next upcoming ex-dividend date per symbol (today or later).
  const today = new Date().toISOString().slice(0, 10);
  const nextDivSymEx = new Map<string, DividendRow>(); const nextDivSym = new Map<string, DividendRow>();
  for (const d of dividends) {
    if (d.ex_date < today) continue;
    const kx = key(d.symbol, d.exchange), ks = d.symbol.toUpperCase();
    const cx = nextDivSymEx.get(kx); if (!cx || d.ex_date < cx.ex_date) nextDivSymEx.set(kx, d);
    const cs = nextDivSym.get(ks); if (!cs || d.ex_date < cs.ex_date) nextDivSym.set(ks, d);
  }

  const latestAsOf = quotes.reduce<string | null>((m, q) => (m && m >= q.as_of ? m : q.as_of), null);

  return {
    hasData: quotes.length > 0,
    latestAsOf,
    quote: (symbol: string, exchange?: string | null) => lookup(qSymEx, qSym, symbol, exchange),
    overview: (symbol: string, exchange?: string | null) => lookup(oSymEx, oSym, symbol, exchange),
    nextDividend: (symbol: string, exchange?: string | null) => lookup(nextDivSymEx, nextDivSym, symbol, exchange),
    allDividends: dividends,
  };
}
