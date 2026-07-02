"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useBaseCurrency, useTier } from "../../src/hooks";

export default function StatementsPage() {
  const tier = useTier();
  const base = useBaseCurrency();
  const today = new Date();
  const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().slice(0, 10);
  const [start, setStart] = useState(firstOfMonth);
  const [end, setEnd] = useState(today.toISOString().slice(0, 10));

  const startIso = new Date(start).toISOString();
  const endIso = new Date(new Date(end).getTime() + 86_400_000).toISOString();
  const { data: rows = [] } = useQuery<Transaction>(
    "SELECT * FROM transactions WHERE deleted_at IS NULL AND type != 'opening_balance' AND occurred_at >= ? AND occurred_at < ? ORDER BY occurred_at",
    [startIso, endIso],
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";

  const income = rows.filter((r) => r.type === "income").reduce((s, r) => s + r.amount, 0);
  const expense = rows.filter((r) => r.type === "expense").reduce((s, r) => s + r.amount, 0);

  if (tier !== "premium") {
    return (
      <div className="fade-up" style={{ display: "grid", gap: 16, maxWidth: 560 }}>
        <h1>Statements</h1>
        <div className="card" style={{ padding: 28, display: "grid", gap: 12, textAlign: "center" }}>
          <div style={{ fontSize: 40 }}>🧾</div>
          <h2>Statements are a Premium feature</h2>
          <p className="muted">Generate a clean statement for any period and save it as a PDF.</p>
          <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>Go Premium</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div className="no-print" style={{ display: "flex", gap: 12, alignItems: "center", flexWrap: "wrap" }}>
        <h1>Statements</h1>
        <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} style={{ maxWidth: 170 }} />
        <input className="input" type="date" value={end} onChange={(e) => setEnd(e.target.value)} style={{ maxWidth: 170 }} />
        <button className="btn" onClick={() => window.print()}>Print / Save PDF</button>
      </div>

      <div className="card" style={{ padding: 32 }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", marginBottom: 20 }}>
          <div>
            <h2 style={{ fontSize: 22 }}>PocketCare Statement</h2>
            <div className="muted">{new Date(start).toLocaleDateString()} – {new Date(end).toLocaleDateString()}</div>
          </div>
          <div style={{ textAlign: "right" }}>
            <div className="muted" style={{ fontSize: 12 }}>Net for period</div>
            <div style={{ fontSize: 24, fontWeight: 750, color: income - expense >= 0 ? "var(--positive)" : "var(--negative)" }}>
              {format(money(income - expense, base), "en-US")}
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: 24, marginBottom: 20 }}>
          <Summary label="Income" value={format(money(income, base), "en-US")} color="var(--positive)" />
          <Summary label="Expenses" value={format(money(expense, base), "en-US")} color="var(--negative)" />
          <Summary label="Transactions" value={String(rows.length)} />
        </div>

        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid var(--border)" }}>
              <th style={{ padding: "8px 6px" }}>Date</th><th>Description</th><th>Category</th><th style={{ textAlign: "right" }}>Amount</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} style={{ borderBottom: "1px solid var(--border)" }}>
                <td style={{ padding: "8px 6px" }}>{new Date(r.occurred_at).toLocaleDateString()}</td>
                <td>{r.label || r.type}</td>
                <td className="muted">{catName(r.category_id)}</td>
                <td style={{ textAlign: "right", color: r.type === "income" ? "var(--positive)" : r.type === "expense" ? "var(--negative)" : "var(--text)" }}>
                  {r.type === "expense" ? "−" : r.type === "income" ? "+" : ""}{format(money(r.amount, r.currency), "en-US")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        {rows.length === 0 && <p className="muted" style={{ marginTop: 16 }}>No transactions in this period.</p>}
      </div>
    </div>
  );
}

function Summary({ label, value, color }: { label: string; value: string; color?: string }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 12 }}>{label}</div>
      <div style={{ fontWeight: 700, fontSize: 18, color }}>{value}</div>
    </div>
  );
}
