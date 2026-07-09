"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, format } from "@pocketcare/money";
import type { Transaction } from "@pocketcare/types";
import { useBaseCurrency } from "../../src/hooks";
import { useEntitlement } from "../../src/entitlement";
import { LockIcon } from "../../src/ui/icons";

export default function StatementsPage() {
  const { t } = useTranslation();
  const { isPaid } = useEntitlement();
  const base = useBaseCurrency();
  const today = new Date();
  const firstOfMonth = new Date(today.getFullYear(), today.getMonth(), 1).toISOString().slice(0, 10);
  const [start, setStart] = useState(firstOfMonth);
  const [end, setEnd] = useState(today.toISOString().slice(0, 10));

  const startIso = new Date(start).toISOString();
  const endIso = new Date(new Date(end).getTime() + 86_400_000).toISOString();
  const { data: rows = [] } = useQuery<Transaction & { labels: string | null }>(
    `SELECT t.*,
       (SELECT GROUP_CONCAT(l.name, ', ') FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = t.id) AS labels
     FROM transactions t WHERE t.deleted_at IS NULL AND t.type != 'opening_balance' AND t.occurred_at >= ? AND t.occurred_at < ? ORDER BY t.occurred_at`,
    [startIso, endIso],
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string }>("SELECT id, name FROM categories");
  const catName = (id: string | null) => cats.find((c) => c.id === id)?.name ?? "Uncategorised";

  const income = rows.filter((r) => r.type === "income").reduce((s, r) => s + r.amount, 0);
  const expense = rows.filter((r) => r.type === "expense").reduce((s, r) => s + r.amount, 0);

  if (!isPaid) {
    return (
      <div className="fade-up" style={{ display: "grid", gap: 16, maxWidth: 560 }}>
        <h1>{t("pages.statements", "Statements")}</h1>
        <div className="card" style={{ padding: 28, display: "grid", gap: 12, textAlign: "center" }}>
          <div style={{ display: "flex", justifyContent: "center", color: "var(--text-2)" }}><LockIcon size={30} /></div>
          <h2>Statements are a Premium feature</h2>
          <p className="muted">Generate a clean statement for any period and save it as a PDF.</p>
          <Link href="/settings" className="btn" style={{ justifySelf: "center" }}>Go Premium</Link>
        </div>
      </div>
    );
  }

  return (
    <div style={{ display: "grid", gap: 20, minWidth: 0, maxWidth: "100%", overflowX: "hidden" }} className="fade-up">
      <div className="no-print" style={{ display: "grid", gap: 14 }}>
        <div style={{ display: "flex", gap: 12, alignItems: "center", justifyContent: "space-between", flexWrap: "wrap" }}>
          <h1>{t("pages.statements", "Statements")}</h1>
          <button className="btn" onClick={() => window.print()}>Print / Save PDF</button>
        </div>
        <div style={{ display: "flex", gap: 12, flexWrap: "wrap" }}>
          <label style={{ display: "grid", gap: 4, flex: "1 1 220px", minWidth: 0 }}>
            <span className="muted" style={{ fontSize: 12 }}>From date</span>
            <input className="input" type="date" value={start} onChange={(e) => { setStart(e.target.value); if (e.target.value > end) setEnd(e.target.value); }} />
          </label>
          <label style={{ display: "grid", gap: 4, flex: "1 1 220px", minWidth: 0 }}>
            <span className="muted" style={{ fontSize: 12 }}>To date</span>
            <input className="input" type="date" value={end} min={start || undefined} onChange={(e) => setEnd(e.target.value)} />
          </label>
        </div>
      </div>

      <div className="card statement-card" style={{ padding: 24, minWidth: 0, maxWidth: "100%", overflowX: "hidden", boxSizing: "border-box" }}>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 16, flexWrap: "wrap", marginBottom: 20 }}>
          <div style={{ minWidth: 0 }}>
            <h2 style={{ fontSize: 22 }}>PocketCare Statement</h2>
            <div className="muted">{new Date(start).toLocaleDateString()} – {new Date(end).toLocaleDateString()}</div>
          </div>
          <div style={{ textAlign: "right", minWidth: 0 }}>
            <div className="muted" style={{ fontSize: 12 }}>Net for period</div>
            <div style={{ fontSize: 22, fontWeight: 750, whiteSpace: "nowrap", color: income - expense >= 0 ? "var(--positive)" : "var(--negative)" }}>
              {format(money(income - expense, base), "en-US")}
            </div>
          </div>
        </div>

        <div style={{ display: "flex", gap: 24, marginBottom: 20, flexWrap: "wrap" }}>
          <Summary label="Income" value={format(money(income, base), "en-US")} color="var(--positive)" />
          <Summary label="Expenses" value={format(money(expense, base), "en-US")} color="var(--negative)" />
          <Summary label="Transactions" value={String(rows.length)} />
        </div>

        <div style={{ overflowX: "auto" }}>
        <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 14, minWidth: 380 }}>
          <thead>
            <tr style={{ textAlign: "left", borderBottom: "2px solid var(--border)" }}>
              <th style={{ padding: "8px 6px" }}>Date</th><th>Description</th><th>Category</th><th style={{ textAlign: "right" }}>Amount</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((r) => (
              <tr key={r.id} style={{ borderBottom: "1px solid var(--border)" }}>
                <td style={{ padding: "8px 6px" }}>{new Date(r.occurred_at).toLocaleDateString()}</td>
                <td>{r.labels || r.description || r.type}</td>
                <td className="muted">{catName(r.category_id)}</td>
                <td style={{ textAlign: "right", color: r.type === "income" ? "var(--positive)" : r.type === "expense" ? "var(--negative)" : "var(--text)" }}>
                  {r.type === "expense" ? "−" : r.type === "income" ? "+" : ""}{format(money(r.amount, r.currency), "en-US")}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
        </div>
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
