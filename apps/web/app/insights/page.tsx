"use client";

import Link from "next/link";
import { useQuery } from "@powersync/react";
import {
  ResponsiveContainer, BarChart, Bar, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid, Legend, Cell,
} from "recharts";
import { useBaseCurrency, useTier } from "../../src/hooks";

const major = (m: number) => m / 100;
const PIE = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647"];

export default function InsightsPage() {
  const tier = useTier();
  const base = useBaseCurrency();

  // Cashflow by month (income vs expense).
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

  // By category (expenses, all time).
  const { data: byCat = [] } = useQuery<{ name: string | null; total: number }>(
    "SELECT c.name as name, SUM(t.amount) as total FROM transactions t LEFT JOIN categories c ON c.id = t.category_id WHERE t.deleted_at IS NULL AND t.type='expense' GROUP BY t.category_id ORDER BY total DESC LIMIT 8",
  );
  const catData = byCat.map((r) => ({ name: r.name ?? "Uncategorised", value: major(r.total) }));

  // By label.
  const { data: byLabel = [] } = useQuery<{ label: string | null; total: number }>(
    "SELECT label, SUM(amount) as total FROM transactions WHERE deleted_at IS NULL AND type='expense' AND label IS NOT NULL AND label != '' GROUP BY label ORDER BY total DESC LIMIT 8",
  );
  const labelData = byLabel.map((r) => ({ name: r.label ?? "—", value: major(r.total) }));

  // Period-to-period comparison (this vs last month).
  const now = new Date();
  const thisM = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
  const lastDate = new Date(now.getFullYear(), now.getMonth() - 1, 1);
  const lastM = `${lastDate.getFullYear()}-${String(lastDate.getMonth() + 1).padStart(2, "0")}`;
  const monthTotals = (ym: string, type: string) => major(byMonth.find((r) => r.ym === ym && r.type === type)?.total ?? 0);
  const comparison = [
    { period: "Last month", income: monthTotals(lastM, "income"), expense: monthTotals(lastM, "expense") },
    { period: "This month", income: monthTotals(thisM, "income"), expense: monthTotals(thisM, "expense") },
  ];

  if (tier !== "premium") {
    return (
      <div className="fade-up" style={{ display: "grid", gap: 16, maxWidth: 560 }}>
        <h1>Insights</h1>
        <div className="card" style={{ padding: 28, display: "grid", gap: 12, textAlign: "center" }}>
          <div style={{ fontSize: 40 }}>📈</div>
          <h2>Detailed insights are a Premium feature</h2>
          <p className="muted">Cashflow, category & label breakdowns, period comparisons and spending structure.</p>
          <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>Go Premium</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>Insights <span className="muted" style={{ fontSize: 13 }}>· {base}</span></h1>

      <Panel title="Cashflow">
        <ResponsiveContainer width="100%" height={280}>
          <BarChart data={cashflow}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
            <XAxis dataKey="month" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip /><Legend />
            <Bar dataKey="income" fill="#5f7a52" radius={[4, 4, 0, 0]} />
            <Bar dataKey="expense" fill="#b06a4f" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </Panel>

      <Panel title="Net cashflow trend">
        <ResponsiveContainer width="100%" height={240}>
          <LineChart data={cashflow}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
            <XAxis dataKey="month" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip />
            <Line type="monotone" dataKey="net" stroke="#3e4a38" strokeWidth={2.5} dot={{ r: 3 }} />
          </LineChart>
        </ResponsiveContainer>
      </Panel>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }}>
        <Panel title="By category">
          <ResponsiveContainer width="100%" height={260}>
            <BarChart layout="vertical" data={catData}>
              <XAxis type="number" tick={{ fontSize: 11 }} /><YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 11 }} /><Tooltip />
              <Bar dataKey="value" radius={[0, 4, 4, 0]}>{catData.map((_, i) => <Cell key={i} fill={PIE[i % PIE.length]} />)}</Bar>
            </BarChart>
          </ResponsiveContainer>
        </Panel>
        <Panel title="By label">
          {labelData.length ? (
            <ResponsiveContainer width="100%" height={260}>
              <BarChart layout="vertical" data={labelData}>
                <XAxis type="number" tick={{ fontSize: 11 }} /><YAxis type="category" dataKey="name" width={90} tick={{ fontSize: 11 }} /><Tooltip />
                <Bar dataKey="value" radius={[0, 4, 4, 0]}>{labelData.map((_, i) => <Cell key={i} fill={PIE[(i + 3) % PIE.length]} />)}</Bar>
              </BarChart>
            </ResponsiveContainer>
          ) : <p className="muted">Add labels to transactions to see this.</p>}
        </Panel>
      </div>

      <Panel title="This month vs last">
        <ResponsiveContainer width="100%" height={240}>
          <BarChart data={comparison}>
            <CartesianGrid strokeDasharray="3 3" stroke="var(--border)" />
            <XAxis dataKey="period" tick={{ fontSize: 12 }} /><YAxis tick={{ fontSize: 12 }} /><Tooltip /><Legend />
            <Bar dataKey="income" fill="#5f7a52" radius={[4, 4, 0, 0]} />
            <Bar dataKey="expense" fill="#b06a4f" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      </Panel>
    </div>
  );
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <section className="card" style={{ padding: 20 }}>
      <h2 style={{ marginBottom: 12 }}>{title}</h2>
      {children}
    </section>
  );
}
