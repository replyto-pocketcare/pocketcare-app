"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import {
  ResponsiveContainer, PieChart, Pie, Cell, Tooltip,
  BarChart, Bar, LineChart, Line, XAxis, YAxis, CartesianGrid, Legend,
} from "recharts";
import { money, format, toMajor, type Money } from "@pocketcare/money";
import { budgetProgress } from "@pocketcare/budget";
import type { BudgetLike } from "@pocketcare/data";
import type { Transaction } from "@pocketcare/types";
import { getRepositories } from "../powersync";
import { useAccountBalances, useBaseCurrency } from "../hooks";
import { useAmountsHidden } from "../prefs";
import { colorForId } from "../colors";
import { ProgressBar } from "../ui/ProgressBar";
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
  { id: "budgets", title: "Budgets", span: "full" },
  { id: "goals", title: "Goals", span: "full" },
  { id: "cashflow", title: "Cashflow", span: "full", premium: true },
  { id: "netTrend", title: "Net cashflow trend", span: "full", premium: true },
  { id: "byCategory", title: "Spending by category", span: "half", premium: true },
  { id: "byLabel", title: "Spending by label", span: "half", premium: true },
  { id: "monthCompare", title: "This month vs last", span: "full", premium: true },
];

export const tileMeta = (id: TileId): TileMeta => TILE_CATALOG.find((t) => t.id === id)!;

