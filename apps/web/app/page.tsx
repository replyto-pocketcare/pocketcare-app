"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format, toMajor } from "@pocketcare/money";
import type { Account, Transaction } from "@pocketcare/types";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip } from "recharts";
import { useNetWorth, useAccountBalances } from "../src/hooks";

const PIE = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264"];

export default function Dashboard() {
  const { total, available, base } = useNetWorth();
  const balances = useAccountBalances();
  const [showAvailable, setShowAvailable] = useState(false);
  const net = showAvailable ? available : total;

  const { data: recent = [] } = useQuery<Transaction>(
    "SELECT * FROM transactions WHERE deleted_at IS NULL AND type != 'opening_balance' ORDER BY occurred_at DESC LIMIT 8",
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>(
    "SELECT id, name FROM categories WHERE deleted_at IS NULL",
  );
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";

  // Spending by category (expenses, this month).
  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
  const { data: spend = [] } = useQuery<{ category_id: string | null; total: number }>(
    `SELECT category_id, SUM(amount) as total FROM transactions
     WHERE deleted_at IS NULL AND type='expense' AND occurred_at >= ? GROUP BY category_id ORDER BY total DESC`,
    [monthStart],
  );
  const pieData = spend.slice(0, 7).map((s) => ({ name: catName(s.category_id), value: s.total }));

  // First-run: no accounts yet — welcome the user and get them started.
  if (balances.length === 0) {
    return (
      <div className="fade-up" style={{ minHeight: "70vh", display: "grid", placeItems: "center" }}>
        <div className="card" style={{ maxWidth: 460, padding: 36, textAlign: "center", display: "grid", gap: 14, background: "radial-gradient(120% 120% at 50% 0%, var(--accent-ghost), var(--surface) 70%)" }}>
          <div style={{ fontSize: 48 }}>🌱</div>
          <h1 style={{ fontSize: 26 }}>Welcome to PocketCare</h1>
          <p className="muted" style={{ lineHeight: 1.6 }}>
            Let’s start by adding your first account — a bank, cash, a card, or investments.
            Everything else grows from here.
          </p>
          <Link href="/accounts/new" className="btn" style={{ justifySelf: "center", padding: "12px 20px" }}>＋ Add your first account</Link>
          <span className="muted" style={{ fontSize: 12 }}>You can add as many as you like, in any currency.</span>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 24 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-end" }}>
        <h1>Dashboard</h1>
        <Link href="/accounts/new" className="btn ghost">＋ Account</Link>
      </div>

      {/* Net worth hero */}
      <section className="card" style={{ padding: 28, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>{showAvailable ? "Available net worth" : "Net worth"}</div>
          <div style={{ fontSize: 44, fontWeight: 750, letterSpacing: "-0.02em", color: "var(--forest)" }}>
            {format(net, "en-US")}
          </div>
          <div className="muted" style={{ fontSize: 13 }}>Base currency {base}</div>
        </div>
        <button className="chip" data-active={showAvailable} onClick={() => setShowAvailable((v) => !v)}>
          {showAvailable ? "Excluding blocked" : "Including blocked"}
        </button>
      </section>

      {/* Accounts */}
      <section style={{ display: "grid", gap: 12 }}>
        <h2>Accounts</h2>
        <div style={{ display: "grid", gridTemplateColumns: "repeat(auto-fill, minmax(220px, 1fr))", gap: 12 }}>
          {balances.map(({ account, balance }) => (
            <Link key={account.id} href="/accounts" className="card" style={{ padding: 18, display: "grid", gap: 4 }}>
              <span className="muted" style={{ fontSize: 12, textTransform: "capitalize" }}>{account.type.replace("_", " ")}</span>
              <span style={{ fontWeight: 600 }}>{account.name}</span>
              <span style={{ fontSize: 20, fontWeight: 700 }}>{format(balance, "en-US")}</span>
            </Link>
          ))}
          {balances.length === 0 && <p className="muted">No accounts yet — add one to get started.</p>}
        </div>
      </section>

      <div style={{ display: "grid", gridTemplateColumns: "1.3fr 1fr", gap: 20 }}>
        {/* Recent */}
        <section className="card" style={{ padding: 20 }}>
          <h2 style={{ marginBottom: 12 }}>Recent activity</h2>
          <div style={{ display: "grid", gap: 8 }}>
            {recent.map((t) => (
              <div key={t.id} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: "1px solid var(--border)" }}>
                <div>
                  <div style={{ fontWeight: 550 }}>{t.label || catName(t.category_id)}</div>
                  <div className="muted" style={{ fontSize: 12 }}>{new Date(t.occurred_at).toLocaleDateString()} · {t.type}</div>
                </div>
                <div style={{ fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
                  {t.type === "expense" ? "−" : t.type === "income" ? "+" : ""}{format(money(t.amount, t.currency), "en-US")}
                </div>
              </div>
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
                <Tooltip formatter={(v: number) => (v / 100).toFixed(2)} />
              </PieChart>
            </ResponsiveContainer>
          ) : (
            <p className="muted">No spending recorded this month.</p>
          )}
          <div style={{ display: "grid", gap: 4, marginTop: 8 }}>
            {pieData.map((d, i) => (
              <div key={d.name} style={{ display: "flex", justifyContent: "space-between", fontSize: 13 }}>
                <span><span style={{ color: PIE[i % PIE.length] }}>●</span> {d.name}</span>
                <span className="muted">{toMajor(money(d.value, base)).toFixed(2)}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
