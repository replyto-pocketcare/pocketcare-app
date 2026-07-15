"use client";

// Structured assistant responses.
// The model may append ONE `<ui>{ …json… }</ui>` block to its text. We parse it
// into native visual cards (stats / progress / breakdown bars) and tappable
// action chips, so answers stay short and the numbers live in UI, not prose.
// Anything malformed degrades gracefully to plain text — the chat never breaks.

import Link from "next/link";
import { ProgressBar } from "../ui/ProgressBar";

// ---- Shapes the model is allowed to emit (validated defensively) ----
export interface UiStatCard {
  kind: "stat";
  label: string;
  value: string;
  sub?: string | undefined;
  tone?: "accent" | "positive" | "negative" | "neutral" | undefined;
}
export interface UiProgressCard { kind: "progress"; label: string; value?: string | undefined; pct: number }
export interface UiBreakdownItem { label: string; value?: string | undefined; pct?: number | undefined }
export interface UiBreakdownCard { kind: "breakdown"; label: string; items: UiBreakdownItem[] }
export type UiCard = UiStatCard | UiProgressCard | UiBreakdownCard;

/** A suggestion the user can act on: either sends a chat message or opens an app route. */
export interface UiAction { label: string; send?: string; href?: string }

export interface AssistantUi { cards: UiCard[]; actions: UiAction[] }

const UI_RE = /<ui>\s*([\s\S]*?)\s*<\/ui>/;
const MAX_CARDS = 4;
const MAX_ACTIONS = 4;

const isStr = (v: unknown): v is string => typeof v === "string" && v.length > 0;
const clampPct = (v: unknown): number => Math.min(100, Math.max(0, typeof v === "number" && Number.isFinite(v) ? v : 0));

function toCard(raw: unknown): UiCard | null {
  if (!raw || typeof raw !== "object") return null;
  const c = raw as Record<string, unknown>;
  if (c.kind === "stat" && isStr(c.label) && isStr(c.value)) {
    const tone = c.tone === "positive" || c.tone === "negative" || c.tone === "neutral" ? c.tone : "accent";
    return { kind: "stat", label: c.label, value: c.value, sub: isStr(c.sub) ? c.sub : undefined, tone };
  }
  if (c.kind === "progress" && isStr(c.label)) {
    return { kind: "progress", label: c.label, value: isStr(c.value) ? c.value : undefined, pct: clampPct(c.pct) };
  }
  if (c.kind === "breakdown" && isStr(c.label) && Array.isArray(c.items)) {
    const items = c.items
      .filter((i): i is Record<string, unknown> => !!i && typeof i === "object")
      .filter((i) => isStr(i.label))
      .slice(0, 6)
      .map((i) => ({ label: i.label as string, value: isStr(i.value) ? i.value : undefined, pct: i.pct == null ? undefined : clampPct(i.pct) }));
    return items.length ? { kind: "breakdown", label: c.label, items } : null;
  }
  return null;
}

function toAction(raw: unknown): UiAction | null {
  if (!raw || typeof raw !== "object") return null;
  const a = raw as Record<string, unknown>;
  if (!isStr(a.label)) return null;
  if (isStr(a.send)) return { label: a.label, send: a.send };
  if (isStr(a.href) && a.href.startsWith("/")) return { label: a.label, href: a.href }; // internal routes only
  return null;
}

/** Split a raw assistant message into concise text + an optional validated UI block. */
export function parseAssistantMessage(raw: string): { text: string; ui: AssistantUi | null } {
  const m = raw.match(UI_RE);
  if (!m) return { text: raw.trim(), ui: null };
  const text = raw.replace(UI_RE, "").trim();
  try {
    const parsed = JSON.parse(m[1]!) as Record<string, unknown>;
    const cards = (Array.isArray(parsed.cards) ? parsed.cards : []).map(toCard).filter((c): c is UiCard => !!c).slice(0, MAX_CARDS);
    const actions = (Array.isArray(parsed.actions) ? parsed.actions : []).map(toAction).filter((a): a is UiAction => !!a).slice(0, MAX_ACTIONS);
    return cards.length || actions.length ? { text, ui: { cards, actions } } : { text, ui: null };
  } catch {
    return { text, ui: null }; // invalid JSON → hide the block, keep the prose
  }
}

