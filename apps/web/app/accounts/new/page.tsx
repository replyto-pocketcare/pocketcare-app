"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { AccountType } from "@pocketcare/types";
import { fromMajor } from "@pocketcare/money";
import { getRepositories, getDb } from "../../../src/powersync";
import { useBaseCurrency } from "../../../src/hooks";
import { ACCOUNT_COLORS } from "../../../src/colors";
import { FloatingInput } from "../../../src/ui/FloatingInput";

const TYPES = Object.values(AccountType);
const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];
const COLORS = ACCOUNT_COLORS;

/**
 * Decide when a newly-entered statement balance is actually payable.
 * If the card is created after this month's statement day, the current statement
 * has already closed, so the amount rolls to the NEXT cycle → 0 due this cycle.
 */
function cardDueDate(created: Date, statementDay: number, dueDay: number): { dueOn: Date; thisCycle: boolean } {
  const billMonthOffset = created.getDate() <= statementDay ? 0 : 1; // rolled to next statement?
  const stmtMonth = created.getMonth() + billMonthOffset;
  const dueMonth = stmtMonth + (dueDay >= statementDay ? 0 : 1); // due day may fall next month
  return { dueOn: new Date(created.getFullYear(), dueMonth, dueDay), thisCycle: billMonthOffset === 0 };
}

