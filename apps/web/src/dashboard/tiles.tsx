"use client";

import { useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import {
  ResponsiveContainer, PieChart, Pie, Cell, Tooltip,
  BarChart, Bar, AreaChart, Area, XAxis, YAxis, LabelList,
} from "recharts";
import { money, format, toMajor, type Money } from "@pocketcare/money";
import { budgetProgress } from "@pocketcare/budget";
import { monthlyEquivalent, emiDueDate } from "@pocketcare/finance";
import type { BudgetLike } from "@pocketcare/data";
import type { Transaction, Period } from "@pocketcare/types";
import { getRepositories } from "../powersync";
import { useAccountBalances, useBaseCurrency, useCurrencyBreakdown, useConvertAmount } from "../hooks";
import { useAmountsHidden } from "../prefs";
import { colorForId } from "../colors";
import { useFriendBalances, useUserProfiles } from "../splits/hooks";
import { useSplitInfo, collapseSplitRows } from "../splits/collapse";
import { SplitChip } from "../ui/TransactionRow";
import { bucketLabel, bucketIcon } from "../cashflow/model";
import type { TileId } from "../dashboard";

const PIE = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#4f46e5", "#7c7264"];
const major = (m: number) => m / 100;

/** Tile metadata used by the dashboard grid and the Customize panel. */
export interface TileMeta {
  id: TileId;
  title: string;
  /** Layout width in the 2-column dashboard grid. */
  span: "full" | "half";
  /** Premium-only tiles (mirror the Insights page gating). */
  premium?: boolean;
}

export const TILE_CATALOG: TileMeta[] = [
  { id: "recent", title: "Recent activity", span: "half" },
  { id: "spending", title: "Spending this month", span: "half" },
  { id: "upcoming", title: "Upcoming payments", span: "half" },
  { id: "trends", title: "Expense trends", span: "full" },
  { id: "splits", title: "Friends & splits", span: "half" },
  { id: "budgets", title: "Budgets", span: "full" },
  { id: "goals", title: "Goals", span: "full" },
  { id: "subscriptions", title: "Subscriptions", span: "half" },
  { id: "cashflow", title: "Cashflow", span: "full", premium: true },
  { id: "netTrend", title: "Net cashflow trend", span: "full", premium: true },
  { id: "byCategory", title: "Spending by category", span: "half", premium: true },
  { id: "byLabel", title: "Spending by label", span: "half", premium: true },
  { id: "monthCompare", title: "This month vs last", span: "full", premium: true },
  { id: "currencies", title: "Across currencies", span: "half" },
];

export const tileMeta = (id: TileId): TileMeta => TILE_CATALOG.find((t) => t.id === id)!;

/**
 * Where a tap on each tile navigates for "more details". Some deep-link with a
 * hash so the target page scrolls straight to the relevant section (e.g. the
 * merged subscriptions live under the Planned Cashflow payments section).
 */
export const TILE_HREF: Record<TileId, string> = {
  recent: "/transactions",
  spending: "/transactions",
  upcoming: "/cashflow#payments",
  trends: "/insights",
  splits: "/friends",
  budgets: "/budgets",
  goals: "/goals",
  subscriptions: "/cashflow#payments",
  cashflow: "/cashflow",
  netTrend: "/insights",
  byCategory: "/insights",
  byLabel: "/insights",
  monthCompare: "/insights",
  currencies: "/accounts",
};

function TileCard({ title, action, children }: { title: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 12, alignContent: "start", minWidth: 0, maxWidth: "100%", overflowX: "hidden" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8, minWidth: 0 }}>
        <h2 style={{ margin: 0, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{title}</h2>
        <span style={{ flexShrink: 0 }}>{action}</span>
      </div>
      {children}
    </section>
  );
}

/* ---- Gradient "showpiece" tiles (light content on an earthy gradient) ---- */
const HERO = {
  cashflow: { grad: "linear-gradient(150deg,#b06a4f 0%,#8f533c 100%)", glow: "0 20px 44px -22px rgba(176,106,79,0.75)" },
  budgets: { grad: "linear-gradient(150deg,#c08a3e 0%,#a8503a 100%)", glow: "0 20px 44px -22px rgba(192,138,62,0.7)" },
  goals: { grad: "linear-gradient(150deg,#2f6f6a 0%,#3e4a38 100%)", glow: "0 20px 44px -22px rgba(47,111,106,0.7)" },
  subs: { grad: "linear-gradient(150deg,#7a4a6b 0%,#4f3a54 100%)", glow: "0 20px 44px -22px rgba(122,74,107,0.7)" },
} as const;
const HERO_MUTED = "rgba(246,240,231,0.82)";

function HeroTile({ title, action, grad, glow, children }: { title: string; action?: React.ReactNode; grad: string; glow: string; children: React.ReactNode }) {
  return (
    <section style={{ position: "relative", borderRadius: 24, padding: "22px 24px", color: "#f6f0e7", background: grad, boxShadow: glow, display: "grid", gap: 14, alignContent: "start" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <div style={{ fontSize: 12, fontWeight: 600, letterSpacing: "0.06em", textTransform: "uppercase", color: "rgba(246,240,231,0.72)" }}>{title}</div>
        {action}
      </div>
      {children}
    </section>
  );
}
const heroLink = (href: string, label: string) => (
  <Link href={href} style={{ fontSize: 12.5, fontWeight: 600, color: "rgba(246,240,231,0.9)" }}>{label}</Link>
);
function LightBar({ pct, color = "#f6f0e7" }: { pct: number; color?: string }) {
  return (
    <div style={{ height: 8, borderRadius: 999, background: "rgba(255,255,255,0.18)", overflow: "hidden" }}>
      <div style={{ height: "100%", width: `${Math.max(0, Math.min(100, pct))}%`, borderRadius: 999, background: color }} />
    </div>
  );
}
function HeroArea({ values, stroke = "#f6ede2", fillId }: { values: number[]; stroke?: string; fillId: string }) {
  if (values.length < 2) return null;
  const w = 300, h = 56, pad = 3;
  const min = Math.min(...values), max = Math.max(...values), range = max - min || 1;
  const pts = values.map((v, i) => [(i / (values.length - 1)) * w, h - pad - ((v - min) / range) * (h - pad * 2)] as const);
  const line = pts.map((p, i) => `${i ? "L" : "M"}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(" ");
  const area = `${line} L ${w} ${h} L 0 ${h} Z`;
  return (
    <svg viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" width="100%" height="56" style={{ display: "block" }}>
      <defs><linearGradient id={fillId} x1="0" y1="0" x2="0" y2="1"><stop offset="0" stopColor={stroke} stopOpacity="0.45" /><stop offset="1" stopColor={stroke} stopOpacity="0" /></linearGradient></defs>
      <path d={area} fill={`url(#${fillId})`} />
      <path d={line} fill="none" stroke={stroke} strokeWidth="2.2" vectorEffect="non-scaling-stroke" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

/** Render the tile for a given id. */
export function TileView({ id }: { id: TileId }) {
  switch (id) {
    case "recent": return <RecentTile />;
    case "spending": return <SpendingTile />;
    case "upcoming": return <UpcomingTile />;
    case "trends": return <TrendsTile />;
    case "splits": return <SplitsTile />;
    case "budgets": return <BudgetsTile />;
    case "goals": return <GoalsTile />;
    case "subscriptions": return <SubscriptionsTile />;
    case "cashflow": return <CashflowTile />;
    case "netTrend": return <NetTrendTile />;
    case "byCategory": return <ByCategoryTile />;
    case "byLabel": return <ByLabelTile />;
    case "monthCompare": return <MonthCompareTile />;
    case "currencies": return <CurrenciesTile />;
    default: return null;
  }
}

// ------------------------------- Tiles -------------------------------

function SplitsTile() {
  const hidden = useAmountsHidden();
  const base = useBaseCurrency();
  const balances = useFriendBalances();
  const profiles = useUserProfiles();
  const name = (id: string) => profiles.get(id)?.name ?? "Someone";
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);
  const top = [...balances].filter((b) => b.net !== 0).sort((a, b) => Math.abs(b.net) - Math.abs(a.net)).slice(0, 3);
  const fmt = (m: number) => (hidden ? "••••" : format(money(m, base), "en-US"));
  return (
    <TileCard title="Friends & splits" action={<Link href="/friends" className="muted" style={{ fontSize: 13 }}>Open →</Link>}>
      <div style={{ display: "flex", gap: 20, flexWrap: "wrap" }}>
        <div><div className="muted" style={{ fontSize: 12 }}>You’re owed</div><div style={{ fontSize: 22, fontWeight: 750, color: "var(--positive)" }}>{fmt(owed)}</div></div>
        <div><div className="muted" style={{ fontSize: 12 }}>You owe</div><div style={{ fontSize: 22, fontWeight: 750, color: "var(--negative)" }}>{fmt(owe)}</div></div>
      </div>
      {top.length > 0 ? (
        <div style={{ display: "grid", gap: 6 }}>
          {top.map((b) => (
            <div key={b.userId} style={{ display: "flex", justifyContent: "space-between", fontSize: 13, gap: 8 }}>
              <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{name(b.userId)}</span>
              <span style={{ flexShrink: 0, color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{b.net > 0 ? `owes you ${fmt(b.net)}` : `you owe ${fmt(-b.net)}`}</span>
            </div>
          ))}
        </div>
      ) : (
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>No open balances yet. Split an expense from <Link href="/transactions/new">Add transaction</Link>.</p>
      )}
    </TileCard>
  );
}

function CurrenciesTile() {
  const hidden = useAmountsHidden();
  const { base, slices, total } = useCurrencyBreakdown();
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));
  return (
    <TileCard title="Across currencies" action={<Link href="/accounts" className="muted" style={{ fontSize: 13 }}>Accounts →</Link>}>
      {slices.length < 2 ? (
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>All your money is in {base}. Add an account in another currency to see the split, converted to {base}.</p>
      ) : (
        <div style={{ display: "grid", gap: 10 }}>
          <div style={{ display: "flex", height: 10, borderRadius: 999, overflow: "hidden", background: "var(--surface-2)" }}>
            {slices.map((s, i) => {
              const pct = total !== 0 ? Math.max(0, (s.base / total) * 100) : 0;
              return <div key={s.currency} title={`${s.currency} ${pct.toFixed(0)}%`} style={{ width: `${pct}%`, background: PIE[i % PIE.length] }} />;
            })}
          </div>
          <div style={{ display: "grid", gap: 6 }}>
            {slices.map((s, i) => {
              const pct = total !== 0 ? (s.base / total) * 100 : 0;
              return (
                <div key={s.currency} style={{ display: "flex", justifyContent: "space-between", fontSize: 13, gap: 8 }}>
                  <span style={{ display: "inline-flex", alignItems: "center", gap: 8, minWidth: 0, overflow: "hidden" }}>
                    <span style={{ color: PIE[i % PIE.length] }}>●</span> <strong>{s.currency}</strong>
                    <span className="muted" style={{ whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{fmt(money(s.native, s.currency))}</span>
                  </span>
                  <span className="muted" style={{ flexShrink: 0 }}>{s.currency === base ? "" : `≈ ${fmt(money(s.base, base))} · `}{pct.toFixed(0)}%</span>
                </div>
              );
            })}
          </div>
        </div>
      )}
    </TileCard>
  );
}

function RecentTile() {
  const hidden = useAmountsHidden();
  const balances = useAccountBalances();
  const { data: recent = [] } = useQuery<Transaction & { labels: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels
     FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance' ORDER BY t.occurred_at DESC LIMIT 16`,
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL");
  const catName = (cid: string | null) => cats.find((c) => c.id === cid)?.name ?? "Uncategorised";
  const acctColor = (aid: string) => balances.find((b) => b.account.id === aid)?.account.color || colorForId(aid);
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));
  const splitInfo = useSplitInfo();
  // Collapse split postings, then keep the 6 most-recent tiles.
  const collapsed = collapseSplitRows(recent, splitInfo).slice(0, 6);

  return (
    <TileCard title="Recent activity" action={<Link className="muted" style={{ fontSize: 13 }} href="/transactions">View all</Link>}>
      <div style={{ display: "grid", gap: 8 }}>
        {collapsed.map(({ row: t, split }) => (
          <Link key={t.id} className="tap-row" href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", gap: 10, padding: "8px", margin: "0 -8px", borderBottom: "1px solid var(--border)", color: "inherit" }}>
            <div style={{ display: "flex", gap: 10, alignItems: "center", minWidth: 0, flex: 1 }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, background: acctColor(t.account_id), flexShrink: 0 }} />
              <div style={{ minWidth: 0 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6, minWidth: 0 }}>
                  <span style={{ fontWeight: 550, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{t.description || t.labels || catName(t.category_id)}</span>
                  {split && <SplitChip />}
                </div>
                <div className="muted" style={{ fontSize: 12 }}>{new Date(t.occurred_at).toLocaleDateString()} · {split ? "split" : t.type}</div>
              </div>
            </div>
            <div style={{ flexShrink: 0, whiteSpace: "nowrap", fontWeight: 650, color: !split && t.type === "income" ? "var(--positive)" : split || t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
              {split ? "−" : t.type === "expense" ? "−" : t.type === "income" ? "+" : ""}{fmt(money(split ? split.displayPaid : t.amount, split ? split.currency : t.currency))}
            </div>
          </Link>
        ))}
        {collapsed.length === 0 && <p className="muted">No transactions yet.</p>}
      </div>
    </TileCard>
  );
}

function SpendingTile() {
  const base = useBaseCurrency();
  const hidden = useAmountsHidden();
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL");
  const catName = (cid: string | null) => cats.find((c) => c.id === cid)?.name ?? "Uncategorised";
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
  const { data: spend = [] } = useQuery<{ category_id: string | null; total: number }>(
    `SELECT category_id, SUM(amount) as total FROM transactions
     WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= ? GROUP BY category_id ORDER BY total DESC`,
    [monthStart],
  );
  const pieData = spend.slice(0, 7).map((s) => ({ name: catName(s.category_id), value: s.total }));
  const total = pieData.reduce((s, d) => s + d.value, 0);
  const pct = (v: number) => (total > 0 ? (v / total) * 100 : 0);

  return (
    <TileCard title="Spending this month">
      {pieData.length ? (
        <ResponsiveContainer width="100%" height={220}>
          <PieChart>
            {/* minAngle guarantees even tiny categories get a visible slice next to a big one */}
            <Pie data={pieData} dataKey="value" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={2} minAngle={6}>
              {pieData.map((_, i) => <Cell key={i} fill={PIE[i % PIE.length]} />)}
            </Pie>
            {!hidden && <Tooltip formatter={(v: number) => `${(v / 100).toFixed(2)} · ${pct(v).toFixed(1)}%`} />}
          </PieChart>
        </ResponsiveContainer>
      ) : (
        <p className="muted">No spending recorded this month.</p>
      )}
      <div style={{ display: "grid", gap: 4 }}>
        {pieData.map((d, i) => (
          <div key={d.name} style={{ display: "flex", justifyContent: "space-between", fontSize: 13, gap: 8 }}>
            <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}><span style={{ color: PIE[i % PIE.length] }}>●</span> {d.name}</span>
            <span className="muted" style={{ flexShrink: 0 }}>{pct(d.value).toFixed(1)}%{hidden ? "" : ` · ${toMajor(money(d.value, base)).toFixed(2)}`}</span>
          </div>
        ))}
      </div>
    </TileCard>
  );
}

function BudgetsTile() {
  const { data: budgets = [] } = useQuery<BudgetLike>(
    "SELECT id, name, period, start_date, end_date, limit_amount, currency, threshold_pct FROM budgets WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT 6",
  );
  // Cap what we render to what fits the default tile height (~3 rows); surface
  // the rest via a "+N more" link so the tile never overflows its gradient card.
  const shown = budgets.slice(0, 4);
  const extra = budgets.length - shown.length;
  return (
    <HeroTile title="Budgets" grad={HERO.budgets.grad} glow={HERO.budgets.glow} action={heroLink("/budgets", "Manage")}>
      {budgets.length ? (
        <div style={{ display: "grid", gap: 12, minWidth: 0 }}>
          {shown.map((b) => <BudgetMini key={b.id} budget={b} />)}
          {extra > 0 && (
            <Link href="/budgets" style={{ fontSize: 12.5, fontWeight: 600, color: "rgba(246,240,231,0.9)" }}>+{extra} more →</Link>
          )}
        </div>
      ) : (
        <p style={{ margin: 0, color: HERO_MUTED }}>No budgets yet. <Link href="/budgets" style={{ color: "#fff", textDecoration: "underline" }}>Create one</Link>.</p>
      )}
    </HeroTile>
  );
}

function BudgetMini({ budget }: { budget: BudgetLike }) {
  const hidden = useAmountsHidden();
  const [spent, setSpent] = useState<Money>(money(0, budget.currency));
  useEffect(() => {
    let active = true;
    void getRepositories().budgets.spentThisPeriod(budget).then((s) => active && setSpent(s));
    return () => { active = false; };
  }, [budget]);
  const limit = money(budget.limit_amount, budget.currency);
  const p = budgetProgress(limit, spent, budget.threshold_pct);
  const fill = p.overLimit ? "#f0d8c9" : p.atOrOverThreshold ? "#f3e4c6" : "#dde7c9";
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));
  return (
    <div style={{ display: "grid", gap: 6, minWidth: 0 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", fontSize: 13, gap: 8, minWidth: 0 }}>
        <span style={{ fontWeight: 600, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{budget.name || budget.period}</span>
        <span style={{ color: HERO_MUTED, flexShrink: 0, whiteSpace: "nowrap", maxWidth: "58%", overflow: "hidden", textOverflow: "ellipsis" }}>{fmt(spent)} / {fmt(limit)}</span>
      </div>
      <LightBar pct={p.pct} color={fill} />
    </div>
  );
}

function GoalsTile() {
  const { data: goals = [] } = useQuery<{ id: string; name: string; target_amount: number; currency: string; is_emergency_fund: number }>(
    "SELECT id, name, target_amount, currency, is_emergency_fund FROM goals WHERE deleted_at IS NULL ORDER BY is_emergency_fund DESC, priority LIMIT 6",
  );
  const { data: allocs = [] } = useQuery<{ goal_id: string; amount_blocked: number }>(
    "SELECT goal_id, amount_blocked FROM goal_allocations WHERE deleted_at IS NULL",
  );
  const hidden = useAmountsHidden();
  const saved = (gid: string) => allocs.filter((a) => a.goal_id === gid).reduce((s, a) => s + a.amount_blocked, 0);
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));

  return (
    <HeroTile title="Goals" grad={HERO.goals.grad} glow={HERO.goals.glow} action={heroLink("/goals", "Manage")}>
      {goals.length ? (
        <div style={{ display: "grid", gap: 14 }}>
          {goals.map((g) => {
            const s = saved(g.id);
            const pct = g.target_amount ? Math.min(100, (s / g.target_amount) * 100) : 0;
            return (
              <div key={g.id} style={{ display: "grid", gap: 6 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13, gap: 8 }}>
                  <span style={{ fontWeight: 600, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{g.name}{g.is_emergency_fund ? " · EF" : ""}</span>
                  <span style={{ color: HERO_MUTED, flexShrink: 0, whiteSpace: "nowrap" }}>{fmt(money(s, g.currency))} / {fmt(money(g.target_amount, g.currency))}</span>
                </div>
                <LightBar pct={pct} color={g.is_emergency_fund ? "#c6cdb3" : "#f3e4c6"} />
              </div>
            );
          })}
        </div>
      ) : (
        <p style={{ margin: 0, color: HERO_MUTED }}>No goals yet. <Link href="/goals" style={{ color: "#fff", textDecoration: "underline" }}>Add one</Link>.</p>
      )}
    </HeroTile>
  );
}

function SubscriptionsTile() {
  const base = useBaseCurrency();
  const hidden = useAmountsHidden();
  const { data: subs = [] } = useQuery<{ name: string; amount: number; currency: string; billing_cycle: string; next_renewal: string | null }>(
    "SELECT name, amount, currency, billing_cycle, next_renewal FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1 ORDER BY next_renewal",
  );
  const monthly = subs.reduce((s, x) => s + monthlyEquivalent(x.amount, x.billing_cycle as Period), 0);
  const fmt = (m: number, c: string = base) => (hidden ? "••••" : format(money(Math.round(m), c), "en-US"));
  const upcoming = subs.filter((x) => x.next_renewal).slice(0, 3);
  return (
    <HeroTile title="Subscriptions" grad={HERO.subs.grad} glow={HERO.subs.glow} action={heroLink("/cashflow#payments", "Manage")}>
      {subs.length === 0 ? (
        <p style={{ margin: 0, color: HERO_MUTED }}>No active subscriptions. <Link href="/subscriptions" style={{ color: "#fff", textDecoration: "underline" }}>Add one</Link>.</p>
      ) : (
        <>
          <div>
            <div style={{ fontSize: 32, fontWeight: 750 }}>{fmt(monthly)}<span style={{ fontSize: 15, fontWeight: 600, color: HERO_MUTED }}> /mo</span></div>
            <div style={{ fontSize: 13, color: HERO_MUTED, marginTop: 4 }}>{subs.length} active {subs.length === 1 ? "subscription" : "subscriptions"}</div>
          </div>
          {upcoming.length > 0 && (
            <div style={{ display: "grid", gap: 8, borderTop: "1px solid rgba(255,255,255,0.16)", paddingTop: 12 }}>
              {upcoming.map((x, i) => (
                <div key={i} style={{ display: "flex", justifyContent: "space-between", gap: 8, fontSize: 13 }}>
                  <span style={{ fontWeight: 600, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{x.name}</span>
                  <span style={{ color: HERO_MUTED, flexShrink: 0, whiteSpace: "nowrap" }}>{fmt(x.amount, x.currency)}{x.next_renewal ? ` · ${new Date(x.next_renewal).toLocaleDateString(undefined, { month: "short", day: "numeric" })}` : ""}</span>
                </div>
              ))}
            </div>
          )}
        </>
      )}
    </HeroTile>
  );
}

// ----- Upcoming payments -----

interface Upcoming { key: string; name: string; sub: string; icon: string; date: Date; amountBase: number }

const startOfToday = () => { const d = new Date(); d.setHours(0, 0, 0, 0); return d; };
const asDate = (iso: string | null): Date | null => {
  if (!iso) return null;
  const d = new Date(iso.length <= 10 ? `${iso}T00:00:00` : iso);
  return Number.isNaN(d.getTime()) ? null : d;
};

/** Roll a recurring anchor date forward to its next occurrence on/after `today`. */
function nextOccurrence(anchor: string | null, freq: string, today: Date): Date | null {
  const d = asDate(anchor);
  if (!d) return null;
  let guard = 0;
  while (d < today && guard++ < 1200) {
    if (freq === "daily") d.setDate(d.getDate() + 1);
    else if (freq === "weekly") d.setDate(d.getDate() + 7);
    else if (freq === "yearly") d.setFullYear(d.getFullYear() + 1);
    else d.setMonth(d.getMonth() + 1); // monthly (default)
  }
  return d;
}

/** Next EMI due date for a loan (first unpaid EMI whose due date is on/after today). */
function nextEmiDate(loan: { start_date: string | null; emi_due_day: number | null; tenure_months: number | null; emis_paid: number | null }, today: Date): Date | null {
  const tenure = loan.tenure_months ?? 0;
  let n = (loan.emis_paid ?? 0) + 1;
  if (tenure && n > tenure) return null;
  let due = asDate(emiDueDate(loan.start_date, loan.emi_due_day, n));
  let guard = 0;
  while (due && due < today && (!tenure || n < tenure) && guard++ < 1200) {
    n += 1;
    due = asDate(emiDueDate(loan.start_date, loan.emi_due_day, n));
  }
  return due;
}

function useUpcomingPayments(): Upcoming[] {
  const convert = useConvertAmount();
  const { data: subs = [] } = useQuery<{ id: string; name: string; amount: number; currency: string; billing_cycle: string; next_renewal: string | null }>(
    "SELECT id, name, amount, currency, billing_cycle, next_renewal FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1",
  );
  const { data: loans = [] } = useQuery<{ id: string; lender: string; emi_amount: number | null; currency: string; start_date: string | null; emi_due_day: number | null; tenure_months: number | null; emis_paid: number | null }>(
    "SELECT id, lender, emi_amount, currency, start_date, emi_due_day, tenure_months, emis_paid FROM loans WHERE deleted_at IS NULL",
  );
  const { data: planned = [] } = useQuery<{ id: string; name: string; direction: string; bucket: string; amount: number; currency: string; frequency: string; next_due: string | null }>(
    "SELECT id, name, direction, bucket, amount, currency, frequency, next_due FROM planned_cashflow WHERE deleted_at IS NULL AND is_active = 1 AND direction IN ('payment','saving')",
  );
  const { data: cards = [] } = useQuery<{ account_id: string; name: string; currency: string; pending_due: number | null; due_on: string | null }>(
    "SELECT cd.account_id AS account_id, a.name AS name, a.currency AS currency, cd.pending_due AS pending_due, cd.due_on AS due_on FROM credit_card_details cd JOIN accounts a ON a.id = cd.account_id WHERE a.deleted_at IS NULL",
  );
  const { data: rules = [] } = useQuery<{ id: string; name: string; type: string; amount: number | null; currency: string | null; frequency: string; next_due: string }>(
    `SELECT r.id AS id, t.name AS name, t.type AS type, t.amount AS amount, t.currency AS currency, r.frequency AS frequency, r.next_due AS next_due
     FROM recurring_rules r JOIN transaction_templates t ON t.id = r.template_id
     WHERE r.deleted_at IS NULL AND t.deleted_at IS NULL AND r.active = 1 AND t.type IN ('expense','transfer')`,
  );

  return useMemo(() => {
    const today = startOfToday();
    const out: Upcoming[] = [];
    for (const s of subs) {
      const d = nextOccurrence(s.next_renewal, s.billing_cycle, today);
      if (d) out.push({ key: `sub:${s.id}`, name: s.name || "Subscription", sub: "Subscription", icon: "↻", date: d, amountBase: convert(s.amount, s.currency) });
    }
    for (const l of loans) {
      if (!l.emi_amount) continue;
      const d = nextEmiDate(l, today);
      if (d) out.push({ key: `emi:${l.id}`, name: `${l.lender || "Loan"} EMI`, sub: "Loan EMI", icon: "≈", date: d, amountBase: convert(l.emi_amount, l.currency) });
    }
    for (const p of planned) {
      const d = nextOccurrence(p.next_due, p.frequency, today);
      if (!d) continue;
      const isSaving = p.direction === "saving";
      out.push({
        key: `pc:${p.id}`,
        name: p.name || (isSaving ? "Saving" : "Payment"),
        sub: bucketLabel(p.direction as never, p.bucket),
        icon: isSaving ? (p.bucket === "sip" ? "↻" : "▲") : bucketIcon("payment", p.bucket),
        date: d,
        amountBase: convert(p.amount, p.currency),
      });
    }
    for (const c of cards) {
      if (!c.pending_due || c.pending_due <= 0) continue;
      const d = asDate(c.due_on);
      if (!d) continue;
      out.push({ key: `card:${c.account_id}`, name: `${c.name || "Card"} bill`, sub: "Credit card", icon: "▭", date: d, amountBase: convert(c.pending_due, c.currency) });
    }
    for (const r of rules) {
      if (!r.amount) continue;
      const d = nextOccurrence(r.next_due, r.frequency, today);
      if (!d) continue;
      const saving = r.type === "transfer";
      out.push({ key: `rule:${r.id}`, name: r.name || (saving ? "Saving" : "Payment"), sub: saving ? "Recurring saving" : "Recurring payment", icon: saving ? "▲" : "↻", date: d, amountBase: convert(r.amount, r.currency ?? "") });
    }
    return out.sort((a, b) => a.date.getTime() - b.date.getTime());
  }, [subs, loans, planned, cards, rules, convert]);
}

function whenLabel(d: Date, today: Date): string {
  const days = Math.round((d.getTime() - today.getTime()) / 86400000);
  if (days <= 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days < 7) return `in ${days} days`;
  return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
}

function UpcomingTile() {
  const base = useBaseCurrency();
  const hidden = useAmountsHidden();
  const items = useUpcomingPayments();
  const today = startOfToday();
  const fmt = (m: number) => (hidden ? "••••" : format(money(Math.round(m), base), "en-US"));

  const horizon = new Date(today); horizon.setDate(horizon.getDate() + 30);
  const due30 = items.filter((x) => x.date <= horizon).reduce((s, x) => s + x.amountBase, 0);
  const shown = items.slice(0, 6);

  return (
    <TileCard title="Upcoming payments" action={<Link href="/cashflow#payments" className="muted" style={{ fontSize: 13 }}>Manage →</Link>}>
      {items.length === 0 ? (
        <p className="muted" style={{ fontSize: 13, margin: 0 }}>
          No scheduled payments yet. Add subscriptions, loan EMIs, SIPs or bills from <Link href="/cashflow#payments">Planned Cashflow</Link>.
        </p>
      ) : (
        <>
          <div>
            <div className="muted" style={{ fontSize: 12 }}>Due in the next 30 days</div>
            <div style={{ fontSize: 26, fontWeight: 750 }}>{fmt(due30)}</div>
          </div>
          <div style={{ display: "grid", gap: 8, borderTop: "1px solid var(--border)", paddingTop: 10 }}>
            {shown.map((x) => {
              const overdue = x.date < today;
              return (
                <div key={x.key} style={{ display: "flex", alignItems: "center", gap: 10 }}>
                  <span aria-hidden style={{ width: 26, height: 26, flexShrink: 0, display: "grid", placeItems: "center", borderRadius: 8, background: "var(--surface-2)", fontSize: 13, color: "var(--text-2)" }}>{x.icon}</span>
                  <div style={{ minWidth: 0, flex: 1 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 600, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{x.name}</div>
                    <div className="muted" style={{ fontSize: 11.5 }}>{x.sub} · <span style={{ color: overdue ? "var(--negative)" : "var(--text-2)" }}>{overdue ? "overdue" : whenLabel(x.date, today)}</span></div>
                  </div>
                  <div style={{ fontSize: 13.5, fontWeight: 650, flexShrink: 0 }}>{fmt(x.amountBase)}</div>
                </div>
              );
            })}
          </div>
          {items.length > shown.length && <div className="muted" style={{ fontSize: 12 }}>+{items.length - shown.length} more · <Link href="/cashflow#payments">view all</Link></div>}
        </>
      )}
    </TileCard>
  );
}

// ----- Insight tiles (Premium) — mirror /insights queries -----

function useCashflow() {
  const { data: byMonth = [] } = useQuery<{ ym: string; type: string; total: number }>(
    "SELECT strftime('%Y-%m', occurred_at) as ym, type, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type IN ('income','expense') GROUP BY ym, type ORDER BY ym",
  );
  const monthsMap = new Map<string, { month: string; income: number; expense: number }>();
  for (const r of byMonth) {
    const m = monthsMap.get(r.ym) ?? { month: r.ym, income: 0, expense: 0 };
    if (r.type === "income") m.income = major(r.total); else m.expense = major(r.total);
    monthsMap.set(r.ym, m);
  }
  const cashflow = [...monthsMap.values()].slice(-8).map((m) => ({ ...m, net: +(m.income - m.expense).toFixed(2) }));
  return { byMonth, cashflow };
}

function gradientDefs() {
  return (
    <defs>
      <linearGradient id="gInc" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#5f7a52" stopOpacity={0.95} /><stop offset="100%" stopColor="#5f7a52" stopOpacity={0.55} /></linearGradient>
      <linearGradient id="gExp" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#b06a4f" stopOpacity={0.95} /><stop offset="100%" stopColor="#b06a4f" stopOpacity={0.55} /></linearGradient>
      <linearGradient id="gNet" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#3e4a38" stopOpacity={0.5} /><stop offset="100%" stopColor="#3e4a38" stopOpacity={0.03} /></linearGradient>
      <linearGradient id="gBar" x1="0" y1="0" x2="1" y2="0"><stop offset="0%" stopColor="#b06a4f" stopOpacity={0.55} /><stop offset="100%" stopColor="#b06a4f" stopOpacity={1} /></linearGradient>
      <linearGradient id="gTrend" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#b06a4f" stopOpacity={0.5} /><stop offset="100%" stopColor="#b06a4f" stopOpacity={0.03} /></linearGradient>
    </defs>
  );
}

type TrendPeriod = "3d" | "1w" | "1m" | "1y";
const MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

/** Bucket daily expense totals into period-appropriate buckets (days / weeks / months). */
function buildTrend(map: Map<string, number>, period: TrendPeriod): { label: string; value: number }[] {
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const dayKey = (d: Date) => d.toISOString().slice(0, 10);
  const out: { label: string; value: number }[] = [];
  if (period === "3d" || period === "1w") {
    const n = period === "3d" ? 3 : 7;
    for (let i = n - 1; i >= 0; i--) {
      const d = new Date(today); d.setDate(d.getDate() - i);
      out.push({ label: `${d.getDate()} ${MON[d.getMonth()]}`, value: (map.get(dayKey(d)) ?? 0) / 100 });
    }
  } else if (period === "1m") {
    for (let w = 3; w >= 0; w--) {
      const start = new Date(today); start.setDate(start.getDate() - (w * 7 + 6));
      const end = new Date(today); end.setDate(end.getDate() - w * 7);
      let sum = 0;
      for (const [k, v] of map) { const kd = new Date(k + "T00:00:00"); if (kd >= start && kd <= end) sum += v; }
      out.push({ label: `${start.getDate()} ${MON[start.getMonth()]}`, value: sum / 100 });
    }
  } else {
    for (let m = 11; m >= 0; m--) {
      const d = new Date(today.getFullYear(), today.getMonth() - m, 1);
      const ym = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
      let sum = 0;
      for (const [k, v] of map) if (k.startsWith(ym)) sum += v;
      out.push({ label: MON[d.getMonth()]!, value: sum / 100 });
    }
  }
  return out;
}

function TrendsTile() {
  const [period, setPeriod] = useState<TrendPeriod>("1m");
  const days = period === "3d" ? 3 : period === "1w" ? 7 : period === "1m" ? 28 : 365;
  const since = useMemo(() => {
    const d = new Date(); d.setHours(0, 0, 0, 0); d.setDate(d.getDate() - days + 1);
    return d.toISOString().slice(0, 10) + "T00:00:00";
  }, [days]);
  const { data: rows = [] } = useQuery<{ d: string; total: number }>(
    "SELECT date(occurred_at) as d, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= ? GROUP BY d ORDER BY d",
    [since],
  );
  const data = useMemo(() => buildTrend(new Map(rows.map((r) => [r.d, r.total])), period), [rows, period]);
  const totalMinor = rows.reduce((s, r) => s + r.total, 0);
  const base = useBaseCurrency();
  const hidden = useAmountsHidden();

  const label = period === "3d" ? "last 3 days" : period === "1w" ? "last week" : period === "1m" ? "last month" : "last year";
  return (
    <TileCard title="Expense trends" action={
      <select className="input" value={period} onChange={(e) => setPeriod(e.target.value as TrendPeriod)} style={{ width: "auto", padding: "4px 8px", fontSize: 13, height: 32 }}>
        <option value="3d">Last 3 days</option>
        <option value="1w">Last week</option>
        <option value="1m">Last month</option>
        <option value="1y">Last year</option>
      </select>
    }>
      <div className="muted" style={{ fontSize: 13, marginTop: -4 }}>
        Spent {hidden ? "••••" : format(money(totalMinor, base), "en-US")} <span style={{ opacity: 0.7 }}>· {label}</span>
      </div>
      <ResponsiveContainer width="100%" height={230}>
        <AreaChart data={data} margin={{ top: 10, right: 10, bottom: 0, left: 0 }}>
          {gradientDefs()}
          <XAxis dataKey="label" {...axisX} interval="preserveStartEnd" />
          <YAxis {...axisY} />
          <Tooltip cursor={{ stroke: "var(--border)" }} formatter={(v: number) => (hidden ? "••••" : v.toLocaleString())} />
          <Area type="monotone" dataKey="value" stroke="#b06a4f" strokeWidth={2.5} fill="url(#gTrend)" dot={false} activeDot={{ r: 5, fill: "#b06a4f", stroke: "var(--surface)", strokeWidth: 2 }} />
        </AreaChart>
      </ResponsiveContainer>
    </TileCard>
  );
}
const axisX = { tick: { fontSize: 11, fill: "var(--text-2)" }, axisLine: false, tickLine: false } as const;
/** Compact axis-tick formatter, e.g. 12.5k / 1.2M. */
const compactTick = (v: number): string => {
  const a = Math.abs(v);
  if (a >= 1_000_000) return `${(v / 1_000_000).toFixed(1)}M`;
  if (a >= 1_000) return `${(v / 1_000).toFixed(1)}k`;
  return String(Math.round(v));
};
const axisY = { tick: { fontSize: 11, fill: "var(--text-2)" }, axisLine: false, tickLine: false, width: 44, tickFormatter: compactTick } as const;

/** "YYYY-MM" -> "Jul" (append 2-digit year only when the window spans years). */
function monthLabel(ym: string, showYear: boolean): string {
  const [y, m] = ym.split("-").map(Number);
  const mon = MON[(m ?? 1) - 1] ?? ym;
  return showYear ? `${mon} '${String(y ?? 0).slice(-2)}` : mon;
}

function CashflowTile() {
  const { cashflow } = useCashflow();
  const base = useBaseCurrency();
  const hidden = useAmountsHidden();
  const fmtCur = (v: number) => (hidden ? "••••" : format(money(Math.round(v * 100), base), "en-US"));
  const totalIn = cashflow.reduce((s, c) => s + c.income, 0);
  const totalOut = cashflow.reduce((s, c) => s + c.expense, 0);
  const net = totalIn - totalOut;
  const spark = cashflow.map((c) => c.net);

  return (
    <HeroTile title="Cashflow" grad={HERO.cashflow.grad} glow={HERO.cashflow.glow} action={heroLink("/insights", "Details →")}>
      {cashflow.length === 0 ? (
        <p style={{ margin: 0, color: HERO_MUTED }}>No income or expenses yet. Add a transaction to see your cashflow.</p>
      ) : (
        <>
          <div>
            <div style={{ fontSize: 34, fontWeight: 750, letterSpacing: "-0.01em" }}>
              {net >= 0 ? "+" : "−"}{fmtCur(Math.abs(net))}<span style={{ fontSize: 14, fontWeight: 600, color: HERO_MUTED }}> net</span>
            </div>
            <div style={{ display: "flex", gap: 18, marginTop: 6, fontSize: 13 }}>
              <span style={{ color: HERO_MUTED }}>In <strong style={{ color: "#dde7c9" }}>{fmtCur(totalIn)}</strong></span>
              <span style={{ color: HERO_MUTED }}>Out <strong style={{ color: "#f3e0d9" }}>{fmtCur(totalOut)}</strong></span>
            </div>
          </div>
          <HeroArea values={spark} fillId="cfFill" />
          <div style={{ display: "flex", justifyContent: "space-between", fontSize: 10.5, color: "rgba(246,240,231,0.7)" }}>
            {cashflow.map((c, i) => <span key={i}>{monthLabel(c.month, false)}</span>)}
          </div>
        </>
      )}
    </HeroTile>
  );
}

function NetTrendTile() {
  const { cashflow } = useCashflow();
  return (
    <TileCard title="Net cashflow trend">
      <ResponsiveContainer width="100%" height={240}>
        <AreaChart data={cashflow} margin={{ top: 10, right: 12, bottom: 0, left: 6 }}>
          {gradientDefs()}
          <XAxis dataKey="month" {...axisX} /><Tooltip />
          <Area type="monotone" dataKey="net" stroke="#3e4a38" strokeWidth={2.5} fill="url(#gNet)" dot={false} activeDot={{ r: 5, fill: "#3e4a38", stroke: "var(--surface)", strokeWidth: 2 }} />
        </AreaChart>
      </ResponsiveContainer>
    </TileCard>
  );
}

function HBarTile({ title, data, empty }: { title: string; data: { name: string; value: number }[]; empty: string }) {
  return (
    <TileCard title={title}>
      {data.length ? (
        <ResponsiveContainer width="100%" height={Math.max(180, data.length * 34)}>
          <BarChart layout="vertical" data={data} margin={{ top: 4, right: 40, bottom: 4, left: 6 }}>
            {gradientDefs()}
            <XAxis type="number" hide />
            <YAxis type="category" dataKey="name" width={96} tick={{ fontSize: 12, fill: "var(--text)" }} axisLine={false} tickLine={false} />
            <Bar dataKey="value" radius={[0, 8, 8, 0]} fill="url(#gBar)" barSize={16}>
              <LabelList dataKey="value" position="right" formatter={(v: number) => v.toLocaleString()} style={{ fontSize: 11, fill: "var(--text-2)" }} />
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      ) : <p className="muted">{empty}</p>}
    </TileCard>
  );
}

function ByCategoryTile() {
  const { data: byCat = [] } = useQuery<{ name: string | null; total: number }>(
    "SELECT c.name as name, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' GROUP BY t.category_id ORDER BY total DESC LIMIT 8",
  );
  return <HBarTile title="Spending by category" data={byCat.map((r) => ({ name: r.name ?? "Uncategorised", value: major(r.total) }))} empty="No expenses recorded yet." />;
}

function ByLabelTile() {
  const { data: labelRows = [] } = useQuery<{ name: string; total: number }>(
    `SELECT l.name AS name, SUM(t.amount) AS total
     FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id JOIN transactions t ON t.id = tl.transaction_id
     WHERE t.deleted_at IS NULL AND t.type='expense' GROUP BY l.id ORDER BY total DESC LIMIT 8`,
  );
  return <HBarTile title="Spending by label" data={labelRows.map((r) => ({ name: r.name, value: major(r.total) }))} empty="Add labels to transactions to see this." />;
}

function MonthCompareTile() {
  const { byMonth } = useCashflow();
  const now = new Date();
  const thisM = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  const lastDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const lastM = `${lastDate.getFullYear()}-${String(lastDate.getMonth() + 1).padStart(2, "0")}`;
  const t = (ym: string, type: string) => major(byMonth.find((r) => r.ym === ym && r.type === type)?.total ?? 0);
  const comparison = [
    { period: "Last month", income: t(lastM, "income"), expense: t(lastM, "expense") },
    { period: "This month", income: t(thisM, "income"), expense: t(thisM, "expense") },
  ];
  return (
    <TileCard title="This month vs last">
      <ResponsiveContainer width="100%" height={240}>
        <BarChart data={comparison} margin={{ top: 10, right: 8, bottom: 0, left: 0 }} barGap={4}>
          {gradientDefs()}
          <XAxis dataKey="period" {...axisX} /><YAxis hide /><Tooltip cursor={{ fill: "var(--surface-2)" }} />
          <Bar dataKey="income" fill="url(#gInc)" radius={[6, 6, 0, 0]} maxBarSize={40} />
          <Bar dataKey="expense" fill="url(#gExp)" radius={[6, 6, 0, 0]} maxBarSize={40} />
        </BarChart>
      </ResponsiveContainer>
    </TileCard>
  );
}
