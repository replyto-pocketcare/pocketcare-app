"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useAmountsHidden } from "../../src/prefs";
import { colorForId } from "../../src/colors";

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
  const { data: accts = [] } = useQuery<{ id: string; name: string; type: string; color: string | null }>("SELECT id, name, type, color FROM accounts WHERE deleted_at IS NULL");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";
  const acct = (id: string) => accts.find((a) => a.id === id);
  const acctColor = (id: string) => acct(id)?.color || colorForId(id);
  const hidden = useAmountsHidden();

  const TYPE_CODE: Record<string, string> = {
    savings: "SV", current: "CU", credit_card: "CC", cash: "$", mutual_funds: "MF", stocks: "ST",
  };
  const typeLabel: Record<string, string> = {
    savings: "Savings", current: "Current", credit_card: "Credit Card", cash: "Cash", mutual_funds: "Mutual Funds", stocks: "Stocks",
  };

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
            <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
              {(() => {
                const a = acct(t.account_id);
                const color = acctColor(t.account_id);
                const code = a ? TYPE_CODE[a.type] ?? "•" : "•";
                return (
                  <span title={a ? `${a.name} · ${typeLabel[a.type] ?? a.type}` : ""}
                    style={{ minWidth: 26, height: 22, padding: "0 5px", borderRadius: 7, background: `${color}1f`, border: `1px solid ${color}`, color, fontSize: 10.5, fontWeight: 700, display: "inline-flex", alignItems: "center", justifyContent: "center", flexShrink: 0, cursor: "help", letterSpacing: "0.02em" }}>
                    {code}
                  </span>
                );
              })()}
              <div>
                <div style={{ fontWeight: 550 }}>{t.label || catName(t.category_id)}</div>
                <div className="muted" style={{ fontSize: 12 }}>{new Date(t.occurred_at).toLocaleString()} · {t.type}</div>
              </div>
            </div>
            <div style={{ fontWeight: 650, color: t.type === "income" ? "var(--positive)" : t.type === "expense" ? "var(--negative)" : "var(--text)" }}>
              {t.type === "expense" ? "−" : t.type === "income" ? "+" : "⇄ "}{hidden ? "••••" : format(money(t.amount, t.currency), "en-US")}
            </div>
          </Link>
        ))}
        {rows.length === 0 && <p className="muted" style={{ padding: 16 }}>No matching transactions.</p>}
      </div>
    </div>
  );
}
