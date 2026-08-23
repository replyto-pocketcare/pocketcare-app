"use client";

/**
 * Create / edit a recurring income or payment. Backed by the recurring engine,
 * so it posts real transactions.
 *
 * Recurring SAVINGS are not created here. A SIP is a transfer into an
 * investment account, so it is set up in Investments next to the holding it
 * funds — see src/investments/write.ts. The engine still knows how to post
 * `saving` items; this modal just isn't how they are born.
 */
import { useState } from "react";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { Modal } from "../ui/Modal";
import { FloatingInput } from "../ui/FloatingInput";
import { utcToLocalTime, localToUtcTime } from "../time";
import type { Freq } from "../recurring/engine";
import { createRecurring, updateRecurring, type RecurringDirection, type RecurringItem } from "./recurring";
import { isInvestmentAccount } from "@sanvya/types";

const FREQS: Freq[] = ["daily", "weekly", "monthly", "yearly"];

/**
 * One-tap starters, per direction. They only fill the name — every other field
 * stays the user's to choose — so a wrong tap costs nothing and there is no
 * hidden magic behind the chip.
 */
const PRESETS: Partial<Record<RecurringDirection, string[]>> = {
  income: ["Salary", "Rent", "Interest", "Freelance"],
  payment: ["Rent", "Electricity", "Internet", "Subscription", "EMI"],
};

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

  const spendAccounts = accounts.filter((a) => !isInvestmentAccount(a.type));
  const isPayment = direction === "payment";

  const [name, setName] = useState(edit?.name ?? prefill?.name ?? "");
  const [amount, setAmount] = useState(edit ? String(edit.amount / 100) : prefill?.amount != null ? String(prefill.amount / 100) : "");
  const [accountId, setAccountId] = useState(edit?.account_id ?? spendAccounts[0]?.id ?? "");
  const [categoryId, setCategoryId] = useState(edit?.category_id ?? "");
  const [freq, setFreq] = useState<Freq>((edit?.frequency as Freq) ?? prefill?.frequency ?? "monthly");
  const [firstDue, setFirstDue] = useState(edit?.next_due ?? new Date().toISOString().slice(0, 10));
  const [alertTime, setAlertTime] = useState(utcToLocalTime(edit?.alert_time_utc));
  const [autoPost, setAutoPost] = useState(edit ? edit.auto_post === 1 : false);
  const [saving, setSaving] = useState(false);

  const accountLabel = direction === "income" ? t("depositInto") : t("payFrom");
  const canSave = !!name.trim() && !!amount && !!accountId;

  async function submit() {
    if (!canSave) return;
    setSaving(true);
    try {
      const input = {
        direction, name: name.trim(), amount: Number(amount),
        accountId, toAccountId: null,
        categoryId: isPayment && categoryId ? categoryId : null,
        frequency: freq, firstDue, autoPost,
        alert_time_utc: localToUtcTime(alertTime),
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

        {!edit && (
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {(PRESETS[direction] ?? []).map((p) => (
              <button
                key={p}
                type="button"
                className="chip"
                data-active={name.trim().toLowerCase() === p.toLowerCase()}
                onClick={() => setName(p)}
              >
                + {p}
              </button>
            ))}
          </div>
        )}

        <FloatingInput label={t("name")} value={name} onChange={setName} />
        <FloatingInput label={t("amountCur", { base })} group currency={base} value={amount} onChange={setAmount} />


        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>{accountLabel}
          <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
            <option value="" disabled>{t("selectAccount")}</option>
            {spendAccounts.map((a) => <option key={a.id} value={a.id}>{a.name}</option>)}
          </select>
        </label>


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
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, width: 140 }}>{t("firstDue")}
            <input className="input" type="date" value={firstDue} onChange={(e) => setFirstDue(e.target.value)} />
          </label>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, width: 100 }}>Alert time
            <input className="input" type="time" value={alertTime} onChange={(e) => setAlertTime(e.target.value)} />
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
