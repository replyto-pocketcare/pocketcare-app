"use client";

// Structured assistant responses.
// The model may append ONE `<ui>{ …json… }</ui>` block to its text. We parse it
// into native visual cards (stats / progress / breakdown bars) and tappable
// action chips, so answers stay short and the numbers live in UI, not prose.
// Anything malformed degrades gracefully to plain text — the chat never breaks.

import { type ReactNode, useId } from "react";
import Link from "next/link";
import {
  ResponsiveContainer, AreaChart, Area, BarChart, Bar, Cell,
  XAxis, YAxis, Tooltip, CartesianGrid,
} from "recharts";
import { ProgressBar } from "../ui/ProgressBar";

const AXIS = { fontSize: 11, fill: "var(--text-2)" } as const;
function compactNum(n: number): string {
  const abs = Math.abs(n);
  if (abs >= 1e7) return `${(n / 1e7).toFixed(1)}Cr`;
  if (abs >= 1e5) return `${(n / 1e5).toFixed(1)}L`;
  if (abs >= 1e3) return `${(n / 1e3).toFixed(1)}k`;
  return `${Math.round(n)}`;
}
function ChartTip({ active, payload }: { active?: boolean; payload?: { value?: number; payload?: { x?: string } }[] }) {
  if (!active || !payload?.length) return null;
  const p = payload[0]!;
  return (
    <div style={{ background: "var(--surface)", border: "1px solid var(--border-strong)", borderRadius: 10, padding: "6px 10px", boxShadow: "var(--shadow)", fontSize: 12 }}>
      <span style={{ color: "var(--text-2)" }}>{p.payload?.x}</span> <strong>{compactNum(Number(p.value))}</strong>
    </div>
  );
}

// --- Lightweight, dependency-free markdown renderer (safe: no raw HTML) -------
// Handles the GitHub-flavoured subset the assistant uses: headings, tables,
// task lists / bullet / ordered lists, blockquotes, rules, fenced code, and
// inline **bold** *italic* `code` and [links](/route). Interactive widgets stay
// in the <ui> block; this covers rich *static* structure in the prose.

const CODE_STYLE = { background: "var(--surface-2)", padding: "0 4px", borderRadius: 4, fontSize: "0.92em" } as const;

/** Inline formatting → React nodes. Links limited to internal routes + http(s). */
function inline(s: string): ReactNode[] {
  const out: ReactNode[] = [];
  const re = /\[([^\]]+)\]\(([^)\s]+)\)|\*\*([^*]+)\*\*|__([^_]+)__|\*([^*\n]+)\*|`([^`]+)`/g;
  let last = 0, m: RegExpExecArray | null, k = 0;
  while ((m = re.exec(s)) !== null) {
    if (m.index > last) out.push(s.slice(last, m.index));
    if (m[1] != null) {
      const href = m[2]!;
      if (href.startsWith("/")) out.push(<Link key={k++} href={href} style={{ color: "var(--accent)", textDecoration: "underline" }}>{m[1]}</Link>);
      else if (/^https?:\/\//.test(href)) out.push(<a key={k++} href={href} target="_blank" rel="noopener noreferrer" style={{ color: "var(--accent)", textDecoration: "underline" }}>{m[1]}</a>);
      else out.push(m[1]!); // unsafe scheme → plain text
    } else if (m[3] ?? m[4]) out.push(<strong key={k++}>{m[3] ?? m[4]}</strong>);
    else if (m[5]) out.push(<em key={k++}>{m[5]}</em>);
    else if (m[6]) out.push(<code key={k++} style={CODE_STYLE}>{m[6]}</code>);
    last = re.lastIndex;
  }
  if (last < s.length) out.push(s.slice(last));
  return out;
}

type Block =
  | { t: "h"; level: number; text: string }
  | { t: "p"; lines: string[] }
  | { t: "ul"; items: { text: string; task?: boolean; checked?: boolean }[] }
  | { t: "ol"; items: string[] }
  | { t: "quote"; lines: string[] }
  | { t: "table"; header: string[]; rows: string[][] }
  | { t: "hr" }
  | { t: "code"; text: string };

const splitRow = (l: string) => l.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map((c) => c.trim());
const isBlockStart = (l: string) =>
  /^(#{1,6}\s|>\s?|\s*[-*+]\s+|\s*\d+[.)]\s+|```)/.test(l) || /^\s*([-*_])\1\1[-*_ ]*$/.test(l);

