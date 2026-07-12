"use client";

import { useTranslation } from "react-i18next";
import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor, toMajor } from "@pocketcare/money";
import { monthlyEquivalent, recurringMonthlyTotal, percentOfIncome } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useMoneyFmt } from "../../src/ui/Money";

interface Loan { id: string; lender: string; principal: number; currency: string; emi_amount: number | null; }
interface Commitment { id: string; kind: string; amount: number; currency: string; frequency: Period; }

const KINDS = ["emi", "subscription", "recurring_expense"] as const;
const CYCLES: Period[] = ["daily", "weekly", "monthly", "yearly"];

export default function LoansPage() {
  const { t } = useTranslation();
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const { data: loans = [] } = useQuery<Loan>("SELECT id, lender, principal, currency, emi_amount FROM loans WHERE deleted_at IS NULL");
  const { data: commitments = [] } = useQuery<Commitment>("SELECT id, kind, amount, currency, frequency FROM recurring_commitments WHERE deleted_at IS NULL");
  const { data: subs = [] } = useQuery<{ amount: number; billing_cycle: Period }>("SELECT amount, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1");

  const monthStart = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString();
  const { data: incomeRows = [] } = useQuery<{ total: number }>(
    "SELECT COALESCE(SUM(amount),0) as total FROM transactions WHERE deleted_at IS NULL AND type='income' AND occurred_at >= ?",
    [monthStart],
  );
  const monthlyIncome = incomeRows[0]?.total ?? 0;

  const recurringMonthly =
    recurringMonthlyTotal(commitments.map((c) => ({ amount: c.amount, frequency: c.frequency }))) +
    recurringMonthlyTotal(subs.map((s) => ({ amount: s.amount, frequency: s.billing_cycle })));
  const pct = percentOfIncome(recurringMonthly, monthlyIncome);

  const [lender, setLender] = useState(""); const [principal, setPrincipal] = useState(""); const [emi, setEmi] = useState("");
  const [ckind, setCkind] = useState<(typeof KINDS)[number]>("emi"); const [camount, setCamount] = useState(""); const [cfreq, setCfreq] = useState<Period>("monthly");

  async function addLoan() {
    if (!lender.trim() || !principal) return;
    await insertRow("loans", { lender: lender.trim(), principal: fromMajor(Number(principal), base).amount, currency: base, interest_rate: 0, emi_amount: emi ? fromMajor(Number(emi), base).amount : null });
    setLender(""); setPrincipal(""); setEmi("");
  }
  async function addCommitment() {
    if (!camount) return;
    await insertRow("recurring_commitments", { kind: ckind, amount: fromMajor(Number(camount), base).amount, currency: base, frequency: cfreq });
    setCamount("");
  }

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <h1>{t("pages.loans", "Loans & Recurring")}</h1>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>Recurring commitments / month</div>
          <div style={{ fontSize: 30, fontFamily: "var(--font-serif)", fontWeight: 750 }}>{fmt(money(recurringMonthly, base), "en-US")}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="muted" style={{ fontSize: 13 }}>Of monthly income</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: Number.isFinite(pct) && pct > 50 ? "var(--negative)" : "var(--forest)" }}>
            {Number.isFinite(pct) ? `${pct.toFixed(0)}%` : "—"}
          </div>
          <div className="muted" style={{ fontSize: 12 }}>Income {fmt(money(monthlyIncome, base), "en-US")}</div>
        </div>
      </section>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }} className="dash-cols">
        <div style={{ display: "grid", gap: 12 }}>
          <h2>Loans</h2>
          {loans.map((l) => <LoanRow key={l.id} loan={l} />)}
          <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
            <FloatingInput label="Lender" value={lender} onChange={setLender} />
            <div style={{ display: "flex", gap: 8 }}>
              <FloatingInput label="Principal" inputMode="decimal" value={principal} onChange={(v) => setPrincipal(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
              <FloatingInput label="EMI" inputMode="decimal" value={emi} onChange={(v) => setEmi(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
            </div>
            <button className="btn" onClick={addLoan} disabled={!lender.trim() || !principal}>Add loan</button>
          </div>
        </div>

        <div style={{ display: "grid", gap: 12 }}>
          <h2>Recurring commitments</h2>
          {commitments.map((c) => <CommitmentRow key={c.id} c={c} />)}
          <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {KINDS.map((k) => <button key={k} className="chip" data-active={k === ckind} style={{ textTransform: "capitalize" }} onClick={() => setCkind(k)}>{k.replace("_", " ")}</button>)}
            </div>
            <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
              <FloatingInput label="Amount" inputMode="decimal" value={camount} onChange={(v) => setCamount(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
              <div style={{ display: "flex", gap: 6 }}>{CYCLES.map((c) => <button key={c} className="chip" data-active={c === cfreq} onClick={() => setCfreq(c)}>{c[0]!.toUpperCase()}</button>)}</div>
            </div>
            <button className="btn" onClick={addCommitment} disabled={!camount}>Add commitment</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function LoanRow({ loan }: { loan: Loan }) {
  const fmt = useMoneyFmt();
  const [editing, setEditing] = useState(false);
  const [lender, setLender] = useState(loan.lender ?? "");
  const [principal, setPrincipal] = useState(String(toMajor(money(loan.principal, loan.currency))));
  const [emi, setEmi] = useState(loan.emi_amount ? String(toMajor(money(loan.emi_amount, loan.currency))) : "");

  async function save() {
    await updateRow("loans", loan.id, {
      lender: lender.trim() || null,
      principal: fromMajor(Number(principal) || 0, loan.currency).amount,
      emi_amount: emi ? fromMajor(Number(emi), loan.currency).amount : null,
    });
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
        <FloatingInput label="Lender" value={lender} onChange={setLender} />
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label="Principal" inputMode="decimal" value={principal} onChange={(v) => setPrincipal(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
          <FloatingInput label="EMI" inputMode="decimal" value={emi} onChange={(v) => setEmi(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        </div>
        <div style={{ display: "flex", gap: 8 }}><button className="btn" onClick={save}>Save</button><button className="chip" onClick={() => setEditing(false)}>Cancel</button></div>
      </div>
    );
  }
  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between" }}>
      <div><strong>{loan.lender || "Loan"}</strong><div className="muted" style={{ fontSize: 12 }}>EMI {loan.emi_amount ? fmt(money(loan.emi_amount, loan.currency), "en-US") : "—"}</div></div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <span>{fmt(money(loan.principal, loan.currency), "en-US")}</span>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={() => softDelete("loans", loan.id)}>×</button>
      </div>
    </div>
  );
}

function CommitmentRow({ c }: { c: Commitment }) {
  const fmt = useMoneyFmt();
  const [editing, setEditing] = useState(false);
  const [kind, setKind] = useState<(typeof KINDS)[number]>(c.kind as (typeof KINDS)[number]);
  const [amount, setAmount] = useState(String(toMajor(money(c.amount, c.currency))));
  const [freq, setFreq] = useState<Period>(c.frequency);

  async function save() {
    await updateRow("recurring_commitments", c.id, {
      kind, amount: fromMajor(Number(amount) || 0, c.currency).amount, frequency: freq,
    });
    setEditing(false);
  }

  if (editing) {
    return (
      <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {KINDS.map((k) => <button key={k} className="chip" data-active={k === kind} style={{ textTransform: "capitalize" }} onClick={() => setKind(k)}>{k.replace("_", " ")}</button>)}
        </div>
        <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <FloatingInput label="Amount" inputMode="decimal" value={amount} onChange={(v) => setAmount(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
          <div style={{ display: "flex", gap: 6 }}>{CYCLES.map((cy) => <button key={cy} className="chip" data-active={cy === freq} onClick={() => setFreq(cy)}>{cy[0]!.toUpperCase()}</button>)}</div>
        </div>
        <div style={{ display: "flex", gap: 8 }}><button className="btn" onClick={save}>Save</button><button className="chip" onClick={() => setEditing(false)}>Cancel</button></div>
      </div>
    );
  }
  return (
    <div className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between" }}>
      <div><strong style={{ textTransform: "capitalize" }}>{c.kind.replace("_", " ")}</strong><div className="muted" style={{ fontSize: 12 }}>{fmt(money(c.amount, c.currency), "en-US")} / {c.frequency}</div></div>
      <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
        <span className="muted">{fmt(money(monthlyEquivalent(c.amount, c.frequency), c.currency), "en-US")}/mo</span>
        <button className="chip" onClick={() => setEditing(true)}>Edit</button>
        <button className="chip" onClick={() => softDelete("recurring_commitments", c.id)}>×</button>
      </div>
    </div>
  );
}