export default function NewAccountPage() {
  const { t } = useTranslation("accounts");
  const router = useRouter();
  const [name, setName] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>(AccountType.Savings);
  const base = useBaseCurrency();
  const [currency, setCurrency] = useState(base);
  const [color, setColor] = useState<string>(COLORS[0]);
  const [includeNw, setIncludeNw] = useState(true);
  const [opening, setOpening] = useState("");
  const [dueAmount, setDueAmount] = useState("");
  const [limit, setLimit] = useState("");
  const [statementDay, setStatementDay] = useState("1");
  const [dueDay, setDueDay] = useState("20");
  const [saving, setSaving] = useState(false);
  const [allowNeg, setAllowNeg] = useState<boolean | null>(null); // null = follow type default

  const isCard = type === AccountType.CreditCard;
  const isDemat = type === AccountType.Demat;
  const allowNegEffective = allowNeg ?? isCard;

  // Live preview of the card cycle so the user understands the "0 due this cycle" rule.
  const cardPreview = isCard && dueAmount
    ? cardDueDate(new Date(), Math.min(28, Math.max(1, Number(statementDay) || 1)), Math.min(28, Math.max(1, Number(dueDay) || 20)))
    : null;

  async function save() {
    if (!name.trim() || saving) return;
    setSaving(true);
    try {
      const repos = getRepositories();
      const account = await repos.accounts.create({ name: name.trim(), type, currency, icon: null, color, is_archived: false, allow_negative: allowNegEffective });
      if (!includeNw) {
        await getDb()?.execute("UPDATE accounts SET include_in_net_worth = 0, updated_at = ? WHERE id = ?", [new Date().toISOString(), account.id]);
      }
      if (isCard) {
        const sDay = Math.min(28, Math.max(1, Number(statementDay) || 1));
        const dDay = Math.min(28, Math.max(1, Number(dueDay) || 20));
        const owed = Number.parseFloat(dueAmount) || 0;
        // A credit card's "balance" is what you owe — record it as a negative opening balance.
        if (owed) await repos.accounts.setOpeningBalance(account.id, fromMajor(-owed, currency), new Date().toISOString());
        const lim = Number.parseFloat(limit);
        await repos.creditCards.upsertDetails({ account_id: account.id, statement_day: sDay, due_day: dDay, credit_limit: lim ? fromMajor(lim, currency).amount : 0, card_last4: null });
        // Cycle-aware due: if created after this month's statement day, the amount
        // is due next cycle (0 this cycle). Store pending_due + due_on.
        if (owed) {
          const { dueOn } = cardDueDate(new Date(), sDay, dDay);
          await getDb()?.execute(
            "UPDATE credit_card_details SET pending_due = ?, due_on = ?, updated_at = ? WHERE account_id = ?",
            [fromMajor(owed, currency).amount, dueOn.toISOString().slice(0, 10), new Date().toISOString(), account.id],
          );
        }
      } else {
        const v = Number.parseFloat(opening);
        if (v) await repos.accounts.setOpeningBalance(account.id, fromMajor(v, currency), new Date().toISOString());
      }
      router.push(isCard ? "/cards" : isDemat ? "/investments" : "/accounts");
    } finally { setSaving(false); }
  }

  return (
    <div style={{ maxWidth: 520, display: "grid", gap: 14 }} className="fade-up">
      <h1>{t("newTitle")}</h1>
      <FloatingInput label={t("accountName")} value={name} onChange={setName} />

      <span className="muted" style={{ fontSize: 13 }}>{t("typeLabel")}</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {TYPES.map((tp) => <button key={tp} className="chip" data-active={tp === type} onClick={() => setType(tp)}>{t(`type.${tp}`, tp.replace("_", " "))}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>{t("currency")}</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {CURRENCIES.map((c) => <button key={c} className="chip" data-active={c === currency} onClick={() => setCurrency(c)}>{c}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>{t("colour")}</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {COLORS.map((c) => (
          <button key={c} aria-label={c} onClick={() => setColor(c)}
            style={{ width: 30, height: 30, borderRadius: 999, background: c, cursor: "pointer",
              border: c === color ? "3px solid var(--text)" : "2px solid var(--border)" }} />
        ))}
      </div>

      <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
        <input type="checkbox" checked={includeNw} onChange={(e) => setIncludeNw(e.target.checked)} />
        {t("includeNw")}
      </label>

      <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 14 }}>
        <input type="checkbox" checked={allowNegEffective} onChange={(e) => setAllowNeg(e.target.checked)} style={{ marginTop: 3 }} />
        <span>{t("allowNeg")}<br />
          <span className="muted" style={{ fontSize: 12 }}>{allowNegEffective ? t("allowNegOn") : t("allowNegOff")}</span>
        </span>
      </label>

      {isCard ? (
        <>
          <span className="muted" style={{ fontSize: 13 }}>{t("creditCardDetails")}</span>
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={t("creditLimit", { currency })} group currency={currency} value={limit} onChange={setLimit} style={{ flex: 1 }} />
            <FloatingInput label={t("amountDue", { currency })} group currency={currency} value={dueAmount} onChange={setDueAmount} style={{ flex: 1 }} />
          </div>
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={t("statementDay")} inputMode="numeric" value={statementDay} onChange={(v) => setStatementDay(v.replace(/\D/g, "").slice(0, 2))} style={{ flex: 1 }} />
            <FloatingInput label={t("dueDay")} inputMode="numeric" value={dueDay} onChange={(v) => setDueDay(v.replace(/\D/g, "").slice(0, 2))} style={{ flex: 1 }} />
          </div>
          {cardPreview && (
            <div style={{ padding: "9px 12px", borderRadius: 10, fontSize: 12.5, background: "var(--surface-2)", border: "1px solid var(--border)", color: "var(--text-2)" }}>
              {cardPreview.thisCycle
                ? t("dueThisCycle", { amount: `${currency} ${dueAmount}`, date: cardPreview.dueOn.toLocaleDateString() })
                : t("dueNextCycle", { amount: `${currency} ${dueAmount}`, date: cardPreview.dueOn.toLocaleDateString() })}
            </div>
          )}
        </>
      ) : isDemat ? (
        <>
          <FloatingInput label={t("invested", { currency })} group currency={currency} value={opening} onChange={setOpening} />
          <span className="muted" style={{ fontSize: 12, marginTop: -4 }}>{t("dematNote")}</span>
        </>
      ) : (
        <FloatingInput label={t("openingBalance", { currency })} group currency={currency} value={opening} onChange={setOpening} />
      )}

      <button className="btn" onClick={save} disabled={!name.trim() || saving} style={{ justifyContent: "center", padding: 13 }}>
        {saving ? t("saving") : t("save")}
      </button>
    </div>
  );
}