function parseBlocks(src: string): Block[] {
  const lines = src.replace(/\r\n/g, "\n").split("\n");
  const blocks: Block[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i]!;
    if (!line.trim()) { i++; continue; }
    if (/^```/.test(line)) {
      const buf: string[] = []; i++;
      while (i < lines.length && !/^```/.test(lines[i]!)) { buf.push(lines[i]!); i++; }
      i++;
      blocks.push({ t: "code", text: buf.join("\n") }); continue;
    }
    if (/^\s*([-*_])\1\1[-*_ ]*$/.test(line)) { blocks.push({ t: "hr" }); i++; continue; }
    const h = /^(#{1,6})\s+(.*)$/.exec(line);
    if (h) { blocks.push({ t: "h", level: h[1]!.length, text: h[2]!.trim() }); i++; continue; }
    if (line.includes("|") && i + 1 < lines.length && /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$/.test(lines[i + 1]!)) {
      const header = splitRow(line); i += 2;
      const rows: string[][] = [];
      while (i < lines.length && lines[i]!.includes("|") && lines[i]!.trim()) { rows.push(splitRow(lines[i]!)); i++; }
      blocks.push({ t: "table", header, rows }); continue;
    }
    if (/^\s*>\s?/.test(line)) {
      const buf: string[] = [];
      while (i < lines.length && /^\s*>\s?/.test(lines[i]!)) { buf.push(lines[i]!.replace(/^\s*>\s?/, "")); i++; }
      blocks.push({ t: "quote", lines: buf }); continue;
    }
    if (/^\s*[-*+]\s+/.test(line)) {
      const items: { text: string; task?: boolean; checked?: boolean }[] = [];
      while (i < lines.length && /^\s*[-*+]\s+/.test(lines[i]!)) {
        const it = lines[i]!.replace(/^\s*[-*+]\s+/, "");
        const task = /^\[( |x|X)\]\s+/.exec(it);
        if (task) items.push({ text: it.replace(/^\[( |x|X)\]\s+/, ""), task: true, checked: task[1]!.toLowerCase() === "x" });
        else items.push({ text: it });
        i++;
      }
      blocks.push({ t: "ul", items }); continue;
    }
    if (/^\s*\d+[.)]\s+/.test(line)) {
      const items: string[] = [];
      while (i < lines.length && /^\s*\d+[.)]\s+/.test(lines[i]!)) { items.push(lines[i]!.replace(/^\s*\d+[.)]\s+/, "")); i++; }
      blocks.push({ t: "ol", items }); continue;
    }
    const buf: string[] = [];
    while (i < lines.length && lines[i]!.trim() && !isBlockStart(lines[i]!)) { buf.push(lines[i]!); i++; }
    blocks.push({ t: "p", lines: buf });
  }
  return blocks;
}

function renderBlock(b: Block, key: number): ReactNode {
  switch (b.t) {
    case "h": {
      const size = b.level <= 1 ? 17 : b.level === 2 ? 15.5 : 14;
      return <div key={key} style={{ fontSize: size, fontWeight: 700, margin: "2px 0", letterSpacing: "-0.01em" }}>{inline(b.text)}</div>;
    }
    case "hr": return <hr key={key} style={{ border: "none", borderTop: "1px solid var(--border)", margin: "4px 0" }} />;
    case "code": return <pre key={key} style={{ background: "var(--surface-2)", padding: "10px 12px", borderRadius: 8, overflowX: "auto", fontSize: 12.5, margin: 0 }}><code>{b.text}</code></pre>;
    case "quote": return <blockquote key={key} style={{ margin: 0, padding: "2px 0 2px 12px", borderLeft: "3px solid var(--accent-soft)", color: "var(--text-2)" }}>{b.lines.map((l, i) => <div key={i}>{inline(l)}</div>)}</blockquote>;
    case "ul": {
      const hasTask = b.items.some((it) => it.task);
      return (
        <ul key={key} style={{ margin: 0, paddingLeft: hasTask ? 0 : 20, listStyle: hasTask ? "none" : undefined, display: "grid", gap: 4 }}>
          {b.items.map((it, i) => it.task
            ? <li key={i} style={{ display: "flex", gap: 8, alignItems: "flex-start", listStyle: "none" }}>
                <input type="checkbox" checked={!!it.checked} readOnly aria-label={it.text} style={{ marginTop: 3, flexShrink: 0 }} />
                <span style={{ textDecoration: it.checked ? "line-through" : "none", color: it.checked ? "var(--text-2)" : "inherit" }}>{inline(it.text)}</span>
              </li>
            : <li key={i}>{inline(it.text)}</li>)}
        </ul>
      );
    }
    case "ol": return <ol key={key} style={{ margin: 0, paddingLeft: 20, display: "grid", gap: 4 }}>{b.items.map((it, i) => <li key={i}>{inline(it)}</li>)}</ol>;
    case "table": return (
      <div key={key} style={{ overflowX: "auto", border: "1px solid var(--border)", borderRadius: 8 }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13 }}>
          <thead><tr>{b.header.map((hd, i) => <th key={i} style={{ textAlign: i === 0 ? "left" : "right", padding: "7px 12px", fontWeight: 600, color: "var(--text-2)", whiteSpace: "nowrap", borderBottom: "1px solid var(--border)" }}>{inline(hd)}</th>)}</tr></thead>
          <tbody>{b.rows.map((r, ri) => <tr key={ri}>{b.header.map((_, ci) => <td key={ci} style={{ textAlign: ci === 0 ? "left" : "right", padding: "7px 12px", borderTop: ri === 0 ? "none" : "1px solid var(--border)", fontWeight: ci === 0 ? 600 : 400, whiteSpace: "nowrap" }}>{inline(r[ci] ?? "")}</td>)}</tr>)}</tbody>
        </table>
      </div>
    );
    case "p": default: return <p key={key} style={{ margin: 0, lineHeight: 1.5 }}>{b.lines.map((l, i) => <span key={i}>{i > 0 && <br />}{inline(l)}</span>)}</p>;
  }
}

