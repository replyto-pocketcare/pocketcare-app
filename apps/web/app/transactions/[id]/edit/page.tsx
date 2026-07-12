"use client";

import { useEffect, useState, useMemo } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { fromMajor, toMajor, money, format, sum, type Money } from "@pocketcare/money";
import type { Account, Transaction } from "@pocketcare/types";
import type { TransactionAudit } from "@pocketcare/data";
import { getRepositories } from "../../../../src/powersync";
import { LabelPicker } from "../../../../src/ui/LabelPicker";
import { SearchSelect } from "../../../../src/ui/SearchSelect";
import { AccountBadge } from "../../../../src/ui/AccountBadge";
import { useEntitlement } from "../../../../src/entitlement";
import { useLearnCategory } from "../../../../src/categorize/hooks";
import { encryptForWrite } from "../../../../src/crypto/fields";
import { decryptField, isEncrypted } from "@pocketcare/crypto";
import { getDek } from "../../../../src/crypto/session";

type TxType = "expense" | "income" | "transfer" | "adjustment";

export default function EditTransactionPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: rows = [] } = useQuery<Transaction>("SELECT * FROM transactions WHERE id = ?", [id]);
  const tx = rows[0];
  const { data: accounts = [] } = useQuery<Account>("SELECT * FROM accounts WHERE deleted_at IS NULL AND IFNULL(kind,'real') = 'real'");
  const { data: cats = [] } = useQuery<{ id: string; name: string; kind: string; parent_id: string | null }>("SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name");
  const { data: labels = [] } = useQuery<{ id: string; name: string; color: string | null }>("SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name");
  const { data: txLabels = [], isLoading: txLabelsLoading } = useQuery<{ name: string }>(
    "SELECT l.name FROM transaction_labels tl JOIN labels l ON l.id = tl.label_id WHERE tl.transaction_id = ? ORDER BY l.name",
    [id],
  );
  const { data: payMethodMap = [] } = useQuery<{ id: string; label: string; account_type_id: string }>(
    `SELECT pm.id, pm.label, m.account_type_id
     FROM account_type_payment_methods m JOIN payment_methods pm ON pm.id = m.payment_method_id
     ORDER BY pm.sort`,
  );
  const { data: audit = [] } = useQuery<TransactionAudit>("SELECT id, transaction_id, action, changes, created_at FROM transaction_audit WHERE transaction_id = ? ORDER BY created_at DESC", [id]);
  const { data: txItems = [], isLoading: txItemsLoading } = useQuery<{ id: string; description: string; amount: number }>(
    "SELECT id, description, amount FROM transaction_items WHERE transaction_id = ? AND deleted_at IS NULL",
    [id],
  );

  const [type, setType] = useState<TxType>("expense");
  const [accountId, setAccountId] = useState("");
  const [amount, setAmount] = useState(""); // Used only for transfers
  const [items, setItems] = useState<{ id: string; description: string; value: string }[]>([]);
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [selectedLabels, setSelectedLabels] = useState<string[]>([]);
  const [paymentMethod, setPaymentMethod] = useState("");
  const [note, setNote] = useState("");
  const [date, setDate] = useState("");
  const [ready, setReady] = useState(false);
  const [labelsReady, setLabelsReady] = useState(false);
  const [itemsReady, setItemsReady] = useState(false);
  const [saving, setSaving] = useState(false);
  const [saveErr, setSaveErr] = useState<string | null>(null);

  const { isPaid } = useEntitlement();
  const learnCategory = useLearnCategory();
  const [originalCategoryId, setOriginalCategoryId] = useState<string | null>(null);

  useEffect(() => {
    if (tx && !ready) {
      setType(tx.type as TxType);
      setAccountId(tx.account_id);
      setAmount(String(toMajor(money(tx.amount, tx.currency))));
      setCategoryId(tx.category_id);
      setOriginalCategoryId(tx.category_id);
      setPaymentMethod(tx.payment_method ?? "");
      // Decrypt the note for editing if it's an encrypted envelope and unlocked.
      const rawNote = tx.note ?? "";
      if (isEncrypted(rawNote) && getDek()) {
        void decryptField(rawNote, getDek()!).then((p) => setNote(p)).catch(() => setNote(""));
      } else {
        setNote(rawNote);
      }
      setDate(new Date(tx.occurred_at).toLocaleString("sv-SE", { timeZoneName: "short" }).substring(0, 16));
      setReady(true);
    }
  }, [tx, ready]);

  useEffect(() => {
    if (tx && !labelsReady && !txLabelsLoading) {
      setSelectedLabels(txLabels.map((r) => r.name));
      setLabelsReady(true);
    }
  }, [tx, txLabels, txLabelsLoading, labelsReady]);

  useEffect(() => {
    if (tx && !itemsReady && !txItemsLoading) {
      if (txItems.length > 0) {
        setItems(txItems.map(it => ({ id: it.id, description: it.description, value: String(toMajor(money(it.amount, tx.currency))) })));
      } else {
        setItems([{ id: `new_${Date.now()}`, description: tx.description ?? "", value: String(toMajor(money(tx.amount, tx.currency))) }]);
      }
      setItemsReady(true);
    }
  }, [tx, txItems, txItemsLoading, itemsReady]);

  if (!tx) return <p className="muted">Loading…</p>;
  const currency = tx.currency;
  
  const itemMoneys = items.map((it) => fromMajor(Number.parseFloat(it.value) || 0, currency));
  const total = sum(itemMoneys, currency);

  const relevantCats = cats.filter((c) => (type === "income" ? c.kind === "income" : c.kind === "expense"));
  const categoryOptions = (() => {
    const opts: { value: string; label: string; search: string }[] = [];
    for (const p of relevantCats.filter((c) => !c.parent_id)) {
      opts.push({ value: p.id, label: p.name, search: p.name });
      for (const ch of relevantCats.filter((c) => c.parent_id === p.id)) {
        opts.push({ value: ch.id, label: `${p.name} › ${ch.name}`, search: `${p.name} ${ch.name}` });
      }
    }
    return opts;
  })();
  const activeAccountType = accounts.find((a) => a.id === accountId)?.type;
  const payMethods = payMethodMap.filter((m) => m.account_type_id === activeAccountType);

  const updateItem = (id: string, patch: Partial<(typeof items)[number]>) =>
    setItems((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it)));

  async function save() {
    setSaving(true);
    setSaveErr(null);
    try {
      let finalAmount = fromMajor(Number(amount) || 0, currency);
      let payloadItems: { id?: string; description: string; amount: Money }[] | undefined;
      const combinedDescription = type === "transfer" 
        ? null 
        : items.map(it => it.description.trim()).filter(Boolean).join(", ");
        
      if (type !== "transfer") {
        finalAmount = total;
        payloadItems = items
          .filter((it) => Number.parseFloat(it.value) > 0)
          .map((it, i) => ({
            ...(it.id.startsWith("new_") ? {} : { id: it.id }),
            description: it.description.trim() || `Item ${i + 1}`,
            amount: fromMajor(Number.parseFloat(it.value) || 0, currency),
          }));
        if ((payloadItems?.length ?? 0) <= 1) {
          payloadItems = [];
        }
      }

      await getRepositories().transactions.update(id, {
        type: type as Transaction["type"],
        account_id: accountId,
        amount: finalAmount,
        category_id: type === "transfer" ? null : categoryId,
        labels: selectedLabels,
        description: combinedDescription || null,
        payment_method: paymentMethod || null,
        note: await encryptForWrite(note.trim() || null),
        occurred_at: new Date(date).toISOString(),
        items: type !== "transfer" ? (payloadItems ?? []) : null,
      });

      if (type !== "transfer" && isPaid && categoryId !== originalCategoryId) {
        void learnCategory(combinedDescription || "", categoryId, originalCategoryId);
      }

      router.push("/transactions");
    } catch (e) {
      setSaveErr(e instanceof Error ? e.message : "Couldn't save changes.");
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
          {accounts.map((a) => (
            <button key={a.id} className="chip" data-active={a.id === accountId} onClick={() => setAccountId(a.id)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <AccountBadge type={a.type} color={a.color} id={a.id} name={a.name} /> {a.name}
            </button>
          ))}
        </div>
      </Field>

      {type === "transfer" ? (
        <Field label={`Amount (${currency})`}>
          <input className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
        </Field>
      ) : (
        <div className="card" style={{ padding: 22, display: "grid", gap: 14 }}>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>Amount{items.length > 1 ? " · sum of items" : ""}</div>
            <div style={{ fontSize: 40, fontFamily: "var(--font-serif)", fontWeight: 750, letterSpacing: "-0.02em", color: type === "expense" ? "var(--negative)" : "var(--positive)" }}>
              {format(total, "en-US")}
            </div>
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it, idx) => (
              <div key={it.id} style={{ display: "flex", gap: 8 }}>
                <input className="input" placeholder={items.length > 1 ? `Item ${idx + 1}` : "What for? (optional)"} value={it.description}
                  onChange={(e) => updateItem(it.id, { description: e.target.value })} />
                <input className="input" style={{ width: 140, textAlign: "right", fontWeight: 600 }} inputMode="decimal" placeholder="0.00"
                  value={it.value}
                  onChange={(e) => updateItem(it.id, { value: e.target.value.replace(/[^0-9.]/g, "") })} />
                {items.length > 1 && (
                  <button className="chip" onClick={() => setItems((p) => p.filter((x) => x.id !== it.id))} aria-label="Remove">×</button>
                )}
              </div>
            ))}
            <button className="chip" style={{ borderStyle: "dashed", color: "var(--accent)", justifySelf: "start" }}
              onClick={() => setItems((p) => [...p, { id: `new_${Date.now()}`, description: "", value: "" }])}>＋ Add item / split</button>
          </div>
        </div>
      )}

      {type !== "transfer" && (
        <Field label="Category">
          <SearchSelect value={categoryId} onChange={setCategoryId} options={categoryOptions} placeholder="Search a category…" />
        </Field>
      )}

      {type !== "transfer" && payMethods.length > 0 && (
        <Field label="Payment method">
          <div style={chips}>
            {payMethods.map((m) => (
              <button key={m.id} className="chip" data-active={m.id === paymentMethod} onClick={() => setPaymentMethod(m.id)}>{m.label}</button>
            ))}
          </div>
        </Field>
      )}

      <Field label="Labels">
        <LabelPicker labels={labels} selected={selectedLabels} onChange={setSelectedLabels} />
      </Field>

      <Field label="Note"><input className="input" value={note} onChange={(e) => setNote(e.target.value)} placeholder="Optional note" /></Field>
      <Field label="Date"><input className="input" type="datetime-local" value={date} onChange={(e) => setDate(e.target.value)} /></Field>

      {saveErr && (
        <div className="card" style={{ padding: "10px 14px", background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)", fontSize: 14 }}>
          {saveErr}
        </div>
      )}

      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <button className="btn" onClick={save} disabled={saving}>{saving ? "Saving…" : "Save changes"}</button>
        <button className="btn ghost" onClick={() => router.push("/transactions")}>Cancel</button>
        <button
          className="btn ghost"
          style={{ marginLeft: "auto", color: "var(--negative)" }}
          disabled={saving}
          onClick={async () => {
            if (typeof window !== "undefined" && !window.confirm("Delete this transaction? This can't be undone.")) return;
            setSaving(true);
            try { await getRepositories().transactions.remove(id); router.push("/transactions"); }
            finally { setSaving(false); }
          }}
        >Delete</button>
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
