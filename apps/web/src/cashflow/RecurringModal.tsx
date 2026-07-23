"use client";

/**
 * Create / edit a recurring cashflow item (income, payment or saving). Backed by
 * the real recurring engine (template + rule) so it actually posts transactions —
 * no standalone planned_cashflow rows. Savings are a recurring transfer into an
 * investment account.
 */
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { Modal } from "../ui/Modal";
import { FloatingInput } from "../ui/FloatingInput";
import type { Freq } from "../templates/write";
import { createRecurring, updateRecurring, type RecurringDirection, type RecurringItem } from "./recurring";

const FREQS: Freq[] = ["daily", "weekly", "monthly", "yearly"];
const INVESTMENT_TYPES = ["demat", "stocks", "mutual_funds"];

export function RecurringModal({ direction, base, edit, prefill, onClose }: {
  direction: RecurringDirection;
  base: string;
  edit?: RecurringItem | null;
  prefill?: { name?: string; amount?: number; frequency?: Freq } | null;
  onClose: (saved: boolean) => void;
}) {
  const { t } = useTranslation("cashflow");
  const { data: accounts = [] } = useQuery<{ id: string; name: string; type: string }>(
    "SELECT id, name, type FROM accounts WHERE deleted_at IS NULL AND IFNULL(is_archived,0)=0 AND IFNULL(kind,'real')='real' ORDER BY created_at",
  );
  const { data: cats = [] } = useQuery<{ id: string; name: string; kind: string }>(
    "SELECT id, name, kind FROM categories WHERE deleted_at IS NULL ORDER BY name",
  );

  const spendAccounts = accounts.filter((a) => !INVESTMENT_TYPES.includes(a.type));
  const investAccounts = accounts.filter((a) => INVESTMENT_TYPES.includes(a.type));
  const isSaving = direction === "saving";
  const isPayment = direction === "payment";

  const [name, setName] = useState(edit?.name ?? prefill?.name ?? "");
  const [amount, setAmount] = useState(edit ? String(edit.amount / 100) : prefill?.amount != null ? String(prefill.amount / 100) : "");
  const [accountId, setAccountId] = useState(edit?.account_id ?? spendAccounts[0]?.id ?? "");
  const [toAccountId, setToAccountId] = useState(edit?.to_account_id ?? investAccounts[0]?.id ?? "");
  const [categoryId, setCategoryId] = useState(edit?.category_id ?? "");
  const [freq, setFreq] = useState<Freq>((edit?.frequency as Freq) ?? prefill?.frequency ?? "monthly");
  const [firstDue, setFirstDue] = useState(edit?.next_due ?? new Date().toISOString().slice(0, 10));
  const [autoPost, setAutoPost] = useState(edit ? edit.auto_post === 1 : false);
  const [saving, setSaving] = useState(false);

  const accountLabel = direction === "income" ? t("depositInto") : isSaving ? t("fundFrom") : t("payFrom");
  const canSave = !!name.trim() && !!amount && !!accountId && (!isSaving || !!toAccountId);

  async function submit() {
    if (!canSave) return;
    setSaving(true);
    try {
      const input = {
        direction, name: name.trim(), amount: Number(amount),
        accountId, toAccountId: isSaving ? toAccountId : null,
        categoryId: isPayment && categoryId ? categoryId : null,
        frequency: freq, firstDue, autoPost,
      };
      if (edit) await updateRecurring(edit.ruleId, edit.templateId, input);
      else await createRecurring(input);
      onClose(true);
    } finally {
      setSaving(false);
    }
  }

  return (
    <Modal open onClose={() => onClose(false)}>
      <div style={{ display: "grid", gap: 12 }}>
        <h2 style={{ margin: 0, textTransform: "capitalize" }}>{edit ? t("modalEdit", { what: t(`dirLabel.${direction}`) }) : t("modalAdd", { what: t(`dirLabel.${direction}`) })}</h2>

        <FloatingInput label={t("name")} value={name} onChange={setName} />
        <FloatingInput label={t("amountCur", { base })} group currency={base} value={amount} onChange={setAmount} />

        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{accountLabel}
          <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="" disabled>{t("selectAccount")}</option>
            {spendAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </label>

        {isSaving && (
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{t("intoInvestment")}
            {investAccounts.length === 0
              ? <span style={{ color: "var(--negative)" }}>{t("noInvestAccount")}</span>
              : <select className="input" value={toAccountId} onChange={(e) => setToAccountId(e.target.value)}>
                  {investAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
                </select>}
          </label>
        )}

        {isPayment && (
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{t("categoryOptional")}
            <select className="input" value={categoryId} onChange={(e) => setCategoryId(e.target.value)}>
              <option value="">{t("noCategory")}</option>
              {cats.filter((c) => c.kind === "expense").map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select>
          </label>
        )}

        <div style={{ display: "flex", gap: 8, alignItems: "flex-end", flexWrap: "wrap" }}>
          <div style={{ display: "grid", gap: 4, flex: 1, minWidth: 180 }}>
            <span className="muted" style={{ fontSize: 12 }}>{t("frequency")}</span>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {FREQS.map((f) => <button key={f} className="chip" data-active={f === freq} onClick={() => setFreq(f)}>{t(`freq.${f}`)}</button>)}
            </div>
          </div>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, width: 160 }}>{t("firstDue")}
            <input className="input" type="date" value={firstDue} onChange={(e) => setFirstDue(e.target.value)} />
          </label>
        </div>

        <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 13, cursor: "pointer" }}>
          <input type="checkbox" checked={autoPost} onChange={(e) => setAutoPost(e.target.checked)} style={{ marginTop: 3 }} />
          <span>{t("postAuto")}<br /><span className="muted" style={{ fontSize: 12 }}>{t("postAutoOff")}</span></span>
        </label>

        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 2 }}>
          <button className="btn ghost" onClick={() => onClose(false)} disabled={saving}>{t("cancel")}</button>
          <button className="btn" onClick={submit} disabled={!canSave || saving}>{saving ? t("savingEllipsis") : edit ? t("save") : t("add")}</button>
        </div>
      </div>
    </Modal>
  );
}
