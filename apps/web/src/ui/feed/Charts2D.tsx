"use client";

// Recharts 2D fallbacks — used when 3D is disabled (reduced motion / no WebGL)
// or while the 3D chunk is loading. Same VisualSpec drives both.

import {
  ResponsiveContainer, BarChart, Bar, Cell, AreaChart, Area, XAxis, YAxis,
  PieChart, Pie, RadialBarChart, RadialBar, PolarAngleAxis,
} from "recharts";
import type { VisualSpec, SeriesPoint } from "../../insights/types";
import { INSIGHT_PALETTE } from "../../insights/types";

export function Visual2D({ visual, accent }: { visual: VisualSpec; accent: string }) {
  switch (visual.kind) {
    case "bars3d":
      return (
        <ResponsiveContainer width="100%" height="100%">
          <BarChart data={visual.series} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--text-2)" }} axisLine={false} tickLine={false} />
            <Bar dataKey="value" radius={[6, 6, 0, 0]}>
              {visual.series.map((_, i) => <Cell key={i} fill={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]} />)}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      );
    case "ribbon3d":
      return (
        <ResponsiveContainer width="100%" height="100%">
          <AreaChart data={visual.series} margin={{ top: 8, right: 8, bottom: 0, left: 8 }}>
            <defs>
              <linearGradient id="rib" x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor={accent} stopOpacity={0.55} />
                <stop offset="100%" stopColor={accent} stopOpacity={0.05} />
              </linearGradient>
            </defs>
            <XAxis dataKey="label" tick={{ fontSize: 11, fill: "var(--text-2)" }} axisLine={false} tickLine={false} />
            <Area type="monotone" dataKey="value" stroke={accent} strokeWidth={2.5} fill="url(#rib)" />
          </AreaChart>
        </ResponsiveContainer>
      );
    case "donut3d":
      return (
        <ResponsiveContainer width="100%" height="100%">
          <PieChart>
            <Pie data={visual.series} dataKey="value" nameKey="label" innerRadius="55%" outerRadius="85%" paddingAngle={2} stroke="none">
              {visual.series.map((_, i) => <Cell key={i} fill={INSIGHT_PALETTE[i % INSIGHT_PALETTE.length]} />)}
            </Pie>
          </PieChart>
        </ResponsiveContainer>
      );
    case "gauge3d": {
      const ratio = visual.max > 0 ? Math.min(1, visual.value / visual.max) : 0;
      const color = ratio >= 1 ? "var(--negative)" : accent;
      return (
        <ResponsiveContainer width="100%" height="100%">
          <RadialBarChart innerRadius="70%" outerRadius="100%" data={[{ value: ratio * 100 }]} startAngle={220} endAngle={-40}>
            <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
            <RadialBar dataKey="value" cornerRadius={12} fill={color} background={{ fill: "var(--border)" }} />
          </RadialBarChart>
        </ResponsiveContainer>
      );
    }
    case "orb3d": {
      const ratio = visual.target && visual.target > 0 ? Math.min(1, visual.value / visual.target) : 0.5;
      return (
        <ResponsiveContainer width="100%" height="100%">
          <RadialBarChart innerRadius="72%" outerRadius="100%" data={[{ value: ratio * 100 }]} startAngle={90} endAngle={-270}>
            <PolarAngleAxis type="number" domain={[0, 100]} tick={false} />
            <RadialBar dataKey="value" cornerRadius={16} fill={accent} background={{ fill: "var(--border)" }} />
          </RadialBarChart>
        </ResponsiveContainer>
      );
    }
    default:
      return null;
  }
}

export type { SeriesPoint };
