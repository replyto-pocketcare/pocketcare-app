"use client";

import type { ReactNode } from "react";

/** Shared card language for the Loans list + EMI schedule (status pills,
 *  labelled footer fields, paid/due status icons) — statement-style like a bank app. */

export type PillTone = "positive" | "negative" | "amber" | "muted";
const PILL: Record<PillTone, { bg: string; fg: string }> = {
  positive: { bg: "color-mix(in srgb, var(--positive) 15%, transparent)", fg: "var(--positive)" },
  negative: { bg: "color-mix(in srgb, var(--negative) 15%, transparent)", fg: "var(--negative)" },
  amber: { bg: "color-mix(in srgb, #c9922a 18%, transparent)", fg: "#b07d1f" },
  muted: { bg: "var(--surface-2)", fg: "var(--text-2)" },
};

/** A small status pill (Active / Paid / Due / Closed). Optionally tappable. */
export function Pill({ tone, children, onClick, title }: { tone: PillTone; children: ReactNode; onClick?: () => void; title?: string }) {
  const c = PILL[tone];
  const style = { background: c.bg, color: c.fg, fontSize: 11, fontWeight: 650, padding: "3px 9px", borderRadius: 999, whiteSpace: "nowrap", flexShrink: 0, border: "none", lineHeight: 1.5 } as const;
  return onClick
    ? <button className="press" title={title} onClick={onClick} style={{ ...style, cursor: "pointer" }}>{children}</button>
    : <span title={title} style={style}>{children}</span>;
}

/** A labelled value (label above, value below) for card footers. */
export function Field({ label, value, align = "left", tone }: { label: string; value: string; align?: "left" | "right"; tone?: string }) {
  return (
    <div style={{ display: "grid", gap: 2, textAlign: align, minWidth: 0 }}>
      <span className="muted" style={{ fontSize: 11 }}>{label}</span>
      <span style={{ fontSize: 14, fontWeight: 600, color: tone, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{value}</span>
    </div>
  );
}

/** Round status icon: green ✓ (paid), amber ! (due/next), or a muted number. */
export function EmiIcon({ state, n }: { state: "paid" | "due" | "idle"; n?: number }) {
  const map = {
    paid: { bg: "var(--positive)", fg: "#fff", ch: "✓" },
    due: { bg: "#c9922a", fg: "#fff", ch: "!" },
    idle: { bg: "var(--surface-2)", fg: "var(--text-2)", ch: n != null ? String(n) : "•" },
  } as const;
  const s = map[state];
  return (
    <span aria-hidden style={{ width: 24, height: 24, flexShrink: 0, borderRadius: 999, background: s.bg, color: s.fg, display: "grid", placeItems: "center", fontSize: 13, fontWeight: 700 }}>{s.ch}</span>
  );
}

/** "Mar '26 – Nov '26" from a start date + tenure in months. */
export function loanRange(start: string | null, tenure: number): string | null {
  if (!start || !tenure) return null;
  const d = new Date(start + "T00:00:00");
  if (Number.isNaN(d.getTime())) return null;
  const end = new Date(d); end.setMonth(end.getMonth() + tenure);
  const f = (x: Date) => x.toLocaleDateString(undefined, { month: "short", year: "2-digit" });
  return `${f(d)} – ${f(end)}`;
}