function TileCard({ title, action, children }: { title: string; action?: React.ReactNode; children: React.ReactNode }) {
  return (
    <section className="card" style={{ padding: 20, display: "grid", gap: 12, alignContent: "start" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <h2 style={{ margin: 0 }}>{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

/** Render the tile for a given id. */
export function TileView({ id }: { id: TileId }) {
  switch (id) {
    case "recent": return <RecentTile />;
    case "spending": return <SpendingTile />;
    case "budgets": return <BudgetsTile />;
    case "goals": return <GoalsTile />;
    case "cashflow": return <CashflowTile />;
    case "netTrend": return <NetTrendTile />;
    case "byCategory": return <ByCategoryTile />;
    case "byLabel": return <ByLabelTile />;
    case "monthCompare": return <MonthCompareTile />;
    default: return null;
  }
}

// ------------------------------- Tiles -------------------------------

function RecentTile() {
  const hidden = useAmountsHidden();
  const balances = useAccountBalances();
  const { data: recent = [] } = useQuery<Transaction & { labels: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels
     FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance' ORDER BY t.occurred_at DESC LIMIT 8`,
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL");
  const catName = (cid: string | null) => cats.find((c) => c.id === cid)?.name ?? "Uncategorised";
  const acctColor = (aid: string) => balances.find((b) => b.account.id === aid)?.account.color || colorForId(aid);
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));

  return (
    <TileCard title="Recent activity" action={<Link className="muted" style={{ fontSize: 13 }} href="/transactions">View all</Link>}>
      <div style={{ display: "grid", gap: 8 }}>
        {recent.map((t) => (
          <Link key={t.id} href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid var(--border)" }}>
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, background: acctColor(t.account_id) }} />
              <div>
                <div style={{ fontWeight: 550 }}>{t.labels || catName(t.category_id)}</div>
                <div className="muted" style={{ fontSize: 12 }}>{new Date(t.occurred_at).toLocaleDateString()} · {t.type}</div>
              </div>
            </div>
            <div style={{ fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
              {t.type === "expense" ? "−" : t.type === "income" ? "+" : ""}{fmt(money(t.amount, t.currency))}
            </div>
          </Link>
        ))}
        {recent.length === 0 && <p className="muted">No transactions yet.</p>}
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

  return (
    <TileCard title="Spending this month">
      {pieData.length ? (
        <ResponsiveContainer width="100%" height={220}>
          <PieChart>
            <Pie data={pieData} dataKey="value" nameKey="name" innerRadius={55} outerRadius={90} paddingAngle={2}>
              {pieData.map((_, i) => <Cell key={i} fill={PIE[i % PIE.length]} />)}
            </Pie>
            {!hidden && <Tooltip formatter={(v: number) => (v / 100).toFixed(2)} />}
          </PieChart>
        </ResponsiveContainer>
      ) : (
        <p className="muted">No spending recorded this month.</p>
      )}
      <div style={{ display: "grid", gap: 4 }}>
        {pieData.map((d, i) => (
          <div key={d.name} style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
            <span><span style={{ color: PIE[i % PIE.length] }}>●</span> {d.name}</span>
            <span className="muted">{hidden ? "••••" : toMajor(money(d.value, base)).toFixed(2)}</span>
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
  return (
    <TileCard title="Budgets" action={<Link className="muted" style={{ fontSize: 13 }} href="/budgets">Manage</Link>}>
      {budgets.length ? (
        <div style={{ display: "grid", gap: 12 }}>
          {budgets.map((b) => <BudgetMini key={b.id} budget={b} />)}
        </div>
      ) : (
        <p className="muted">No budgets yet. <Link href="/budgets">Create one</Link>.</p>
      )}
    </TileCard>
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
  const color = p.overLimit ? "var(--negative)" : p.atOrOverThreshold ? "var(--warning)" : "var(--positive)";
  const fmt = (m: Money) => (hidden ? "••••" : format(m, "en-US"));
  return (
    <div style={{ display: "grid", gap: 6 }}>
      <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
        <span style={{ fontWeight: 550 }}>{budget.name || budget.period}</span>
        <span className="muted">{fmt(spent)} / {fmt(limit)}</span>
      </div>
      <ProgressBar pct={p.pct} color={color} height={8} />
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
    <TileCard title="Goals" action={<Link className="muted" style={{ fontSize: 13 }} href="/goals">Manage</Link>}>
      {goals.length ? (
        <div style={{ display: "grid", gap: 12 }}>
          {goals.map((g) => {
            const s = saved(g.id);
            const pct = g.target_amount ? Math.min(100, (s / g.target_amount) * 100) : 0;
            return (
              <div key={g.id} style={{ display: "grid", gap: 6 }}>
                <div style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
                  <span style={{ fontWeight: 550 }}>{g.name}{g.is_emergency_fund ? " · EF" : ""}</span>
                  <span className="muted">{fmt(money(s, g.currency))} / {fmt(money(g.target_amount, g.currency))}</span>
                </div>
                <ProgressBar pct={pct} color={g.is_emergency_fund ? "var(--sage)" : "var(--accent)"} height={8} />
              </div>
            );
          })}
        </div>
      ) : (
        <p className="muted">No goals yet. <Link href="/goals">Add one</Link>.</p>
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

function CashflowTile() {
  const { cashflow } = useCashflow();
  return (
    <TileCard title="Cashflow">
      <ResponsiveContainer width="100%" height={260}>
        <BarChart data={cashflow}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
          <XAxis dataKey="month" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip /><Legend />
          <Bar dataKey="income" fill="#5f7a52" radius={[4, 4, 0, 0]} />
          <Bar dataKey="expense" fill="#b06a4f" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </TileCard>
  );
}

function NetTrendTile() {
  const { cashflow } = useCashflow();
  return (
    <TileCard title="Net cashflow trend">
      <ResponsiveContainer width="100%" height={240}>
        <LineChart data={cashflow}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
          <XAxis dataKey="month" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip />
          <Line type="monotone" dataKey="net" stroke="#3e4a38" strokeWidth={2.5} dot={{ r: 3 }} />
        </LineChart>
      </ResponsiveContainer>
    </TileCard>
  );
}

function ByCategoryTile() {
  const { data: byCat = [] } = useQuery<{ name: string | null; total: number }>(
    "SELECT c.name as name, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' GROUP BY t.category_id ORDER BY total DESC LIMIT 8",
  );
  const catData = byCat.map((r) => ({ name: r.name ?? "Uncategorised", value: major(r.total) }));
  return (
    <TileCard title="Spending by category">
      {catData.length ? (
        <ResponsiveContainer width="100%" height={260}>
          <BarChart layout="vertical" data={catData}>
            <XAxis type="number" tick={{ fontSize: 11 }} /><YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 11 }} /><Tooltip />
            <Bar dataKey="value" radius={[0, 4, 4, 0]}>{catData.map((_, i) => <Cell key={i} fill={PIE[i % PIE.length]} />)}</Bar>
          </BarChart>
        </ResponsiveContainer>
      ) : <p className="muted">No expenses recorded yet.</p>}
    </TileCard>
  );
}

function ByLabelTile() {
  const { data: labelRows = [] } = useQuery<{ name: string; total: number }>(
    `SELECT l.name AS name, SUM(t.amount) AS total
     FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id JOIN transactions t ON t.id = tl.transaction_id
     WHERE t.deleted_at IS NULL AND t.type='expense' GROUP BY l.id ORDER BY total DESC LIMIT 8`,
  );
  const labelData = labelRows.map((r) => ({ name: r.name, value: major(r.total) }));
  return (
    <TileCard title="Spending by label">
      {labelData.length ? (
        <ResponsiveContainer width="100%" height={260}>
          <BarChart layout="vertical" data={labelData}>
            <XAxis type="number" tick={{ fontSize: 11 }} /><YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 11 }} /><Tooltip />
            <Bar dataKey="value" radius={[0, 4, 4, 0]}>{labelData.map((_, i) => <Cell key={i} fill={PIE[(i + 3) % PIE.length]} />)}</Bar>
          </BarChart>
        </ResponsiveContainer>
      ) : <p className="muted">Add labels to transactions to see this.</p>}
    </TileCard>
  );
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
        <BarChart data={comparison}>
          <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
          <XAxis dataKey="period" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip /><Legend />
          <Bar dataKey="income" fill="#5f7a52" radius={[4, 4, 0, 0]} />
          <Bar dataKey="expense" fill="#b06a4f" radius={[4, 4, 0, 0]} />
        </BarChart>
      </ResponsiveContainer>
    </TileCard>
  );
}
