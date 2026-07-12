"use client";

import Link from "next/link";
import type { InsightCard as Card, InsightType } from "../../insights/types";
import { THEME_TOKEN } from "../../insights/types";
import { Visual2D } from "./Charts2D";

const TYPE_LABEL: Record<InsightType, string> = {
  weekly_summary: "Weekly recap",
  budget_warning: "Budget alert",
  savings_achievement: "Achievement",
  spending_trend: "Spending trend",
  category_breakdown: "Breakdown",
  net_worth_update: "Net worth",
  streak: "Streak",
  biggest_expense: "Biggest expense",
  weekday_pattern: "Spending pattern",
  label_breakdown: "By label",
  subscriptions_load: "Subscriptions",
  month_pace: "Month pace",
  no_spend_days: "No-spend days",
  goal_progress: "Goal progress",
  category_spike: "Category spike",
  avg_daily_spend: "Daily average",
};

function VisualHost({ card }: { card: Card }) {
  const cssAccent = THEME_TOKEN[card.theme].accent;
  return (
    <div style={{ position: "absolute", inset: 0, padding: "8px 6px" }}>
      <Visual2D visual={card.visual} accent={cssAccent} />
    </div>
  );
}

function DeltaPill({ card }: { card: Card }) {
  const m = card.metric;
  if (!m || m.deltaPct === undefined) return null;
  const up = m.direction === "up";
  return (
    <span style={{ fontSize: 13, fontWeight: 600, color: up ? "var(--positive)" : "var(--negative)" }}>
      {up ? "▲" : "▼"} {Math.abs(m.deltaPct)}%
    </span>
  );
}

function TextBlock({ card }: { card: Card }) {
  const accent = THEME_TOKEN[card.theme].accent;
  return (
    <div style={{ display: "grid", gap: 12, alignContent: "center" }}>
      <span style={{ justifySelf: "start", fontSize: 11, fontWeight: 700, letterSpacing: "0.08em", textTransform: "uppercase",
        color: accent, background: "var(--surface-2)", padding: "4px 10px", borderRadius: 999 }}>
        {TYPE_LABEL[card.type]}
      </span>
      <h2 style={{ margin: 0, fontSize: "clamp(22px, 3.4vw, 34px)", lineHeight: 1.12, letterSpacing: "-0.02em" }}>{card.headline}</h2>
      {card.subhead && <div className="muted" style={{ fontSize: 14, marginTop: -4 }}>{card.subhead}</div>}
      {card.metric && (
        <div style={{ display: "flex", alignItems: "baseline", gap: 10 }}>
          <span style={{ fontSize: "clamp(26px, 4vw, 40px)", fontWeight: 750, color: accent }}>{card.metric.display}</span>
          <DeltaPill card={card} />
        </div>
      )}
      <ul style={{ margin: 0, paddingLeft: 0, display: "grid", gap: 7, listStyle: "none" }}>
        {card.bullets.map((b, i) => (
          <li key={i} style={{ display: "flex", gap: 9, fontSize: 14.5, alignItems: "flex-start" }}>
            <span style={{ color: accent, flexShrink: 0 }}>•</span>{b}
          </li>
        ))}
      </ul>
      {card.cta && (
        <Link href={card.cta.target} className="btn" style={{ justifySelf: "start", marginTop: 4 }}>{card.cta.label}</Link>
      )}
    </div>
  );
}

/**
 * One insight. `layout="mobile"` stacks the visual over the copy (full-viewport
 * card); `layout="desktop"` is a landscape tile with the visual on the left and
 * the copy on the right.
 */
export function InsightCard({ card, layout }: { card: Card; layout: "mobile" | "desktop" }) {
  const glow = THEME_TOKEN[card.theme].accent;
  if (layout === "desktop") {
    return (
      <div className="card" style={{ height: "100%", display: "grid", gridTemplateColumns: "1.05fr 1fr", overflow: "hidden",
        background: "var(--surface)", boxShadow: "var(--shadow-lg)" }}>
        <div style={{ position: "relative", background: `radial-gradient(120% 100% at 30% 20%, ${glow}18, transparent 70%)` }}>
          <div style={{ position: "absolute", inset: 22, borderRadius: 20, background: "var(--surface-2)", border: "1px solid var(--border)", boxShadow: "var(--shadow)" }} />
          <VisualHost card={card} />
        </div>
        <div style={{ padding: "36px 40px", display: "grid" }}>
          <TextBlock card={card} />
        </div>
      </div>
    );
  }
  // mobile — full viewport
  return (
    <div style={{ height: "100%", display: "grid", gridTemplateRows: "1fr auto", padding: "16px 20px 40px",
      background: `radial-gradient(90% 45% at 50% 15%, ${glow}14, transparent 70%)` }}>
      <div style={{ position: "relative", minHeight: 0 }}>
        <div style={{ position: "absolute", inset: "14px 8px", borderRadius: 20, background: "var(--surface-2)", border: "1px solid var(--border)", boxShadow: "var(--shadow)" }} />
        <VisualHost card={card} />
      </div>
      <div className="card" style={{ padding: 22, background: "var(--surface)", boxShadow: "var(--shadow)" }}>
        <TextBlock card={card} />
      </div>
    </div>
  );
}
