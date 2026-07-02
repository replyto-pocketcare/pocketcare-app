"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";

const TYPES = ["all", "income", "expense", "transfer"] as const;

export default function TransactionsPage() {
  const [q, setQ] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");

  const like = `%${q}%`;
  const { data: rows = [] } = useQuery<Transaction>(
    `SELECT * FROM transactions
     WHERE deleted_at IS NULL AND type != 'opening_balance'
       AND (? = '' OR label LIKE ? OR note LIKE ?)
       AND (? = 'all' OR type = ?)
     ORDER BY occurred_at DESC LIMIT 200`,
    [q, like, like, type, type],
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Transactions</h1>
        <Link href="/transactions/new" className="btn">＋ Add</Link>
      </div>

      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <input className="input" placeholder="Search label or note…" value={q} onChange={(e) => setQ(e.target.value)} style={{ maxWidth: 340 }} />
        <div style={{ display: "flex", gap: 6 }}>
          {TYPES.map((t) => (
            <button key={t} className="chip" data-active={t === type} style={{ textTransform: "capitalize" }} onClick={() => setType(t)}>{t}</button>
          ))}
        </div>
      </div>

      <div className="card" style={{ padding: 8 }}>
        {rows.map((t) => (
          <Link key={t.id} href={`/transactions/${t.id}/edit`} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: "12px 14px", borderBottom: "1px solid var(--border)" }}>
            <div>
              <div style={{ fontWeight: 550 }}>{t.label || catName(t.category_id)}</div>
              <div className="muted" style={{ fontSize: 12 }}>{new Date(t.occurred_at).toLocaleString()} · {t.type}</div>
            </div>
            <div style={{ fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
              {t.type === "expense" ? "−" : t.type === "income" ? "+" : "⇄ "}{format(money(t.amount, t.currency), "en-US")}
            </div>
          </Link>
        ))}
        {rows.length === 0 && <p className="muted" style={{ padding: 16 }}>No matching transactions.</p>}
      </div>
    </div>
  );
}
