"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { AccountType } from "@pocketcare/types";
import { fromMajor } from "@pocketcare/money";
import { getRepositories, getDb } from "../../../src/powersync";
import { useBaseCurrency } from "../../../src/hooks";
import { ACCOUNT_COLORS } from "../../../src/colors";
import { FloatingInput } from "../../../src/ui/FloatingInput";

const TYPES = Object.values(AccountType);
const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];
const COLORS = ACCOUNT_COLORS;

export default function NewAccountPage() {
  const router = useRouter();
  const [name, setName] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>(AccountType.Savings);
  const base = useBaseCurrency();
  const [currency, setCurrency] = useState(base);
  const [color, setColor] = useState<string>(COLORS[0]);
  const [includeNw, setIncludeNw] = useState(true);
  const [opening, setOpening] = useState("");
  const [spent, setSpent] = useState("");
  const [limit, setLimit] = useState("");
  const [saving, setSaving] = useState(false);
  const [allowNeg, setAllowNeg] = useState<boolean | null>(null); // null = follow type default

  const isCard = type === AccountType.CreditCard;
  const allowNegEffective = allowNeg ?? isCard;

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
        // A credit card's "balance" is what you owe — record the amount already
        // spent as a negative opening balance so the ledger shows it as owed.
        const owed = Number.parseFloat(spent);
        if (owed) await repos.accounts.setOpeningBalance(account.id, fromMajor(-owed, currency), new Date().toISOString());
        // Store the credit limit (with placeholder cycle dates you can edit on the Cards page).
        const lim = Number.parseFloat(limit);
        if (lim) await repos.creditCards.upsertDetails({ account_id: account.id, statement_day: 1, due_day: 20, credit_limit: fromMajor(lim, currency).amount, card_last4: null });
      } else {
        const v = Number.parseFloat(opening);
        if (v) await repos.accounts.setOpeningBalance(account.id, fromMajor(v, currency), new Date().toISOString());
      }
      router.push(isCard ? "/cards" : "/accounts");
    } finally { setSaving(false); }
  }

  return (
    <div style={{ maxWidth: 520, display: "grid", gap: 14 }} className="fade-up">
      <h1>New account</h1>
      <FloatingInput label="Account name" value={name} onChange={setName} />

      <span className="muted" style={{ fontSize: 13 }}>Type</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {TYPES.map((tp) => <button key={tp} className="chip" data-active={tp === type} style={{ textTransform: "capitalize" }} onClick={() => setType(tp)}>{tp.replace("_", " ")}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>Currency</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {CURRENCIES.map((c) => <button key={c} className="chip" data-active={c === currency} onClick={() => setCurrency(c)}>{c}</button>)}
      </div>

      <span className="muted" style={{ fontSize: 13 }}>Colour</span>
      <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
        {COLORS.map((c) => (
          <button key={c} aria-label={c} onClick={() => setColor(c)}
            style={{ width: 30, height: 30, borderRadius: 999, background: c, cursor: "pointer",
              border: c === color ? "3px solid var(--text)" : "2px solid var(--border)" }} />
        ))}
      </div>

      <label style={{ display: "flex", gap: 8, alignItems: "center", fontSize: 14 }}>
        <input type="checkbox" checked={includeNw} onChange={(e) => setIncludeNw(e.target.checked)} />
        Include this account in net worth
      </label>

      <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 14 }}>
        <input type="checkbox" checked={allowNegEffective} onChange={(e) => setAllowNeg(e.target.checked)} style={{ marginTop: 3 }} />
        <span>Allow negative balance (overdraft)<br />
          <span className="muted" style={{ fontSize: 12 }}>{allowNegEffective ? "Spending can take this account below zero." : "Transactions that would overdraw this account are blocked."}</span>
        </span>
      </label>

      {isCard ? (
        <>
          <span className="muted" style={{ fontSize: 13 }}>Credit card details</span>
          <div style={{ display: "flex", gap: 8 }}>
            <FloatingInput label={`Credit limit (${currency})`} inputMode="decimal" value={limit} onChange={(v) => setLimit(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
            <FloatingInput label="Spent so far" inputMode="decimal" value={spent} onChange={(v) => setSpent(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
          </div>
          <span className="muted" style={{ fontSize: 12, marginTop: -4 }}>You can set the billing cycle (statement & due dates) on the Cards page.</span>
        </>
      ) : (
        <FloatingInput label={`Opening balance (${currency}, optional)`} inputMode="decimal" value={opening} onChange={(v) => setOpening(v.replace(/[^0-9.]/g, ""))} />
      )}

      <button className="btn" onClick={save} disabled={!name.trim() || saving} style={{ justifyContent: "center", padding: 13 }}>
        {saving ? "Saving…" : "Save"}
      </button>
    </div>
  );
}
