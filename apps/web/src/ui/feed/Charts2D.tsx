"use client";

// Polished 2D visuals (recharts). Clean, brand-consistent, minimal chrome —
// these are the primary visuals for the insight feed.

import { useId } from "react";
import {
  ResponsiveContainer, BarChart, Bar, Cell, AreaChart, Area, XAxis, YAxis, LabelList,
  PieChart, Pie, RadialBarChart, RadialBar, PolarAngleAxis,
} from "recharts";
import type { VisualSpec } from "../../insights/types";
import { INSIGHT_PALETTE } from "../../insights/types";

function Center({ label, sub }: { label?: string | undefined; sub?: string | undefined }) {
  if (!label && !sub) return null;
  return (
    <div style={{ position: "absolute", inset: 0, display: "grid", placeItems: "center", pointerEvents: "none" }}>
      <div style={{ textAlign: "center" }}>
        {label && <div style={{ fontSize: "clamp(20px, 3.2vw, 30px)", fontWeight: 750, lineHeight: 1 }}>{label}</div>}
        {sub && <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>{sub}</div>}
      </div>
    </div>
  );
}

export function Visual2D({ visual, accent }: { visual: VisualSpec; accent: string }) {
  const gid = useId().replace(/[:]/g, "");

  switch (visual.kind) {
    case "bars": {
      if (visual.horizontal) {
        return (
          <ResponsiveContainer width="100%" height="100%">
            <BarChart layout="vertical" data={visual.series} margin={{ top: 6, right: 44, bottom: 6, left: 6 }}>
              <defs>
                <linearGradient id={`h${gid}`} x1="0" y1="0" x2="1" y2="0">
                  <stop offset="0%" stopColor={accent} stopOpacity={0.6} />
                  <stop offset="100%" stopColor={accent} stopOpacity={1} />
                </linearGradient>
              </defs>
              <XAxis type="number" hide />
              <YAxis type="category" dataKey="label" width={100} tick={{ fontSize: 12, fill: "var(--text)" }} axisLine={false} tickLine={false} />
              <Bar dataKey="value" radius={[0, 8, 8, 0]} fill={`url(#h${gid})`} barSize={18}>
                <LabelList dataKey="value" position="right" formatter={(v: number) => v.toLocaleString()} style={{ fontSize: 11, fill: "var(--text-2)" }} />
              </Bar>
            </BarChart>
          </ResponsiveContainer>
        );
      }
      return (
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={visual.series} margin={{ top: 18, right: 10, bottom: 2, left: 10 }}>
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--text-2)" }} axisLine={false} tickLine={false} interval={0} />
            <Bar dataKey="value" radius={[8, 8, 0, 0]} maxBarSize={46}>
              <LabelList dataKey="value" position="top" formatter={(v: number) => (v ? v.toLocaleString() : "")} style={{ fontSize: 10, fill: "var(--text-2)" }} />
              {visual.series.map((s, i) => <Cell key={i} fill={s.color ?? INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} />)}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      );
    }
    case "area":
      return (
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={visual.series} margin={{ top: 16, right: 14, bottom: 2, left: 14 }}>
            <defs>
              <linearGradient id={`a${gid}`} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={accent} stopOpacity={0.5} />
                <stop offset="100%" stopColor={accent} stopOpacity={0.03} />
              </linearGradient>
            </defs>
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--text-2)" }} axisLine={false} tickLine={false} interval="preserveStartEnd" />
            <Area type="monotone" dataKey="value" stroke={accent} strokeWidth={3} fill={`url(#a${gid})`}
              dot={{ r: 0 }} activeDot={{ r: 5, fill: accent, stroke: "var(--surface)", strokeWidth: 2 }} />
          </AreaChart>
        </ResponsiveContainer>
      );
    case "donut":
      return (
        <div style={{ position: "relative", width: "100%", height: "100%" }}>
          <ResponsiveContainer width="100%" height="100%">
            <PieChart>
              <Pie data={visual.series} dataKey="value" nameKey="label" innerRadius="62%" outerRadius="92%"
                paddingAngle={visual.series.length > 1 ? 3 : 0} cornerRadius={6} stroke="none" startAngle={90} endAngle={-270}>
                {visual.series.map((s, i) => <Cell key={i} fill={s.color ?? INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]!} />)}
              </Pie>
            </PieChart>
          </ResponsiveContainer>
          <Center label={visual.centerLabel} sub={visual.centerSub} />
        </div>
      );
    case "gauge": {
      const ratio = visual.max > 0 ? Math.min(1, visual.value / visual.max) : 0;
      const color = visual.value >= (visual.dangerAt ?? visual.max) ? "var(--negative)"
        : visual.value >= (visual.warnAt ?? visual.max * 0.8) ? "var(--warning)" : accent;
      return (
        <div style={{ position: "relative", width: "100%", height: "100%" }}>
          <ResponsiveContainer width="100%" height="100%">
            <RadialBarChart innerRadius="68%" outerRadius="100%" data={[{ value: ratio * 100 }]} startAngle={210} endAngle={-30}>
              <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
              <RadialBar dataKey="value" cornerRadius={14} fill={color} background={{ fill: "var(--border)" }} />
            </RadialBarChart>
          </ResponsiveContainer>
          <Center label={visual.centerLabel ?? `${Math.round(ratio * 100)}%`} />
        </div>
      );
    }
    case "progress": {
      const ratio = visual.target && visual.target > 0 ? Math.min(1, visual.value / visual.target) : 0.5;
      return (
        <div style={{ position: "relative", width: "100%", height: "100%" }}>
          <ResponsiveContainer width="100%" height="100%">
            <RadialBarChart innerRadius="72%" outerRadius="100%" data={[{ value: ratio * 100 }]} startAngle={90} endAngle={-270}>
              <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
              <RadialBar dataKey="value" cornerRadius={16} fill={accent} background={{ fill: "var(--border)" }} />
            </RadialBarChart>
          </ResponsiveContainer>
          <Center label={visual.centerLabel ?? `${Math.round(ratio * 100)}%`} />
        </div>
      );
    }
    default:
      return null;
  }
}
