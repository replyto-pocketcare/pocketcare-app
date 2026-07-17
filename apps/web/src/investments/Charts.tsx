"use client";

/**
 * Investments insight visualizations. Presentational only — series arrive
 * pre-computed in MAJOR units; `fmt` renders currency. Colors are CSS tokens so
 * light/dark themes track the rest of the app. Gradient fills match the
 * dashboard style.
 */
import { useId } from "react";
import {
  ResponsiveContainer, PieChart, Pie, Cell, Tooltip,
  BarChart, Bar, XAxis, YAxis, CartesianGrid, ReferenceLine,
} from "recharts";

const AXIS = { fontSize: 11, fill: "var(--text-2)" } as const;
const GRID = "var(--border)";

/** A rotating palette of theme tokens for allocation slices. */
export const SLICE_COLORS = ["var(--accent)", "var(--teal)", "var(--positive)", "var(--gold, #c9a24a)", "var(--negative)", "var(--text-3)"];

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

export interface Slice { name: string; value: number; color?: string }

/** Allocation donut with a centered total label. */
export function AllocationDonut({ data, centerLabel, centerValue, fmt }: {
  data: Slice[]; centerLabel: string; centerValue: string; fmt: (n: number) => string;
}) {
  const slices = data.filter((d) => d.value > 0).map((d, i) => ({ ...d, color: d.color ?? SLICE_COLORS[i % SLICE_COLORS.length] }));
  const total = slices.reduce((a, d) => a + d.value, 0);
  if (total <= 0) return <Empty label="Add investments to see your allocation" />;
  return (
    <div style={{ position: "relative" }}>
      <ResponsiveContainer width="100%" height={240}>
        <PieChart>
          <Pie data={slices} dataKey="value" nameKey="name" innerRadius={66} outerRadius={100} paddingAngle={2} stroke="var(--surface)" strokeWidth={2}>
            {slices.map((d, i) => <Cell key={i} fill={d.color} />)}
          </Pie>
          <Tooltip content={({ active, payload }) => active && payload?.length
            ? <TipCard rows={[{ label: String(payload[0]!.name), value: `${fmt(Number(payload[0]!.value))} · ${Math.round((Number(payload[0]!.value) / total) * 100)}%`, color: (payload[0]!.payload as { color: string }).color }]} />
            : null} />
        </PieChart>
      </ResponsiveContainer>
      <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", pointerEvents: "none" }}>
        <div style={{ textAlign: "center" }}>
          <div className="muted" style={{ fontSize: 11 }}>{centerLabel}</div>
          <div style={{ fontSize: 20, fontWeight: 760, letterSpacing: "-0.01em" }}>{centerValue}</div>
        </div>
      </div>
    </div>
  );
}

export interface GainPoint { name: string; gain: number }

/** Gain / loss per group — gradient bars, zero reference line. */
export function GainBars({ data, fmt }: { data: GainPoint[]; fmt: (n: number) => string }) {
  const gid = useId().replace(/[:]/g, "");
  if (data.length === 0) return <Empty label="No gains to show yet" />;
  return (
    <ResponsiveContainer width="100%" height={240}>
      <BarChart data={data} margin={{ top: 8, right: 8, bottom: 0, left: -8 }}>
        <defs>
          <linearGradient id={`gPos-${gid}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--positive)" stopOpacity={0.95} />
            <stop offset="100%" stopColor="var(--positive)" stopOpacity={0.45} />
          </linearGradient>
          <linearGradient id={`gNeg-${gid}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor="var(--negative)" stopOpacity={0.45} />
            <stop offset="100%" stopColor="var(--negative)" stopOpacity={0.95} />
          </linearGradient>
        </defs>
        <CartesianGrid vertical={false} stroke={GRID} />
        <XAxis dataKey="name" tick={AXIS} axisLine={false} tickLine={false} interval={0} height={40} angle={-18} textAnchor="end" />
        <YAxis tick={AXIS} axisLine={false} tickLine={false} tickFormatter={compact} width={44} />
        <ReferenceLine y={0} stroke="var(--border-strong)" />
        <Tooltip cursor={{ fill: "var(--surface-2)" }} content={({ active, payload }) => active && payload?.length
          ? <TipCard rows={[{ label: String(payload[0]!.payload.name), value: fmt(Number(payload[0]!.value)) }]} />
          : null} />
        <Bar dataKey="gain" radius={[6, 6, 0, 0]} maxBarSize={54}>
          {data.map((d, i) => <Cell key={i} fill={d.gain >= 0 ? `url(#gPos-${gid})` : `url(#gNeg-${gid})`} />)}
        </Bar>
      </BarChart>
    </ResponsiveContainer>
  );
}

function Empty({ label }: { label: string }) {
  return <div style={{ height: 240, display: "grid", placeItems: "center", color: "var(--text-3)", fontSize: 13 }}>{label}</div>;
}
