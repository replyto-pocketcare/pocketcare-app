"use client";

import { useMemo, useState } from "react";
import { useQuery } from "@powersync/react";
import { AreaChart, Area, XAxis, YAxis, ResponsiveContainer, Tooltip } from "recharts";
import { money, fromMajor } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { useBaseCurrency, useRates } from "../hooks";
import { useMoneyFmt } from "../ui/Money";
import { useMarketData } from "./hooks";
import { computeDividendEvents, dividendSummary, type HoldingLite } from "./dividends";

interface HoldRow extends HoldingLite { avg_cost: number | null }

/**
 * Projects future portfolio wealth: current value compounded at an assumed
 * growth rate, plus monthly contributions, plus (optionally) reinvested
 * dividends estimated from the holding's dividend history. All assumptions are
 * user-adjustable — this is guidance, not a guarantee.
 */
export function ProjectionPanel() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const getRate = useRates();
  const market = useMarketData();

  const { data: holdings = [] } = useQuery<HoldRow>("SELECT symbol, exchange, quantity, currency, avg_cost FROM holdings WHERE deleted_at IS NULL");

  const [growth, setGrowth] = useState(7); // % annual price growth assumption
  const [monthly, setMonthly] = useState(0); // monthly contribution, major units
  const [years, setYears] = useState(15);
  const [reinvest, setReinvest] = useState(true);

  // Current market value in base currency (fallback to cost when no quote).
  const currentValue = useMemo(() => holdings.reduce((s, h) => {
    const q = market.quote(h.symbol, h.exchange);
    const perShare = q ? q.price : (h.avg_cost ?? 0);
    const ccy = q ? q.currency : h.currency;
    const rate = ccy === base ? 1 : getRate(ccy as CurrencyCode, base as CurrencyCode);
    return s + perShare * h.quantity * rate;
  }, 0), [holdings, market, getRate, base]);

  // Estimated annual dividend income → an effective yield for reinvestment.
  const annualDividend = useMemo(() => {
    const ev = computeDividendEvents(holdings, market.allDividends, getRate, base as CurrencyCode);
    const s = dividendSummary(ev);
    return s.trailing12 > 0 ? s.trailing12 : s.upcoming12;
  }, [holdings, market.allDividends, getRate, base]);
  const yieldRate = currentValue > 0 ? annualDividend / currentValue : 0;

  const { series, endValue, contributed } = useMemo(() => {
    const mGrowth = Math.pow(1 + growth / 100, 1 / 12) - 1;
    const mContribMinor = fromMajor(monthly, base as CurrencyCode).amount;
    let value = currentValue;
    let paidIn = currentValue;
    const pts: { year: string; value: number; contrib: number }[] = [{ year: "Now", value: Math.round(value), contrib: Math.round(paidIn) }];
    for (let m = 1; m <= years * 12; m++) {
      value = value * (1 + mGrowth) + mContribMinor;
      if (reinvest) value += (value * yieldRate) / 12;
      paidIn += mContribMinor;
      if (m % 12 === 0) pts.push({ year: `${m / 12}y`, value: Math.round(value), contrib: Math.round(paidIn) });
    }
    return { series: pts, endValue: value, contributed: paidIn };
  }, [currentValue, growth, monthly, years, reinvest, yieldRate, base]);

  if (holdings.length === 0) return null;

  const money0 = (v: number) => fmt(money(Math.round(v), base), "en-US");
  const growthPortion = endValue - contributed;

  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 14 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 12, flexWrap: "wrap" }}>
        <h2 style={{ margin: 0 }}>Projected wealth</h2>
        <span className="muted" style={{ fontSize: 12 }}>in {years} years</span>
      </div>

      <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
        <Stat label="Projected value" value={money0(endValue)} accent />
        <Stat label="You put in" value={money0(contributed)} />
        <Stat label="Growth + dividends" value={money0(growthPortion)} positive />
      </div>

      <div style={{ height: 220, marginLeft: -8 }}>
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={series} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
            <defs>
              <linearGradient id="gProj" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#5f7a52" stopOpacity={0.55} /><stop offset="100%" stopColor="#5f7a52" stopOpacity={0.03} /></linearGradient>
              <linearGradient id="gContrib" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#8a8580" stopOpacity={0.35} /><stop offset="100%" stopColor="#8a8580" stopOpacity={0.02} /></linearGradient>
            </defs>
            <XAxis dataKey="year" axisLine={false} tickLine={false} tick={{ fontSize: 11, fill: "var(--text-2)" }} interval="preserveStartEnd" />
            <YAxis hide />
            <Tooltip
              cursor={{ stroke: "var(--border)" }}
              contentStyle={{ background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, fontSize: 12 }}
              formatter={(v: number, n) => [money0(v), n === "value" ? "Projected" : "Contributed"]}
            />
            <Area type="monotone" dataKey="contrib" stroke="#8a8580" strokeWidth={1} fill="url(#gContrib)" />
            <Area type="monotone" dataKey="value" stroke="#5f7a52" strokeWidth={2} fill="url(#gProj)" />
          </AreaChart>
        </ResponsiveContainer>
      </div>

      <div style={{ display: "grid", gap: 12 }}>
        <Slider label="Assumed annual growth" value={growth} min={0} max={15} step={0.5} suffix="%" onChange={setGrowth} />
        <Slider label={`Monthly contribution (${base})`} value={monthly} min={0} max={5000} step={50} onChange={setMonthly} />
        <Slider label="Horizon" value={years} min={1} max={40} step={1} suffix="y" onChange={setYears} />
        <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 13 }}>
          <input type="checkbox" checked={reinvest} onChange={(e) => setReinvest(e.target.checked)} />
          Reinvest dividends {yieldRate > 0 ? `(~${(yieldRate * 100).toFixed(1)}% yield)` : ""}
        </label>
      </div>

      <p className="muted" style={{ fontSize: 11, margin: 0 }}>
        A projection using your assumptions, not a forecast or advice. Growth is hypothetical; actual returns vary and can be negative.
      </p>
    </section>
  );
}

function Stat({ label, value, accent, positive }: { label: string; value: string; accent?: boolean; positive?: boolean }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 12 }}>{label}</div>
      <div style={{ fontSize: 20, fontFamily: "var(--font-serif)", fontWeight: 750, color: accent ? "var(--accent)" : positive ? "var(--positive)" : "var(--text)" }}>{value}</div>
    </div>
  );
}

function Slider({ label, value, min, max, step, suffix, onChange }: { label: string; value: number; min: number; max: number; step: number; suffix?: string; onChange: (v: number) => void }) {
  return (
    <label style={{ display: "grid", gap: 4 }}>
      <span className="muted" style={{ fontSize: 12, display: "flex", justifyContent: "space-between" }}>
        <span>{label}</span><strong style={{ color: "var(--text)" }}>{value}{suffix ?? ""}</strong>
      </span>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
    </label>
  );
}
