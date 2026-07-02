"use client";

import { useState } from "react";
import { useQuery } from "@powersync/react";
import { money, format, fromMajor } from "@pocketcare/money";
import { monthlyEquivalent, recurringMonthlyTotal, percentOfIncome } from "@pocketcare/finance";
import type { Period } from "@pocketcare/types";
import { useBaseCurrency } from "../../src/hooks";
import { insertRow, softDelete } from "../../src/write";

interface Loan { id: string; lender: string; principal: number; currency: string; emi_amount: number | null; }
interface Commitment { id: string; kind: string; amount: number; currency: string; frequency: Period; }

const KINDS = ["emi", "subscription", "recurring_expense"] as const;
const CYCLES: Period[] = ["daily", "weekly", "monthly", "yearly"];

export default function LoansPage() {
  const base = useBaseCurrency();
  const { data: loans = [] } = useQuery<Loan>("SELECT id, lender, principal, currency, emi_amount FROM loans WHERE deleted_at IS NULL");
  const { data: commitments = [] } = useQuery<Commitment>("SELECT id, kind, amount, currency, frequency FROM recurring_commitments WHERE deleted_at IS NULL");
  const { data: subs = [] } = useQuery<{ amount: number; billing_cycle: Period }>("SELECT amount, billing_cycle FROM subscriptions WHERE deleted_at IS NULL AND is_active = 1");

  // Monthly income estimate = income transactions this month.
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
      <h1>Loans & Recurring</h1>

      <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="muted" style={{ fontSize: 13 }}>Recurring commitments / month</div>
          <div style={{ fontSize: 30, fontWeight: 750 }}>{format(money(recurringMonthly, base), "en-US")}</div>
        </div>
        <div style={{ textAlign: "right" }}>
          <div className="muted" style={{ fontSize: 13 }}>Of monthly income</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: Number.isFinite(pct) && pct > 50 ? "var(--negative)" : "var(--forest)" }}>
            {Number.isFinite(pct) ? `${pct.toFixed(0)}%` : "—"}
          </div>
          <div className="muted" style={{ fontSize: 12 }}>Income {format(money(monthlyIncome, base), "en-US")}</div>
        </div>
      </section>

      <div style={{ display: "grid", gridTemplateColumns: "1fr 1fr", gap: 20 }}>
        <div style={{ display: "grid", gap: 12 }}>
          <h2>Loans</h2>
          {loans.map((l) => (
            <div key={l.id} className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between" }}>
              <div><strong>{l.lender || "Loan"}</strong><div className="muted" style={{ fontSize: 12 }}>EMI {l.emi_amount ? format(money(l.emi_amount, l.currency), "en-US") : "—"}</div></div>
              <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                <span>{format(money(l.principal, l.currency), "en-US")}</span>
                <button className="chip" onClick={() => softDelete("loans", l.id)}>×</button>
              </div>
            </div>
          ))}
          <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
            <input className="input" placeholder="Lender" value={lender} onChange={(e) => setLender(e.target.value)} />
            <div style={{ display: "flex", gap: 8 }}>
              <input className="input" inputMode="decimal" placeholder="Principal" value={principal} onChange={(e) => setPrincipal(e.target.value.replace(/[^0-9.]/g, ""))} />
              <input className="input" inputMode="decimal" placeholder="EMI" value={emi} onChange={(e) => setEmi(e.target.value.replace(/[^0-9.]/g, ""))} />
            </div>
            <button className="btn" onClick={addLoan} disabled={!lender.trim() || !principal}>Add loan</button>
          </div>
        </div>

        <div style={{ display: "grid", gap: 12 }}>
          <h2>Recurring commitments</h2>
          {commitments.map((c) => (
            <div key={c.id} className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between" }}>
              <div><strong style={{ textTransform: "capitalize" }}>{c.kind.replace("_", " ")}</strong><div className="muted" style={{ fontSize: 12 }}>{format(money(c.amount, c.currency), "en-US")} / {c.frequency}</div></div>
              <div style={{ display: "flex", gap: 10, alignItems: "center" }}>
                <span className="muted">{format(money(monthlyEquivalent(c.amount, c.frequency), c.currency), "en-US")}/mo</span>
                <button className="chip" onClick={() => softDelete("recurring_commitments", c.id)}>×</button>
              </div>
            </div>
          ))}
          <div className="card" style={{ padding: 16, display: "grid", gap: 8 }}>
            <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
              {KINDS.map((k) => <button key={k} className="chip" data-active={k === ckind} style={{ textTransform: "capitalize" }} onClick={() => setCkind(k)}>{k.replace("_", " ")}</button>)}
            </div>
            <div style={{ display: "flex", gap: 8 }}>
              <input className="input" inputMode="decimal" placeholder="Amount" value={camount} onChange={(e) => setCamount(e.target.value.replace(/[^0-9.]/g, ""))} />
              <div style={{ display: "flex", gap: 6 }}>{CYCLES.map((c) => <button key={c} className="chip" data-active={c === cfreq} onClick={() => setCfreq(c)}>{c[0].toUpperCase()}</button>)}</div>
            </div>
            <button className="btn" onClick={addCommitment} disabled={!camount}>Add commitment</button>
          </div>
        </div>
      </div>
    </div>
  );
}
