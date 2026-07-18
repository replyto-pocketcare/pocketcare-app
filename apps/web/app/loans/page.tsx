"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { effectivePaidEmis, emiFromPrincipal } from "@pocketcare/finance";
import { useBaseCurrency, useConvert } from "../../src/hooks";
import { insertRow } from "../../src/write";
import { useMoneyFmt } from "../../src/ui/Money";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { Modal } from "../../src/ui/Modal";
import { Pill, Field, loanRange } from "../../src/loans/ui";

interface Loan {
  id: string; lender: string; principal: number; currency: string;
  emi_amount: number | null; tenure_months: number | null; emis_paid: number | null; interest_rate: number | null;
  start_date: string | null; emi_payments: string | null; emi_due_day: number | null; auto_mark_paid: number | null;
  rate_type: string | null;
}

const todayIso = () => new Date().toISOString().slice(0, 10);

/** Effective paid-EMI count for a loan row (manual marks ∪ auto-marked past-due). */
function paidCount(l: Loan): number {
  const tenure = l.tenure_months ?? 0;
  let manual: number[] = [];
  try {
    const obj = l.emi_payments ? (JSON.parse(l.emi_payments) as Record<string, string>) : {};
    manual = Object.entries(obj).filter(([, v]) => v).map(([k]) => Number(k));
  } catch { /* ignore */ }
  if (manual.length === 0 && (l.emis_paid ?? 0) > 0) manual = Array.from({ length: l.emis_paid ?? 0 }, (_, i) => i + 1);
  return effectivePaidEmis(manual, tenure, {
    autoMark: (l.auto_mark_paid ?? 0) === 1, startIso: l.start_date, dueDay: l.emi_due_day, asOfIso: todayIso(),
  }).size;
}

