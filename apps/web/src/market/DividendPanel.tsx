"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@powersync/react";
import { BarChart, Bar, XAxis, YAxis, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { useBaseCurrency, useRates } from "../hooks";
import { useMoneyFmt } from "../ui/Money";
import { computeDividendEvents, bucketize, dividendSummary, type Period, type HoldingLite, type DivRow } from "./dividends";

const PERIODS: { id: Period; label: string }[] = [
  { id: "week", label: "Week" }, { id: "month", label: "Month" }, { id: "quarter", label: "Quarter" },
  { id: "year", label: "Year" }, { id: "all", label: "All" },
];

export function DividendPanel() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const getRate = useRates();
  const [period, setPeriod] = useState<Period>("month");

  const { data: holdings = [] } = useQuery<HoldingLite>("SELECT symbol, exchange, quantity, currency FROM holdings WHERE deleted_at IS NULL");
  const { data: dividends = [] } = useQuery<DivRow>("SELECT symbol, exchange, ex_date, pay_date, amount, currency FROM market_dividends");

  const events = useMemo(() => computeDividendEvents(holdings, dividends, getRate, base as CurrencyCode), [holdings, dividends, getRate, base]);
  const buckets = useMemo(() => bucketize(events, period), [events, period]);
  const summary = useMemo(() => dividendSummary(events), [events]);

  if (holdings.length === 0) return null;

  const empty = events.length === 0;
  const money0 = (v: number) => fmt(money(Math.round(v), base), "en-US");

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <h2 style={{ margin: 0 }}>Dividend income</h2>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {PERIODS.map((p) => (
            <button key={p.id} className="chip" data-active={p.id === period} onClick={() => setPeriod(p.id)}>{p.label}</button>
          ))}
        </div>
      </div>

      <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
        <Stat label="Last 12 months" value={money0(summary.trailing12)} />
        <Stat label="Next 12 months (est.)" value={money0(summary.upcoming12)} accent />
        <Stat label="All-time" value={money0(summary.total)} />
      </div>

      {empty ? (
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>
          No dividend data yet. Once the daily market sync fetches dividend history for your holdings, income by period will appear here.
        </p>
      ) : (
        <div style={{ height: 220, marginLeft: -8 }}>
          <ResponsiveContainer width="100%" height="100%">
            <BarChart data={buckets} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
              <defs>
                <linearGradient id="gDiv" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#5f7a52" stopOpacity={0.95} /><stop offset="100%" stopColor="#5f7a52" stopOpacity={0.5} /></linearGradient>
                <linearGradient id="gDivUp" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#c08a3e" stopOpacity={0.9} /><stop offset="100%" stopColor="#c08a3e" stopOpacity={0.45} /></linearGradient>
              </defs>
              <XAxis dataKey="label" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--text-2)" }} interval="preserveStartEnd" />
              <YAxis hide />
              <Tooltip
                cursor={{ fill: "var(--surface-2)" }}
                contentStyle={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, fontSize: 12 }}
                formatter={(v: number) => [money0(v), "Income"]}
              />
              <Bar dataKey="value" radius={[6, 6, 0, 0]} maxBarSize={40}>
                {buckets.map((b, i) => <Cell key={i} fill={b.upcoming ? "url(#gDivUp)" : "url(#gDiv)"} />)}
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        </div>
      )}

      <p className="muted" style={{ fontSize: 11, margin: 0 }}>
        Estimated from your current share counts × Alpha Vantage dividend history. Amber bars are upcoming (scheduled ex-dates).
      </p>
    </section>
  );
}

function Stat({ label, value, accent }: { label: string; value: string; accent?: boolean }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 12 }}>{label}</div>
      <div style={{ fontSize: 20, fontFamily: "var(--font-serif)", fontWeight: 750, color: accent ? "var(--accent)" : "var(--text)" }}>{value}</div>
    </div>
  );
}
