"use client";

/**
 * Planned Cashflow (BETA) visualizations. Presentational only — every series is
 * passed in already computed. Colors are CSS tokens so light/dark themes track
 * the rest of the app. Amounts arrive in MAJOR units; `fmt` renders currency.
 */
import {
  ResponsiveContainer,
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  PieChart,
  Pie,
  Cell,
  ReferenceLine,
} from "recharts";

const AXIS = { fontSize: 11, fill: "var(--text-2)" } as const;
const GRID = "var(--border)";

function compact(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1e7) return `${(n / 1e7).toFixed(1)}Cr`;
  if (abs >= 1e5) return `${(n / 1e5).toFixed(1)}L`;
  if (abs >= 1e3) return `${(n / 1e3).toFixed(0)}k`;
  return `${Math.round(n)}`;
}

function TipCard({ rows }: { rows: { label: string; value: string; color?: string }[] }) {
  return (
    <div style={{ background: "var(--surface)", border: "1px solid var(--border-strong)", borderRadius: 12, padding: "8px 12px", boxShadow: "var(--shadow)", fontSize: 12 }}>
      {rows.map((r, i) => (
        <div key={i} style={{ display: "flex", gap: 12, justifyContent: "space-between", alignItems: "center" }}>
          <span style={{ display: "inline-flex", alignItems: "center", gap: 6, color: "var(--text-2)" }}>
            {r.color && <span style={{ width: 8, height: 8, borderRadius: 999, background: r.color }} />}{r.label}
          </span>
          <strong style={{ color: "var(--text)" }}>{r.value}</strong>
        </div>
      ))}
    </div>
  );
}

/** Where each rupee of income goes: payments, savings, free surplus. */
export function SplitDonut({ payments, savings, surplus, fmt }: { payments: number; savings: number; surplus: number; fmt: (n: number) => string }) {
  const data = [
    { name: "Payments", value: Math.max(payments, 0), color: "var(--negative)" },
    { name: "Savings", value: Math.max(savings, 0), color: "var(--teal)" },
    { name: "Free surplus", value: Math.max(surplus, 0), color: "var(--positive)" },
  ].filter((d) => d.value > 0);
  const total = data.reduce((a, d) => a + d.value, 0);
  if (total <= 0) return <Empty label="Add income & payments to see the split" />;
  return (
    <ResponsiveContainer width="100%" height={220}>
      <PieChart>
        <Pie data={data} dataKey="value" nameKey="name" innerRadius={58} outerRadius={90} paddingAngle={2} stroke="var(--surface)" strokeWidth={2}>
          {data.map((d, i) => <Cell key={i} fill={d.color} />)}
        </Pie>
        <Tooltip content={({ active, payload }) => active && payload?.length
          ? <TipCard rows={[{ label: String(payload[0]!.name), value: fmt(Number(payload[0]!.value)), color: (payload[0]!.payload as { color: string }).color }]} />
          : null} />
      </PieChart>
    </ResponsiveContainer>
  );
}

/** Monthly income vs payments vs savings — quick magnitude comparison. */
export function RatioBars({ income, payments, savings, fmt }: { income: number; payments: number; savings: number; fmt: (n: number) => string }) {
  const data = [
    { name: "Income", value: income, color: "var(--positive)" },
    { name: "Payments", value: payments, color: "var(--negative)" },
    { name: "Savings", value: savings, color: "var(--teal)" },
  ];
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -14 }}>
        <CartesianGrid vertical={false} stroke={GRID} />
        <XAxis dataKey="name" tick={AXIS} axisLine={false} tickLine={false} />
        <YAxis tick={AXIS} axisLine={false} tickLine={false} tickFormatter={compact} width={44} />
        <Tooltip cursor={{ fill: "var(--surface-2)" }} content={({ active, payload }) => active && payload?.length
          ? <TipCard rows={[{ label: String(payload[0]!.payload.name), value: fmt(Number(payload[0]!.value)), color: payload[0]!.payload.color }]} />
          : null} />
        <Bar dataKey="value" radius={[8, 8, 0, 0]} maxBarSize={64}>
          {data.map((d, i) => <Cell key={i} fill={d.color} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

export interface GrowthPoint { year: number; nominal: number; real: number; contributed: number }

/** AI-projected savings growth: nominal vs inflation-adjusted (real). */
export function GrowthArea({ data, fmt }: { data: GrowthPoint[]; fmt: (n: number) => string }) {
  return (
    <ResponsiveContainer width="100%" height={260}>
      <AreaChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -14 }}>
        <defs>
          <linearGradient id="gNominal" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.35} />
            <stop offset="100%" stopColor="var(--accent)" stopOpacity={0.02} />
          </linearGradient>
          <linearGradient id="gReal" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--teal)" stopOpacity={0.28} />
            <stop offset="100%" stopColor="var(--teal)" stopOpacity={0.02} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} stroke={GRID} />
        <XAxis dataKey="year" tick={AXIS} axisLine={false} tickLine={false} tickFormatter={(y) => (y === 0 ? "Now" : `Yr ${y}`)} />
        <YAxis tick={AXIS} axisLine={false} tickLine={false} tickFormatter={compact} width={44} />
        <Tooltip content={({ active, payload, label }) => active && payload?.length
          ? <TipCard rows={[
              { label: label === 0 ? "Today" : `Year ${label}`, value: "" },
              { label: "Projected", value: fmt(Number(payload.find((p) => p.dataKey === "nominal")?.value ?? 0)), color: "var(--accent)" },
              { label: "In today's money", value: fmt(Number(payload.find((p) => p.dataKey === "real")?.value ?? 0)), color: "var(--teal)" },
            ]} />
          : null} />
        <Area type="monotone" dataKey="nominal" stroke="var(--accent)" strokeWidth={2.5} fill="url(#gNominal)" />
        <Area type="monotone" dataKey="real" stroke="var(--teal)" strokeWidth={2} fill="url(#gReal)" strokeDasharray="5 4" />
      </AreaChart>
    </ResponsiveContainer>
  );
}

export interface NetPoint { year: number; surplus: number }

/** Projected free surplus (income − payments − savings) per year. */
export function NetBars({ data, fmt }: { data: NetPoint[]; fmt: (n: number) => string }) {
  return (
    <ResponsiveContainer width="100%" height={220}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -14 }}>
        <CartesianGrid vertical={false} stroke={GRID} />
        <XAxis dataKey="year" tick={AXIS} axisLine={false} tickLine={false} tickFormatter={(y) => `Yr ${y}`} />
        <YAxis tick={AXIS} axisLine={false} tickLine={false} tickFormatter={compact} width={44} />
        <ReferenceLine y={0} stroke="var(--border-strong)" />
        <Tooltip cursor={{ fill: "var(--surface-2)" }} content={({ active, payload }) => active && payload?.length
          ? <TipCard rows={[{ label: `Year ${payload[0]!.payload.year}`, value: fmt(Number(payload[0]!.value)) }]} />
          : null} />
        <Bar dataKey="surplus" radius={[8, 8, 0, 0]} maxBarSize={54}>
          {data.map((d, i) => <Cell key={i} fill={d.surplus >= 0 ? "var(--positive)" : "var(--negative)"} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

function Empty({ label }: { label: string }) {
  return <div style={{ height: 220, display: "grid", placeItems: "center", color: "var(--text-3)", fontSize: 13 }}>{label}</div>;
}
