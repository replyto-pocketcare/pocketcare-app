"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format, toMajor, type Money } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { useNetWorth, useAccountBalances } from "../src/hooks";
import { useAmountsHidden, setAmountsHidden } from "../src/prefs";
import { colorForId } from "../src/colors";
import { getDb } from "../src/powersync";

const PIE = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#4f46e5", "#7c7264"];

export default function Dashboard() {
  const { total, available, base } = useNetWorth();
  const balances = useAccountBalances();
  const hidden = useAmountsHidden();
  const [showAvailable, setShowAvailable] = useState(false);
  const net = showAvailable ? available : total;

  const fmt = (m: Money) => (hidden ? "••••••" : format(m, "en-US"));

  const { data: recent = [] } = useQuery<Transaction>(
    "SELECT * FROM transactions WHERE deleted_at IS NULL AND type != 'opening_balance' ORDER BY occurred_at DESC LIMIT 8",
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories WHERE deleted_at IS NULL");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";
  const acctColor = (id: string) => balances.find((b) => b.account.id === id)?.account.color || colorForId(id);

  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
  const { data: spend = [] } = useQuery<{ category_id: string | null; total: number }>(
    `SELECT category_id, SUM(amount) as total FROM transactions
     WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= ? GROUP BY category_id ORDER BY total DESC`,
    [monthStart],
  );
  const pieData = spend.slice(0, 7).map((s) => ({ name: catName(s.category_id), value: s.total }));

  async function toggleNw(id: string, included: boolean) {
    await getDb()?.execute("UPDATE accounts SET include_in_net_worth = ?, updated_at = ? WHERE id = ?", [included ? 0 : 1, new Date().toISOString(), id]);
  }

  if (balances.length === 0) {
    return (
      <div className="fade-up" style={{ minHeight: "70vh", display: "grid", placeItems: "center" }}>
        <div className="card" style={{ maxWidth: 460, padding: 36, textAlign: "center", display: "grid", gap: 14, background: "radial-gradient(120% 120% at 50% 0%, var(--accent-ghost), var(--surface) 70%)" }}>
          <div style={{ fontSize: 48 }}>🌱</div>
          <h1 style={{ fontSize: 26 }}>Welcome to PocketCare</h1>
          <p className="muted" style={{ lineHeight: 1.6 }}>Let’s start by adding your first account — a bank, cash, a card, or investments.</p>
          <Link href="/accounts/new" className="btn" style={{ justifySelf: "center", padding: "12px 20px" }}>＋ Add your first account</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 24 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end", gap: 12 }}>
        <h1>Dashboard</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <button className="chip" onClick={() => setAmountsHidden(!hidden)} title={hidden ? "Show amounts" : "Hide amounts"}>
            {hidden ? "👁 Show" : "🙈 Hide"}
          </button>
          <Link href="/accounts/new" className="btn ghost">＋ Account</Link>
        </div>
      </div>

      {/* Net worth hero */}
      <section className="card" style={{ padding: 28, display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>{showAvailable ? "Available net worth" : "Net worth"}</div>
          <div style={{ fontSize: 44, fontWeight: 750, letterSpacing: "-0.02em", color: "var(--forest)" }}>{fmt(net)}</div>
          <div className="muted" style={{ fontSize: 13 }}>Base currency {base}</div>
        </div>
        <button className="chip" data-active={showAvailable} onClick={() => setShowAvailable((v) => !v)}>
          {showAvailable ? "Excluding blocked" : "Including blocked"}
        </button>
      </section>

      {/* Accounts */}
      <section style={{ display: "grid", gap: 12 }}>
        <h2>Accounts</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(230px, 1fr))", gap: 12 }}>
          {balances.map(({ account, balance }) => {
            const included = account.include_in_net_worth !== 0;
            const color = account.color || colorForId(account.id);
            return (
              <div key={account.id} className="card" style={{ padding: 0, overflow: "hidden", display: "flex" }}>
                <div style={{ width: 5, background: color }} />
                <div style={{ padding: 16, display: "grid", gap: 3, flex: 1 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                    <span className="muted" style={{ fontSize: 12, textTransform: "capitalize" }}>{account.type.replace("_", " ")}</span>
                    <button onClick={() => toggleNw(account.id, included)} title={included ? "In net worth — click to exclude" : "Excluded — click to include"}
                      style={{ background: "transparent", border: "none", cursor: "pointer", fontSize: 14, opacity: included ? 1 : 0.4 }}>
                      {included ? "👁" : "🙈"}
                    </button>
                  </div>
                  <span style={{ fontWeight: 600 }}>{account.name}</span>
                  <span style={{ fontSize: 20, fontWeight: 700 }}>{fmt(balance)}</span>
                </div>
              </div>
            );
          })}
        </div>
      </section>

      <div style={{ display: "grid", gridTemplateColumns: "1.3fr 1fr", gap: 20 }} className="dash-cols">
        {/* Recent */}
        <section className="card" style={{ padding: 20 }}>
          <h2 style={{ marginBottom: 12 }}>Recent activity</h2>
          <div style={{ display: "grid", gap: 8 }}>
            {recent.map((t) => (
              <Link key={t.id} href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid var(--border)" }}>
                <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                  <span style={{ width: 8, height: 8, borderRadius: 999, background: acctColor(t.account_id) }} />
                  <div>
                    <div style={{ fontWeight: 550 }}>{t.label || catName(t.category_id)}</div>
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
        </section>

        {/* Spending by category */}
        <section className="card" style={{ padding: 20 }}>
          <h2 style={{ marginBottom: 12 }}>Spending this month</h2>
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
          <div style={{ display: "grid", gap: 4, marginTop: 8 }}>
            {pieData.map((d, i) => (
              <div key={d.name} style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
                <span><span style={{ color: PIE[i % PIE.length] }}>●</span> {d.name}</span>
                <span className="muted">{hidden ? "••••" : toMajor(money(d.value, base)).toFixed(2)}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
