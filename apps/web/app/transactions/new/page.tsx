"use client";

import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@powersync/react";
import { fromMajor, sum, format, type Money } from "@pocketcare/money";
import type { Account } from "@pocketcare/types";
import { getRepositories } from "../../../src/powersync";

type TxType = "expense" | "income" | "transfer";
let counter = 0;
const newItem = () => ({ id: `i${++counter}`, description: "", value: "" });

export default function NewTransactionPage() {
  const router = useRouter();
  const { data: accounts = [] } = useQuery<Account>(
    "SELECT * FROM accounts WHERE deleted_at IS NULL ORDER BY created_at",
  );
  const { data: categories = [] } = useQuery<{ id: string; name: string; kind: string; parent_id: string | null }>(
    "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY name",
  );
  const { data: labelList = [] } = useQuery<{ id: string; name: string; color: string | null }>(
    "SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name",
  );

  const [type, setType] = useState<TxType>("expense");
  const [accountId, setAccountId] = useState<string | null>(null);
  const [toAccountId, setToAccountId] = useState<string | null>(null);
  const [categoryId, setCategoryId] = useState<string | null>(null);
  const [label, setLabel] = useState("");
  const [items, setItems] = useState([newItem()]);
  const [toValue, setToValue] = useState(""); // cross-currency destination amount
  const [saving, setSaving] = useState(false);

  const account = accounts.find((a) => a.id === accountId) ?? accounts[0];
  const currency = account?.currency ?? "USD";
  const toAccount = accounts.find((a) => a.id === toAccountId) ?? accounts.find((a) => a.id !== account?.id);
  const crossCurrency = type === "transfer" && toAccount && toAccount.currency !== currency;

  const itemMoneys: Money[] = useMemo(
    () => items.map((it) => fromMajor(Number.parseFloat(it.value) || 0, currency)),
    [items, currency],
  );
  const total = useMemo(() => sum(itemMoneys, currency), [itemMoneys, currency]);
  const relevantCats = categories.filter((c) => (type === "income" ? c.kind === "income" : c.kind === "expense"));

  const update = (id: string, patch: Partial<(typeof items)[number]>) =>
    setItems((prev) => prev.map((it) => (it.id === id ? { ...it, ...patch } : it)));

  const canSave =
    !!account && total.amount > 0 && !saving && (type !== "transfer" || (!!toAccount && toAccount.id !== account.id));

  async function save() {
    if (!account || !canSave) return;
    setSaving(true);
    try {
      const repos = getRepositories();
      if (type === "transfer" && toAccount) {
        await repos.transactions.create({
          account_id: account.id,
          type: "transfer",
          amount: total,
          to_account_id: toAccount.id,
          to_amount: crossCurrency ? fromMajor(Number.parseFloat(toValue) || 0, toAccount.currency) : null,
          label: label.trim() || null,
          occurred_at: new Date().toISOString(),
        });
      } else {
        const payload = items
          .filter((it) => Number.parseFloat(it.value) > 0)
          .map((it, i) => ({
            description: it.description.trim() || `Item ${i + 1}`,
            amount: fromMajor(Number.parseFloat(it.value) || 0, currency),
          }));
        await repos.transactions.create({
          account_id: account.id,
          type,
          amount: total,
          category_id: categoryId,
          label: label.trim() || null,
          occurred_at: new Date().toISOString(),
          items: payload.length > 1 ? payload : undefined,
        });
      }
      router.push("/transactions");
    } finally {
      setSaving(false);
    }
  }

  if (accounts.length === 0) {
    return (
      <div className="fade-up">
        <h1>Add transaction</h1>
        <p className="muted">Create an account first.</p>
        <a href="/accounts/new" className="btn" style={{ marginTop: 12 }}>＋ New account</a>
      </div>
    );
  }

  const accentFor: Record<TxType, string> = { expense: "var(--negative)", income: "var(--positive)", transfer: "var(--forest)" };

  return (
    <div style={{ maxWidth: 620, display: "grid", gap: 16 }} className="fade-up">
      <h1>Add transaction</h1>

      <div style={{ display: "flex", gap: 8 }}>
        {(["expense", "income", "transfer"] as TxType[]).map((tp) => (
          <button key={tp} className="chip" data-active={tp === type} style={{ flex: 1, textTransform: "capitalize" }} onClick={() => setType(tp)}>
            {tp}
          </button>
        ))}
      </div>

      <div className="card" style={{ padding: 22 }}>
        <div className="muted" style={{ fontSize: 13 }}>Amount</div>
        <div style={{ fontSize: 38, fontWeight: 750, color: accentFor[type] }}>{format(total, "en-US")}</div>
      </div>

      <Field label={type === "transfer" ? "From account" : "Account"}>
        <div style={chips}>
          {accounts.map((a) => (
            <button key={a.id} className="chip" data-active={a.id === account.id} onClick={() => setAccountId(a.id)}>
              {a.name} <span className="muted">· {a.currency}</span>
            </button>
          ))}
        </div>
      </Field>

      {type === "transfer" && (
        <Field label="To account">
          <div style={chips}>
            {accounts.filter((a) => a.id !== account.id).map((a) => (
              <button key={a.id} className="chip" data-active={a.id === toAccount?.id} onClick={() => setToAccountId(a.id)}>
                {a.name} <span className="muted">· {a.currency}</span>
              </button>
            ))}
          </div>
        </Field>
      )}

      {crossCurrency && (
        <Field label={`Amount received (${toAccount?.currency})`}>
          <input className="input" inputMode="decimal" placeholder="0.00" value={toValue}
            onChange={(e) => setToValue(e.target.value.replace(/[^0-9.]/g, ""))} />
        </Field>
      )}

      {type !== "transfer" && (
        <Field label="Category">
          <div style={chips}>
            {relevantCats.map((c) => (
              <button key={c.id} className="chip" data-active={c.id === categoryId} onClick={() => setCategoryId(c.id)}>{c.name}</button>
            ))}
          </div>
        </Field>
      )}

      <Field label="Label (optional)">
        {labelList.length > 0 && (
          <div style={{ ...chips, marginBottom: 8 }}>
            {labelList.map((l) => {
              const active = label === l.name;
              const c = l.color || "#b06a4f";
              return (
                <button key={l.id} type="button" onClick={() => setLabel(active ? "" : l.name)}
                  style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "6px 12px", borderRadius: 999, cursor: "pointer",
                    border: `1px solid ${c}`, background: active ? c : `${c}22`, color: active ? "#fff" : "var(--text)" }}>
                  <span style={{ width: 8, height: 8, borderRadius: 999, background: active ? "#fff" : c }} />
                  {l.name}
                </button>
              );
            })}
          </div>
        )}
        <input className="input" placeholder="Pick a label above or type a custom one" value={label} onChange={(e) => setLabel(e.target.value)} />
      </Field>

      {type !== "transfer" && (
        <Field label="Breakdown (＋ sub-items always sum to the total)">
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it, idx) => (
              <div key={it.id} style={{ display: "flex", gap: 8 }}>
                <input className="input" placeholder={`Item ${idx + 1}`} value={it.description} onChange={(e) => update(it.id, { description: e.target.value })} />
                <input className="input" style={{ width: 130, textAlign: "right" }} inputMode="decimal" placeholder="0.00" value={it.value}
                  onChange={(e) => update(it.id, { value: e.target.value.replace(/[^0-9.]/g, "") })} />
                <button className="chip" onClick={() => setItems((p) => (p.length > 1 ? p.filter((x) => x.id !== it.id) : p))} aria-label="Remove">×</button>
              </div>
            ))}
            <button className="chip" style={{ borderStyle: "dashed", color: "var(--accent)" }} onClick={() => setItems((p) => [...p, newItem()])}>＋ Add item</button>
          </div>
        </Field>
      )}

      {type === "transfer" && (
        <Field label="Amount">
          <input className="input" inputMode="decimal" placeholder="0.00" value={items[0]?.value ?? ""}
            onChange={(e) => setItems([{ ...(items[0] ?? newItem()), value: e.target.value.replace(/[^0-9.]/g, "") }])} />
        </Field>
      )}

      <button className="btn" disabled={!canSave} onClick={save} style={{ justifyContent: "center", padding: 14 }}>
        {saving ? "Saving…" : `Save · ${format(total, "en-US")}`}
      </button>
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label style={{ display: "grid", gap: 8 }}>
      <span className="muted" style={{ fontSize: 13 }}>{label}</span>
      {children}
    </label>
  );
}

const chips: React.CSSProperties = { display: "flex", flexWrap: "wrap", gap: 8 };