export default function LoansPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const { data: loans = [] } = useQuery<Loan>("SELECT id, lender, principal, currency, emi_amount, tenure_months, emis_paid, interest_rate, start_date, emi_payments, emi_due_day, auto_mark_paid, rate_type FROM loans WHERE deleted_at IS NULL ORDER BY created_at");
  const [adding, setAdding] = useState(false);

  const totalEmi = loans.reduce((s, l) => s + (l.emi_amount ? conv(money(l.emi_amount, l.currency || base)).amount : 0), 0);

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>Loans</h1>
        <button className="btn" onClick={() => setAdding(true)}>+ Add loan</button>
      </div>

      {loans.length > 0 && (
        <section className="card" style={{ padding: 20, display: "flex", justifyContent: "space-between", alignItems: "baseline", flexWrap: "wrap", gap: 12 }}>
          <div>
            <div className="muted" style={{ fontSize: 13 }}>Total EMIs / month</div>
            <div style={{ fontSize: 30, fontWeight: 750 }}>{fmt(money(totalEmi, base))}</div>
          </div>
          <div className="muted" style={{ fontSize: 13 }}>{loans.length} loan{loans.length === 1 ? "" : "s"}</div>
        </section>
      )}

      {loans.length === 0 ? (
        <div className="card" style={{ padding: 24, textAlign: "center", display: "grid", gap: 10, justifyItems: "center" }}>
          <div style={{ fontSize: 26 }}>≈</div>
          <h2 style={{ margin: 0 }}>No loans yet</h2>
          <p className="muted" style={{ margin: 0, maxWidth: 380 }}>Add a loan to track its EMIs, remaining balance, and a month-by-month amortization schedule.</p>
          <button className="btn" onClick={() => setAdding(true)}>+ Add your first loan</button>
        </div>
      ) : (
        <div className="list-grid">
          {loans.map((l) => {
            const paid = paidCount(l);
            const tenure = l.tenure_months ?? 0;
            const remaining = tenure ? Math.max(0, tenure - paid) : null;
            const closed = tenure > 0 && remaining === 0;
            const range = loanRange(l.start_date, tenure);
            return (
              <Link key={l.id} href={`/loans/${l.id}`} className="card lift" style={{ padding: 0, overflow: "hidden", color: "inherit", display: "block" }}>
                <div style={{ padding: "14px 16px", display: "grid", gap: 10 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "flex-start", gap: 8 }}>
                    <strong style={{ fontSize: 15, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{l.lender || "Loan"}</strong>
                    <Pill tone={closed ? "muted" : "positive"}>{closed ? "Closed" : "Active"}</Pill>
                  </div>
                  <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
                    <span className="muted" style={{ fontSize: 12 }}>{range || (l.interest_rate ? `${l.interest_rate}% p.a.` : "—")}</span>
                    <span style={{ fontSize: 12.5, fontWeight: 600 }}>{tenure ? `${paid}/${tenure} EMI Paid` : `${paid} paid`}</span>
                  </div>
                  {tenure > 0 && (
                    <div style={{ height: 6, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
                      <div style={{ width: `${Math.min(100, (paid / tenure) * 100)}%`, height: "100%", background: closed ? "var(--positive)" : "var(--accent)" }} />
                    </div>
                  )}
                </div>
                <div style={{ borderTop: "1px solid var(--border)", padding: "10px 16px", display: "flex", justifyContent: "space-between", gap: 12 }}>
                  <Field label="Loan Amount" value={fmt(conv(money(l.principal, l.currency || base)))} />
                  <Field label="EMI Amount" align="right" value={l.emi_amount ? fmt(conv(money(l.emi_amount, l.currency || base))) : (l.rate_type === "variable" ? "Varies" : "—")} />
                </div>
              </Link>
            );
          })}
        </div>
      )}

      {adding && <AddLoan base={base} onClose={() => setAdding(false)} />}
    </div>
  );
}

function AddLoan({ base, onClose }: { base: string; onClose: () => void }) {
  const fmt = useMoneyFmt();
  const [lender, setLender] = useState("");
  const [principal, setPrincipal] = useState("");
  const [emi, setEmi] = useState("");
  const [emiTouched, setEmiTouched] = useState(false);
  const [tenure, setTenure] = useState("");
  const [rate, setRate] = useState("");
  const [rateType, setRateType] = useState<"fixed" | "variable">("fixed");
  const [start, setStart] = useState(new Date().toISOString().slice(0, 10));
  const [dueDay, setDueDay] = useState("");
  const [autoMark, setAutoMark] = useState(false);

  // Fixed loans: derive the EMI from principal/rate/tenure (user can override).
  const principalMinor = principal ? fromMajor(Number(principal), base).amount : 0;
  const computedEmiMinor = rateType === "fixed" ? emiFromPrincipal(principalMinor, Number(rate) || 0, Number(tenure) || 0) : 0;
  const computedEmiMajor = computedEmiMinor ? String(toMajor(money(computedEmiMinor, base))) : "";
  const emiValue = rateType === "variable" ? "" : (emiTouched ? emi : computedEmiMajor);

  async function save() {
    if (!lender.trim() && !principal) return;
    const dd = dueDay ? Math.min(31, Math.max(1, Number(dueDay))) : null;
    const emiToUse = rateType === "variable" ? null : (emiTouched ? emi : computedEmiMajor);
    await insertRow("loans", {
      lender: lender.trim(), currency: base,
      principal: principalMinor,
      emi_amount: emiToUse ? fromMajor(Number(emiToUse), base).amount : null,
      interest_rate: rate ? Number(rate) : 0,
      tenure_months: tenure ? Number(tenure) : null,
      start_date: start || null,
      emi_due_day: dd,
      auto_mark_paid: autoMark ? 1 : 0,
      rate_type: rateType,
      emis_paid: 0,
    });
    onClose();
  }

  return (
    <Modal open onClose={onClose}>
      <div style={{ display: "grid", gap: 12 }}>
        <h2 style={{ margin: 0 }}>Add loan</h2>
        <FloatingInput label="Lender" value={lender} onChange={setLender} />

        {/* Interest type */}
        <div style={{ display: "grid", gap: 4 }}>
          <span className="muted" style={{ fontSize: 12 }}>Interest type</span>
          <div style={{ display: "flex", gap: 6 }}>
            <button className="chip" data-active={rateType === "fixed"} onClick={() => setRateType("fixed")}>Fixed</button>
            <button className="chip" data-active={rateType === "variable"} onClick={() => setRateType("variable")}>Variable</button>
          </div>
        </div>

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label={`Principal (${base})`} group currency={base} value={principal} onChange={setPrincipal} style={{ flex: 1, minWidth: 130 }} />
          <FloatingInput label="Tenure (months)" inputMode="numeric" value={tenure} onChange={(v) => setTenure(v.replace(/\D/g, ""))} style={{ flex: 1, minWidth: 120 }} />
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label={rateType === "variable" ? "Current interest % p.a." : "Interest % p.a."} inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1, minWidth: 120 }} />
          {rateType === "fixed" && (
            <FloatingInput label={`Monthly EMI (${base})`} group currency={base} value={emiValue} onChange={(v) => { setEmi(v); setEmiTouched(true); }} style={{ flex: 1, minWidth: 130 }} />
          )}
        </div>
        {rateType === "fixed" ? (
          computedEmiMinor > 0 && (
            <div className="muted" style={{ fontSize: 12, marginTop: -4 }}>
              {emiTouched ? <>Auto-calculated EMI was {fmt(money(computedEmiMinor, base))}. <button className="chip" style={{ padding: "1px 8px", fontSize: 11 }} onClick={() => { setEmiTouched(false); setEmi(""); }}>Use it</button></> : "EMI auto-calculated from principal, rate and tenure — edit it to override."}
            </div>
          )
        ) : (
          <div style={{ padding: "9px 12px", borderRadius: 10, fontSize: 12, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", color: "var(--text-2)" }}>
            Variable-rate EMIs change over time and can’t be auto-calculated, so we’ll ask you to <strong style={{ color: "var(--text)" }}>enter each month’s EMI</strong> on the loan’s page.
          </div>
        )}
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", alignItems: "flex-end" }}>
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, flex: 1, minWidth: 150 }}>Loan started on
            <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
          </label>
          <FloatingInput label="EMI due day (1–31)" inputMode="numeric" value={dueDay} onChange={(v) => setDueDay(v.replace(/\D/g, "").slice(0, 2))} style={{ width: 150 }} />
        </div>
        <label style={{ display: "flex", gap: 8, alignItems: "flex-start", fontSize: 13, cursor: "pointer" }}>
          <input type="checkbox" checked={autoMark} onChange={(e) => setAutoMark(e.target.checked)} style={{ marginTop: 3 }} />
          <span>Auto-mark EMIs as paid on their due date<br /><span className="muted" style={{ fontSize: 12 }}>Otherwise you mark each EMI paid yourself. You can change this later.</span></span>
        </label>
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
          <button className="btn ghost" onClick={onClose}>Cancel</button>
          <button className="btn" onClick={save} disabled={!lender.trim() && !principal}>Add</button>
        </div>
      </div>
    </Modal>
  );
}
