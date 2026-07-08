// The "Insight Payload" contract. Cards are generated client-side today (from
// PowerSync aggregates) but this schema is the portable contract, so a backend
// or edge function can emit the exact same shapes later.

export type InsightTheme = "positive" | "warning" | "neutral" | "celebratory";

export type InsightType =
  | "weekly_summary"
  | "budget_warning"
  | "savings_achievement"
  | "spending_trend"
  | "category_breakdown"
  | "net_worth_update"
  | "streak";

/** A single labelled datum shared by the chart visuals. */
export interface SeriesPoint {
  label: string;
  value: number; // major units (or count, for streaks)
  /** Optional explicit colour; otherwise the renderer assigns from the palette. */
  color?: string;
}

/**
 * VisualSpec is a discriminated union on `kind`. Each kind renders as a 3D
 * (react-three-fiber) chart with a recharts 2D fallback — the backend picks the
 * visual independently of the copy.
 */
export type VisualSpec =
  | { kind: "bars3d"; series: SeriesPoint[]; unit?: string }
  | { kind: "donut3d"; series: SeriesPoint[] }
  | { kind: "gauge3d"; value: number; max: number; warnAt?: number; dangerAt?: number; unit?: string }
  | { kind: "ribbon3d"; series: SeriesPoint[] }
  | { kind: "orb3d"; value: number; target?: number };

export type VisualKind = VisualSpec["kind"];

/** The hero number for a card. `display` is pre-formatted (currency-aware). */
export interface InsightMetric {
  display: string;
  raw?: number | undefined;
  deltaPct?: number | undefined;
  direction?: "up" | "down" | "flat" | undefined;
}

export interface InsightCard {
  /** Deterministic per period so "seen" state and dedupe are stable. */
  id: string;
  type: InsightType;
  theme: InsightTheme;
  generatedAt: string; // ISO
  period: { start: string; end: string };
  /** Higher = more important. Used to rank the day's stack. */
  priority: number;
  headline: string;
  subhead?: string;
  bullets: string[];
  metric?: InsightMetric;
  visual: VisualSpec;
  cta?: { label: string; target: string }; // in-app route
  cadence: { key: string; frequency: "daily" | "weekly" | "monthly" | "event" };
}

/** Theme → brand tokens (works in both light and dark themes via CSS vars). */
export const THEME_TOKEN: Record<InsightTheme, { accent: string; ghost: string }> = {
  positive: { accent: "var(--positive)", ghost: "var(--surface-2)" },
  warning: { accent: "var(--warning)", ghost: "var(--surface-2)" },
  celebratory: { accent: "var(--accent)", ghost: "var(--accent-ghost)" },
  neutral: { accent: "var(--forest)", ghost: "var(--surface-2)" },
};

/** Brand palette for multi-series visuals (matches the Insights page PIE). */
export const INSIGHT_PALETTE = [
  "#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647",
];