/** Render assistant prose as safe markdown (block + inline). */
export function Markdown({ text }: { text: string }) {
  return <div style={{ display: "grid", gap: 8 }}>{parseBlocks(text).map((b, i) => renderBlock(b, i))}</div>;
}

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
export interface UiChartPoint { x: string; y: number }
export interface UiChartCard { kind: "chart"; label: string; chart: "line" | "bar"; points: UiChartPoint[]; value?: string | undefined }
export type UiCard = UiStatCard | UiProgressCard | UiBreakdownCard | UiChartCard;

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
  if (c.kind === "chart" && isStr(c.label) && (c.chart === "line" || c.chart === "bar") && Array.isArray(c.points)) {
    const points = c.points
      .filter((p): p is Record<string, unknown> => !!p && typeof p === "object")
      .filter((p) => isStr(p.x) && typeof p.y === "number" && Number.isFinite(p.y))
      .slice(0, 12)
      .map((p) => ({ x: p.x as string, y: p.y as number }));
    return points.length >= 2 ? { kind: "chart", label: c.label, chart: c.chart, points, value: isStr(c.value) ? c.value : undefined } : null;
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

/** A small line/bar trend chart (time series) — recharts, matching the dashboard. */
function ChartCard({ card }: { card: UiChartCard }) {
  const gid = "ac" + useId().replace(/[:]/g, "");
  const data = card.points.map((p) => ({ x: p.x, y: p.y }));
  return (
    <div className="card" style={{ padding: "14px 16px", display: "grid", gap: 6 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
        <span className="eyebrow">{card.label}</span>
        {card.value && <span style={{ fontWeight: 750, fontSize: 16, letterSpacing: "-0.01em" }}>{card.value}</span>}
      </div>
      <ResponsiveContainer width="100%" height={150}>
        {card.chart === "line" ? (
          <AreaChart data={data} margin={{ top: 8, right: 6, bottom: 0, left: -16 }}>
            <defs>
              <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.35} />
                <stop offset="100%" stopColor="var(--accent)" stopOpacity={0.02} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis dataKey="x" tick={AXIS} axisLine={false} tickLine={false} interval="preserveStartEnd" minTickGap={16} />
            <YAxis tick={AXIS} axisLine={false} tickLine={false} width={40} tickFormatter={compactNum} />
            <Tooltip content={<ChartTip />} cursor={{ stroke: "var(--border-strong)" }} />
            <Area type="monotone" dataKey="y" stroke="var(--accent)" strokeWidth={2.6} fill={`url(#${gid})`} dot={false} activeDot={{ r: 4, strokeWidth: 0 }} />
          </AreaChart>
        ) : (
          <BarChart data={data} margin={{ top: 8, right: 6, bottom: 0, left: -16 }}>
            <defs>
              <linearGradient id={gid} x1="0" y1="0" x2="0" y2="1">
                <stop offset="0%" stopColor="var(--accent)" stopOpacity={0.95} />
                <stop offset="100%" stopColor="var(--accent)" stopOpacity={0.5} />
              </linearGradient>
            </defs>
            <CartesianGrid vertical={false} stroke="var(--border)" />
            <XAxis dataKey="x" tick={AXIS} axisLine={false} tickLine={false} interval="preserveStartEnd" minTickGap={12} />
            <YAxis tick={AXIS} axisLine={false} tickLine={false} width={40} tickFormatter={compactNum} />
            <Tooltip content={<ChartTip />} cursor={{ fill: "var(--surface-2)" }} />
            <Bar dataKey="y" radius={[6, 6, 0, 0]} maxBarSize={40}>
              {data.map((_, i) => <Cell key={i} fill={`url(#${gid})`} />)}
            </Bar>
          </BarChart>
        )}
      </ResponsiveContainer>
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
        c.kind === "progress" ? <ProgressCard key={i} card={c} />
        : c.kind === "chart" ? <ChartCard key={i} card={c} />
        : <BreakdownCard key={i} card={c as UiBreakdownCard} />,
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
