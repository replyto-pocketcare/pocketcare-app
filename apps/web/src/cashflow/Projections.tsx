"use client";

/**
 * Planned Cashflow (BETA) — AI projection engine panel.
 * Deterministic, offline, inflation-aware. Feeds the finance `projectCashflow`
 * engine from the current monthly totals and renders 1/2/3-year structure cards
 * plus growth + net-surplus charts. Return/inflation/growth are tunable sliders,
 * seeded from the user's blended expected return.
 */
import { useMemo, useState } from "react";
import { money, toMajor, fromMajor, format } from "@pocketcare/money";
import { projectCashflow } from "@pocketcare/finance";
import { GrowthArea, NetBars, type GrowthPoint, type NetPoint } from "./Charts";

function Slider({ label, value, set, min, max, step, suffix }: { label: string; value: number; set: (n: number) => void; min: number; max: number; step: number; suffix: string }) {
  return (
    <label style={{ display: "grid", gap: 6 }}>
      <span style={{ display: "flex", justifyContent: "space-between", fontSize: 12.5, color: "var(--text-2)" }}>
        {label}<strong style={{ color: "var(--text)" }}>{value}{suffix}</strong>
      </span>
      <input className="pc-range" type="range" min={min} max={max} step={step} value={value} onChange={(e) => set(Number(e.target.value))} />
    </label>
  );
}

export function ProjectionPanel({ monthlyIncome, monthlyPayments, monthlySavings, seedReturnPct, currency }: {
  monthlyIncome: number;
  monthlyPayments: number;
  monthlySavings: number;
  seedReturnPct: number;
  currency: string;
}) {
  const [ret, setRet] = useState(Math.round(seedReturnPct * 100) / 100 || 10);
  const [inflation, setInflation] = useState(6);
  const [growth, setGrowth] = useState(5);
  const [startMajor, setStartMajor] = useState("0");

  const fmt = (major: number) => format(money(fromMajor(major, currency).amount, currency), "en-US");
  const toMaj = (minor: number) => toMajor(money(minor, currency));

  const rows = useMemo(() => projectCashflow({
    monthlyIncome,
    monthlyPayments,
    monthlySavings,
    currentSavings: fromMajor(Number(startMajor) || 0, currency).amount,
    annualReturnPct: ret,
    annualInflationPct: inflation,
    incomeGrowthPct: growth,
  }, 3), [monthlyIncome, monthlyPayments, monthlySavings, startMajor, ret, inflation, growth, currency]);

  const growthData: GrowthPoint[] = [
    { year: 0, nominal: toMaj(fromMajor(Number(startMajor) || 0, currency).amount), real: toMaj(fromMajor(Number(startMajor) || 0, currency).amount), contributed: 0 },
    ...rows.map((r) => ({ year: r.year, nominal: toMaj(r.savingsBalance), real: toMaj(r.realSavingsBalance), contributed: toMaj(r.savingsContributed) })),
  ];
  const netData: NetPoint[] = rows.map((r) => ({ year: r.year, surplus: toMaj(r.netCashflow) }));

  const hasData = monthlyIncome > 0 || monthlySavings > 0;

  return (
    <div style={{ display: "grid", gap: 18 }}>
      <div style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fit, minmax(150px, 1fr))" }}>
        <Slider label="Expected return" value={ret} set={setRet} min={0} max={25} step={0.5} suffix="%" />
        <Slider label="Inflation" value={inflation} set={setInflation} min={0} max={15} step={0.5} suffix="%" />
        <Slider label="Income growth" value={growth} set={setGrowth} min={0} max={20} step={0.5} suffix="%" />
        <label style={{ display: "grid", gap: 6 }}>
          <span style={{ fontSize: 12.5, color: "var(--text-2)" }}>Starting savings ({currency})</span>
          <input className="input" inputMode="decimal" value={startMajor} onChange={(e) => setStartMajor(e.target.value.replace(/[^0-9.]/g, ""))} />
        </label>
      </div>

      {/* 1 / 2 / 3-year structure cards */}
      <div style={{ display: "grid", gap: 12, gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))" }}>
        {rows.map((r) => (
          <div key={r.year} className="card lift" style={{ padding: 16, display: "grid", gap: 8, background: "var(--surface-2)" }}>
            <span className="eyebrow">{r.year} year{r.year > 1 ? "s" : ""}</span>
            <div>
              <div style={{ fontSize: 22, fontWeight: 750, letterSpacing: "-0.01em" }}>{fmt(toMaj(r.savingsBalance))}</div>
              <div className="muted" style={{ fontSize: 11.5 }}>projected savings</div>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, paddingTop: 6, borderTop: "1px solid var(--border)" }}>
              <span className="muted">Today's money</span>
              <strong style={{ color: "var(--teal)" }}>{fmt(toMaj(r.realSavingsBalance))}</strong>
            </div>
            <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12 }}>
              <span className="muted">Free surplus / yr</span>
              <strong style={{ color: r.netCashflow >= 0 ? "var(--positive)" : "var(--negative)" }}>{fmt(toMaj(r.netCashflow))}</strong>
            </div>
          </div>
        ))}
      </div>

      {hasData ? (
        <div style={{ display: "grid", gap: 18, gridTemplateColumns: "repeat(auto-fit, minmax(280px, 1fr))" }}>
          <div className="card" style={{ padding: 16 }}>
            <div className="eyebrow" style={{ marginBottom: 8 }}>Savings growth · nominal vs real</div>
            <GrowthArea data={growthData} fmt={fmt} />
          </div>
          <div className="card" style={{ padding: 16 }}>
            <div className="eyebrow" style={{ marginBottom: 8 }}>Projected free surplus</div>
            <NetBars data={netData} fmt={fmt} />
          </div>
        </div>
      ) : (
        <div className="card" style={{ padding: 24, textAlign: "center", color: "var(--text-3)", fontSize: 13 }}>
          Add recurring income and savings to unlock your projected 3-year structure.
        </div>
      )}
    </div>
  );
}
