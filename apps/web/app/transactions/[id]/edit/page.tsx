"use client";

import { useEffect, useState, useMemo } from "react";
import { useParams, useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { fromMajor, toMajor, money, format, sum, type Money } from "@pocketcare/money";
import type { Account, Transaction } from "@pocketcare/types";
import type { TransactionAudit } from "@pocketcare/data";
import { getRepositories } from "../../../../src/powersync";
import { LabelPicker } from "../../../../src/ui/LabelPicker";
import { SearchSelect } from "../../../../src/ui/SearchSelect";
import { AccountBadge } from "../../../../src/ui/AccountBadge";
import { useConfirm } from "../../../../src/ui/Confirm";
import { Modal } from "../../../../src/ui/Modal";
import { KebabMenu } from "../../../../src/ui/KebabMenu";
import { useEntitlement } from "../../../../src/entitlement";
import { useLearnCategory } from "../../../../src/categorize/hooks";
import { useMoneyFmt } from "../../../../src/ui/Money";
import { useUserProfiles } from "../../../../src/splits/hooks";
import { getUserId } from "../../../../src/powersync";
import Link from "next/link";
import { encryptForWrite } from "../../../../src/crypto/fields";
import { decryptField, isEncrypted } from "@pocketcare/crypto";
import { getDek } from "../../../../src/crypto/session";

type TxType = "expense" | "income" | "transfer" | "adjustment";

export default function EditTransactionPage() {
  const { t } = useTranslation("transactions");
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const confirm = useConfirm();
  const [showHistory, setShowHistory] = useState(false);
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

  if (!tx) return <p className="muted">{t("loading")}</p>;
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
  // Resolve backend ids to human-readable names for the edit-history view.
  const catName = (cid: string) => cats.find((c) => c.id === cid)?.name ?? "—";
  const acctName = (aid: string) => accounts.find((a) => a.id === aid)?.name ?? "—";
  const payName = (pid: string) => payMethodMap.find((m) => m.id === pid)?.label ?? pid;

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
      setSaveErr(e instanceof Error ? e.message : t("saveChangesError"));
    } finally { setSaving(false); }
  }

  return (
    <div style={{ maxWidth: 620, display: "grid", gap: 14 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <h1>{t("editTitle")}</h1>
        {audit.length > 0 && (
          <KebabMenu label={t("txOptions")} items={[
            { label: t("viewHistory"), onClick: () => setShowHistory(true) },
          ]} />
        )}
      </div>

      <SplitBanner txId={id} />

      <div style={{ display: "flex", gap: 8 }}>
        {(["expense", "income", "transfer"] as TxType[]).map((tp) => (
          <button key={tp} className="chip" data-active={tp === type} style={{ flex: 1 }} onClick={() => setType(tp)}>{t(`type.${tp}`)}</button>
        ))}
      </div>

      <Field label={t("account")}>
        <div style={chips}>
          {accounts.map((a) => (
            <button key={a.id} className="chip" data-active={a.id === accountId} onClick={() => setAccountId(a.id)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
              <AccountBadge type={a.type} color={a.color} id={a.id} name={a.name} /> {a.name}
            </button>
          ))}
        </div>
      </Field>

      {type === "transfer" ? (
        <Field label={t("amountCurrency", { currency })}>
          <input className="input" inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value.replace(/[^0-9.]/g, ""))} />
        </Field>
      ) : (
        <div className="card" style={{ padding: 22, display: "grid", gap: 14 }}>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>{items.length > 1 ? t("amountWithItems") : t("amount")}</div>
            <div style={{ fontSize: 40, fontWeight: 750, letterSpacing: "-0.02em", color: type === "expense" ? "var(--negative)" : "var(--positive)" }}>
              {format(total, "en-US")}
            </div>
          </div>
          <div style={{ display: "grid", gap: 8 }}>
            {items.map((it, idx) => (
              <div key={it.id} style={{ display: "flex", gap: 8 }}>
                <input className="input" placeholder={items.length > 1 ? t("item", { n: idx + 1 }) : t("whatFor")} value={it.description}
                  onChange={(e) => updateItem(it.id, { description: e.target.value })} />
                <input className="input" style={{ width: 140, textAlign: "right", fontWeight: 600 }} inputMode="decimal" placeholder="0.00"
                  value={it.value}
                  onChange={(e) => updateItem(it.id, { value: e.target.value.replace(/[^0-9.]/g, "") })} />
                {items.length > 1 && (
                  <button className="chip" onClick={() => setItems((p) => p.filter((x) => x.id !== it.id))} aria-label={t("remove")}>×</button>
                )}
              </div>
            ))}
            <button className="chip" style={{ borderStyle: "dashed", color: "var(--accent)", justifySelf: "start" }}
              onClick={() => setItems((p) => [...p, { id: `new_${Date.now()}`, description: "", value: "" }])}>＋ {t("addItemSplit")}</button>
          </div>
        </div>
      )}

      {type !== "transfer" && (
        <Field label={t("category")}>
          <SearchSelect value={categoryId} onChange={setCategoryId} options={categoryOptions} placeholder={t("searchCategory")} />
        </Field>
      )}

      {type !== "transfer" && payMethods.length > 0 && (
        <Field label={t("paymentMethod")}>
          <div style={chips}>
            {payMethods.map((m) => (
              <button key={m.id} className="chip" data-active={m.id === paymentMethod} onClick={() => setPaymentMethod(m.id)}>{m.label}</button>
            ))}
          </div>
        </Field>
      )}

      <Field label={t("labels")}>
        <LabelPicker labels={labels} selected={selectedLabels} onChange={setSelectedLabels} />
      </Field>

      <Field label={t("note")}><input className="input" value={note} onChange={(e) => setNote(e.target.value)} placeholder={t("optionalNote")} /></Field>
      <Field label={t("date")}><input className="input" type="datetime-local" value={date} onChange={(e) => setDate(e.target.value)} /></Field>

      {saveErr && (
        <div className="card" style={{ padding: "10px 14px", background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)", fontSize: 14 }}>
          {saveErr}
        </div>
      )}

      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <button className="btn" onClick={save} disabled={saving}>{saving ? t("saving") : t("saveChanges")}</button>
        <button className="btn ghost" onClick={() => router.push("/transactions")}>{t("cancel")}</button>
        <button
          className="btn ghost"
          style={{ marginLeft: "auto", color: "var(--negative)" }}
          disabled={saving}
          onClick={async () => {
            if (!(await confirm({ title: t("deleteConfirmTitle"), message: t("deleteConfirmMsg") }))) return;
            setSaving(true);
            try { await getRepositories().transactions.remove(id); router.push("/transactions"); }
            finally { setSaving(false); }
          }}
        >{t("delete")}</button>
      </div>

      {/* Edit history — behind the ⋯ menu, not shown by default */}
      <Modal open={showHistory} onClose={() => setShowHistory(false)}>
        <h2 style={{ margin: "0 0 12px" }}>{t("editHistory")}</h2>
        <div style={{ display: "grid", gap: 10, maxHeight: "60vh", overflowY: "auto" }}>
          {audit.length === 0 ? (
            <p className="muted" style={{ margin: 0, fontSize: 13 }}>{t("noEdits")}</p>
          ) : audit.map((a) => (
            <div key={a.id} style={{ fontSize: 13, borderBottom: "1px solid var(--border)", paddingBottom: 8 }}>
              <div className="muted" style={{ fontSize: 12 }}>{new Date(a.created_at).toLocaleString()} · {a.action}</div>
              <AuditChanges changes={a.changes} currency={currency} catName={catName} acctName={acctName} payName={payName} />
            </div>
          ))}
        </div>
      </Modal>
    </div>
  );
}

// Only these fields are shown in edit history — everything else (ids we can't
// resolve, timestamps, checksums, user_id, etc.) is backend noise and hidden.
const AUDIT_LABELS: Record<string, string> = {
  amount: "Amount",
  to_amount: "To amount",
  description: "Description",
  merchant: "Merchant",
  note: "Note",
  occurred_at: "Date",
  type: "Type",
  category_id: "Category",
  account_id: "Account",
  to_account_id: "To account",
  payment_method_id: "Payment method",
};

function AuditChanges({ changes, currency, catName, acctName, payName }: {
  changes: string | null; currency: string;
  catName: (id: string) => string; acctName: (id: string) => string; payName: (id: string) => string;
}) {
  const { t } = useTranslation("transactions");
  if (!changes) return null;
  let parsed: Record<string, { from: unknown; to: unknown }> = {};
  try { parsed = JSON.parse(changes); } catch { return null; }

  const show = (field: string, v: unknown): string => {
    if (v === null || v === undefined || v === "") return "—";
    const s = String(v);
    switch (field) {
      case "amount":
      case "to_amount": return format(money(Number(v) || 0, currency), "en-US");
      case "occurred_at": return new Date(s).toLocaleString();
      case "category_id": return catName(s);
      case "account_id":
      case "to_account_id": return acctName(s);
      case "payment_method_id": return payName(s);
      case "type": return s.charAt(0).toUpperCase() + s.slice(1);
      default: return s;
    }
  };

  const entries = Object.entries(parsed).filter(([field]) => AUDIT_LABELS[field]);
  if (entries.length === 0) {
    return <div className="muted" style={{ fontSize: 12, marginTop: 4 }}>{t("minorUpdate")}</div>;
  }
  return (
    <div style={{ display: "grid", gap: 2, marginTop: 4 }}>
      {entries.map(([field, { from, to }]) => (
        <div key={field}><strong>{t(`audit.${field}`)}</strong>: <span className="muted">{show(field, from)}</span> → {show(field, to)}</div>
      ))}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <label style={{ display: "grid", gap: 8 }}><span className="muted" style={{ fontSize: 13 }}>{label}</span>{children}</label>;
}
const chips: React.CSSProperties = { display: "flex", flexWrap: "wrap", gap: 8 };

/**
 * Shown when this transaction is one leg of a split expense. Explains that it's
 * part of a shared bill and shows the breakdown (total, your share, who paid,
 * what's owed) with a link into the group — so users find the split detail here
 * instead of seeing three cryptic ledger rows in their list.
 */
function SplitBanner({ txId }: { txId: string }) {
  const fmt = useMoneyFmt();
  const profiles = useUserProfiles();
  const me = (() => { try { return getUserId(); } catch { return ""; } })();

  const { data: post = [] } = useQuery<{ expense_id: string }>(
    "SELECT expense_id FROM expense_postings WHERE transaction_id = ? AND expense_id IS NOT NULL AND deleted_at IS NULL LIMIT 1",
    [txId],
  );
  const expenseId = post[0]?.expense_id ?? "";
  const { data: exp = [] } = useQuery<{ id: string; group_id: string; description: string | null; amount: number; currency: string; occurred_at: string; created_by: string }>(
    expenseId ? "SELECT id, group_id, description, amount, currency, occurred_at, created_by FROM expenses WHERE id = ? AND deleted_at IS NULL" : "SELECT NULL WHERE 0",
    expenseId ? [expenseId] : [],
  );
  const { data: parts = [] } = useQuery<{ user_id: string; paid_amount: number; share_amount: number }>(
    expenseId ? "SELECT user_id, paid_amount, share_amount FROM expense_participants WHERE expense_id = ? AND deleted_at IS NULL" : "SELECT NULL WHERE 0",
    expenseId ? [expenseId] : [],
  );
  const { data: grp = [] } = useQuery<{ name: string }>(
    exp[0]?.group_id ? "SELECT name FROM split_groups WHERE id = ?" : "SELECT NULL WHERE 0",
    exp[0]?.group_id ? [exp[0].group_id] : [],
  );

  const e = exp[0];
  if (!e) return null;
  const cur = e.currency;
  const mine = parts.find((p) => p.user_id === me);
  const myShare = mine?.share_amount ?? 0;
  const myPaid = mine?.paid_amount ?? 0;
  const net = myPaid - myShare; // >0 you're owed, <0 you owe

  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 10, border: "1px solid var(--accent-soft)", background: "var(--accent-ghost)" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 8 }}>
        <strong style={{ fontSize: 15 }}>Split expense</strong>
        {e.group_id && <Link href={`/groups/${e.group_id}`} className="chip">{grp[0]?.name ? `Open ${grp[0].name}` : "Open group"}</Link>}
      </div>
      <div style={{ display: "flex", gap: 18, flexWrap: "wrap", fontSize: 13 }}>
        <span><span className="muted">Total bill</span><br /><strong>{fmt(money(e.amount, cur))}</strong></span>
        <span><span className="muted">Your share</span><br /><strong>{fmt(money(myShare, cur))}</strong></span>
        <span><span className="muted">You paid</span><br /><strong>{fmt(money(myPaid, cur))}</strong></span>
        <span><span className="muted">{net >= 0 ? "Owed to you" : "You owe"}</span><br />
          <strong style={{ color: net >= 0 ? "var(--positive)" : "var(--negative)" }}>{fmt(money(Math.abs(net), cur))}</strong></span>
      </div>
      {parts.length > 0 && (
        <div style={{ display: "grid", gap: 4, fontSize: 12.5 }}>
          <div className="muted">Participants</div>
          {parts.map((p) => (
            <div key={p.user_id} style={{ display: "flex", justifyContent: "space-between", gap: 10 }}>
              <span style={{ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>
                {p.user_id === me ? "You" : profiles.get(p.user_id)?.name ?? "Someone"}
              </span>
              <span className="muted" style={{ flexShrink: 0 }}>share {fmt(money(p.share_amount, cur))} · paid {fmt(money(p.paid_amount, cur))}</span>
            </div>
          ))}
        </div>
      )}
      <div className="muted" style={{ fontSize: 11.5 }}>
        This is your private ledger entry for the split. To change the split itself, open the group.
      </div>
    </div>
  );
}
