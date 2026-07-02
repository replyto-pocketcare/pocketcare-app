"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { fromMajor, toMajor, money, format } from "@pocketcare/money";
import type { Account, Transaction } from "@pocketcare/types";
import type { TransactionAudit } from "@pocketcare/data";
import { getRepositories } from "../../../../src/powersync";

type TxType = "expense" | "income" | "transfer" | "adjustment";

export default function EditTransactionPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: rows = [] } = useQuery<Transaction>("SELECT * FROM transactions WHERE id = ?", [id]);
  const tx = rows[0];
  const { data: accounts = [] } = useQuery<Account>("SELECT * FROM accounts WHERE deleted_at IS NULL");
  const { data: cats = [] } = useQuery<{ id: string; name: string; kind: string }>("SELECT id, name, kind FROM categories WHERE deleted_at IS NULL ORDER BY name");
  const { data: labels = [] } = useQuery<{ id: string; name: string; color: string | null }>("SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name");
  const { data: audit = [] } = useQuery<TransactionAudit>("SELECT id, transaction_id, action, changes, created_at FROM transaction_audit WHERE transaction_id = ? ORDER BY created_at DESC", [id]);

  const [type, setType] = useState<TxType>("expense");
  const [accountId, setAccountId] = useState("");
  const [amount, setAmount] = useState("");
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [label, setLabel] = useState("");
  const [note, setNote] = useState("");
  const [date, setDate] = useState("");
  const [ready, setReady] = useState(false);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (tx && !ready) {
      setType(tx.type as TxType);
      setAccountId(tx.account_id);
      setAmount(String(toMajor(money(tx.amount, tx.currency))));
      setCategoryId(tx.category_id);
      setLabel(tx.label ?? "");
      setNote(tx.note ?? "");
      setDate(tx.occurred_at.slice(0, 10));
      setReady(true);
    }
  }, [tx, ready]);

  if (!tx) return <p className="muted">Loading…</p>;
  const currency = tx.currency;
  const relevantCats = cats.filter((c) => (type === "income" ? c.kind === "income" : c.kind === "expense"));

  async function save() {
    setSaving(true);
    try {
      await getRepositories().transactions.update(id, {
        type: type as Transaction["type"],
        account_id: accountId,
        amount: fromMajor(Number(amount) || 0, currency),
        category_id: type === "transfer" ? null : categoryId,
        label: label.trim() || null,
        note: note.trim() || null,
        occurred_at: new Date(date).toISOString(),
      });
      router.push("/transactions");
    } finally { setSaving(false); }
  }

  return (
    <div style={{ maxWidth: 620, display: "grid", gap: 14 }} className="fade-up">
      <h1>Edit transaction</h1>

      <div style={{ display: "flex", gap: 8 }}>
        {(["expense", "income", "transfer"] as TxType[]).map((tp) => (
          <button key={tp} className="chip" data-active={tp === type} style={{ flex: 1, textTransform: "capitalize" }} onClick={() => setType(tp)}>{tp}</button>
        ))}
      </div>

      <Field label="Account">
        <div style={chips}>
          {accounts.map((a) => <button key={a.id} className="chip" data-active={a.id === accountId} onClick={() => setAccountId(a.id)}>{a.name}</button>)}
        </div>
      </Field>

      <Field label={`Amount (${currency})`}>
        <input className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
      </Field>

      {type !== "transfer" && (
        <Field label="Category">
          <div style={chips}>
            {relevantCats.map((c) => <button key={c.id} className="chip" data-active={c.id === categoryId} onClick={() => setCategoryId(c.id)}>{c.name}</button>)}
          </div>
        </Field>
      )}

      <Field label="Label">
        {labels.length > 0 && (
          <div style={{ ...chips, marginBottom: 8 }}>
            {labels.map((l) => {
              const active = label === l.name; const c = l.color || "#b06a4f";
              return <button key={l.id} onClick={() => setLabel(active ? "" : l.name)} style={{ padding: "6px 12px", borderRadius: 999, cursor: "pointer", border: `1px solid ${c}`, background: active ? c : `${c}22`, color: active ? "#fff" : "var(--text)" }}>{l.name}</button>;
            })}
          </div>
        )}
        <input className="input" value={label} onChange={(e) => setLabel(e.target.value)} placeholder="Label" />
      </Field>

      <Field label="Note"><input className="input" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional note" /></Field>
      <Field label="Date"><input className="input" type="date" value={date} onChange={(e) => setDate(e.target.value)} /></Field>

      <div style={{ display: "flex", gap: 10 }}>
        <button className="btn" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save changes"}</button>
        <button className="btn ghost" onClick={() => router.push("/transactions")}>Cancel</button>
      </div>

      {/* Audit trail */}
      {audit.length > 0 && (
        <section className="card" style={{ padding: 20, marginTop: 8 }}>
          <h2 style={{ marginBottom: 10 }}>Edit history</h2>
          <div style={{ display: "grid", gap: 10 }}>
            {audit.map((a) => (
              <div key={a.id} style={{ fontSize: 13, borderBottom: "1px solid var(--border)", paddingBottom: 8 }}>
                <div className="muted" style={{ fontSize: 12 }}>{new Date(a.created_at).toLocaleString()} · {a.action}</div>
                <AuditChanges changes={a.changes} currency={currency} />
              </div>
            ))}
          </div>
        </section>
      )}
    </div>
  );
}

function AuditChanges({ changes, currency }: { changes: string | null; currency: string }) {
  if (!changes) return null;
  let parsed: Record<string, { from: unknown; to: unknown }> = {};
  try { parsed = JSON.parse(changes); } catch { return null; }
  const fmt = (field: string, v: unknown) =>
    field === "amount" || field === "to_amount" ? format(money(Number(v) || 0, currency), "en-US") : String(v ?? "—");
  return (
    <div style={{ display: "grid", gap: 2, marginTop: 4 }}>
      {Object.entries(parsed).map(([field, { from, to }]) => (
        <div key={field}><strong>{field}</strong>: <span className="muted">{fmt(field, from)}</span> → {fmt(field, to)}</div>
      ))}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label style={{ display: "grid", gap: 8 }}><span className="muted" style={{ fontSize: 13 }}>{label}</span>{children}</label>;
}
const chips: React.CSSProperties = { display: "flex", flexWrap: "wrap", gap: 8 };