const TONE_COLOR: Record<NonNullable<UiStatCard["tone"]>, string> = {
  accent: "var(--accent)",
  positive: "var(--positive)",
  negative: "var(--negative)",
  neutral: "var(--text)",
};

function StatCards({ cards }: { cards: UiStatCard[] }) {
  return (
    <div style={{ display: "grid", gap: 10, gridTemplateColumns: "repeat(auto-fit, minmax(min(150px, 100%), 1fr))" }}>
      {cards.map((c, i) => (
        <div key={i} className="card" style={{ padding: "12px 14px", display: "grid", gap: 3, alignContent: "start" }}>
          <span className="eyebrow">{c.label}</span>
          <span style={{ fontSize: 20, fontWeight: 700, letterSpacing: "-0.02em", color: TONE_COLOR[c.tone ?? "accent"] }}>{c.value}</span>
          {c.sub && <span className="muted" style={{ fontSize: 12 }}>{c.sub}</span>}
        </div>
      ))}
    </div>
  );
}

function ProgressCard({ card }: { card: UiProgressCard }) {
  return (
    <div className="card" style={{ padding: "12px 14px", display: "grid", gap: 8 }}>
      <div style={{ display: "flex", justifyContent: "space-between", gap: 8, alignItems: "baseline" }}>
        <span style={{ fontSize: 13, fontWeight: 600 }}>{card.label}</span>
        {card.value && <span className="muted" style={{ fontSize: 12, whiteSpace: "nowrap" }}>{card.value}</span>}
      </div>
      <ProgressBar pct={card.pct} height={8} />
    </div>
  );
}

function BreakdownCard({ card }: { card: UiBreakdownCard }) {
  return (
    <div className="card" style={{ padding: "12px 14px", display: "grid", gap: 10 }}>
      <span className="eyebrow">{card.label}</span>
      {card.items.map((it, i) => (
        <div key={i} style={{ display: "grid", gap: 4 }}>
          <div style={{ display: "flex", justifyContent: "space-between", gap: 8, fontSize: 13 }}>
            <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{it.label}</span>
            {it.value && <span className="muted" style={{ whiteSpace: "nowrap" }}>{it.value}</span>}
          </div>
          {it.pct != null && (
            <div style={{ height: 6, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
              <div style={{ height: "100%", width: `${it.pct}%`, borderRadius: 999, background: "var(--accent-soft)", transition: "width 0.4s cubic-bezier(0.2,0,0,1)" }} />
            </div>
          )}
        </div>
      ))}
    </div>
  );
}

/** Visual cards + action chips rendered under an assistant bubble. */
export function AssistantUiBlock({ ui, onSend, disabled }: { ui: AssistantUi; onSend: (text: string) => void; disabled?: boolean }) {
  const stats = ui.cards.filter((c): c is UiStatCard => c.kind === "stat");
  const rest = ui.cards.filter((c) => c.kind !== "stat");
  return (
    <div className="fade-up" style={{ display: "grid", gap: 10 }}>
      {stats.length > 0 && <StatCards cards={stats} />}
      {rest.map((c, i) =>
        c.kind === "progress" ? <ProgressCard key={i} card={c} /> : <BreakdownCard key={i} card={c as UiBreakdownCard} />,
      )}
      {ui.actions.length > 0 && (
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          {ui.actions.map((a, i) =>
            a.href ? (
              <Link key={i} href={a.href} className="chip" style={{ whiteSpace: "normal" }}>
                {a.label} ›
              </Link>
            ) : (
              <button
                key={i}
                className="chip press"
                style={{ whiteSpace: "normal", textAlign: "left", borderColor: "var(--accent-soft)", color: "var(--accent)", fontWeight: 600 }}
                disabled={disabled}
                onClick={() => a.send && onSend(a.send)}
              >
                {a.label}
              </button>
            ),
          )}
        </div>
      )}
    </div>
  );
}
