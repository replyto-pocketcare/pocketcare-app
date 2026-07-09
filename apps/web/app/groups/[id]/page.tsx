"use client";

import { useParams } from "next/navigation";
import Link from "next/link";
import { money } from "@pocketcare/money";
import { useBaseCurrency } from "../../../src/hooks";
import { useMoneyFmt } from "../../../src/ui/Money";
import { useGroup, useGroupExpenses, useGroupBalances, useContacts } from "../../../src/splits/hooks";

export default function GroupDetailPage() {
  const params = useParams<{ id: string }>();
  const id = params.id;
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const group = useGroup(id);
  const expenses = useGroupExpenses(id);
  const balances = useGroupBalances(id);
  const contacts = useContacts();

  const name = (cid: string) => contacts.find((c) => c.id === cid)?.name ?? "?";
  const total = expenses.reduce((s, e) => s + e.total_amount, 0);
  const owed = balances.reduce((s, b) => s + Math.max(0, b.net), 0);
  const owe = balances.reduce((s, b) => s + Math.max(0, -b.net), 0);

  if (!group) {
    return <div className="fade-up"><p className="muted">Group not found. <Link href="/groups">Back to groups</Link></p></div>;
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div>
        <Link href="/groups" className="muted" style={{ fontSize: 13 }}>← Groups</Link>
        <h1 style={{ margin: "6px 0 0" }}>{group.name} <span className="muted" style={{ fontSize: 14 }}>· {group.kind}</span></h1>
        {group.start_date && <div className="muted" style={{ fontSize: 13 }}>{group.start_date}{group.end_date ? ` → ${group.end_date}` : ""}</div>}
      </div>

      <section className="card" style={{ padding: 20, display: "flex", gap: 24, flexWrap: "wrap" }}>
        <div><div className="muted" style={{ fontSize: 13 }}>Total spent</div><div style={{ fontSize: 26, fontWeight: 750 }}>{fmt(money(total, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>You’re owed</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--positive)" }}>{fmt(money(owed, base))}</div></div>
        <div><div className="muted" style={{ fontSize: 13 }}>You owe</div><div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(owe, base))}</div></div>
      </section>

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>Balances</h2>
        {balances.filter((b) => b.net !== 0).length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>All settled in this {group.kind}.</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {balances.filter((b) => b.net !== 0).map((b) => (
              <div key={b.contactId} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14 }}>
                <span>{name(b.contactId)}</span>
                <span style={{ color: b.net > 0 ? "var(--positive)" : "var(--negative)" }}>{b.net > 0 ? `owes you ${fmt(money(b.net, base))}` : `you owe ${fmt(money(-b.net, base))}`}</span>
              </div>
            ))}
          </div>
        )}
      </section>

      <section style={{ display: "grid", gap: 8 }}>
        <h2 style={{ margin: 0 }}>Expenses</h2>
        {expenses.length === 0 ? (
          <p className="muted" style={{ fontSize: 13 }}>No expenses yet. Add one from <Link href="/transactions/new">Add transaction</Link> and choose this {group.kind}.</p>
        ) : (
          <div className="card" style={{ padding: 8 }}>
            {expenses.map((e) => (
              <div key={e.id} style={{ display: "flex", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid var(--border)", fontSize: 14, gap: 8 }}>
                <span style={{ minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                  {e.description || "Expense"} <span className="muted" style={{ fontSize: 12 }}>· {new Date(e.occurred_at).toLocaleDateString()}</span>
                </span>
                <span style={{ flexShrink: 0, fontWeight: 600 }}>{fmt(money(e.total_amount, base))}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
