"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { money, fromMajor } from "@pocketcare/money";
import { monthlyEquivalent } from "@pocketcare/finance";
import { useBaseCurrency, useConvert } from "../../src/hooks";
import { insertRow } from "../../src/write";
import { useMoneyFmt } from "../../src/ui/Money";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { Modal } from "../../src/ui/Modal";

interface Loan {
  id: string; lender: string; principal: number; currency: string;
  emi_amount: number | null; tenure_months: number | null; emis_paid: number | null; interest_rate: number | null;
}

export default function LoansPage() {
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const conv = useConvert();
  const { data: loans = [] } = useQuery<Loan>("SELECT id, lender, principal, currency, emi_amount, tenure_months, emis_paid, interest_rate FROM loans WHERE deleted_at IS NULL ORDER BY created_at");
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
            const paid = l.emis_paid ?? 0;
            const tenure = l.tenure_months ?? 0;
            return (
              <Link key={l.id} href={`/loans/${l.id}`} className="card lift" style={{ padding: 16, display: "grid", gap: 6, color: "inherit" }}>
                <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", gap: 8 }}>
                  <strong>{l.lender || "Loan"}</strong>
                  <span style={{ fontWeight: 650 }}>{l.emi_amount ? fmt(conv(money(l.emi_amount, l.currency || base))) : "—"}<span className="muted" style={{ fontSize: 11, fontWeight: 400 }}> /mo</span></span>
                </div>
                <div className="muted" style={{ fontSize: 12 }}>Principal {fmt(conv(money(l.principal, l.currency || base)))}{l.interest_rate ? ` · ${l.interest_rate}% p.a.` : ""}</div>
                {tenure > 0 && (
                  <>
                    <div style={{ height: 6, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
                      <div style={{ width: `${Math.min(100, (paid / tenure) * 100)}%`, height: "100%", background: "var(--accent)" }} />
                    </div>
                    <div className="muted" style={{ fontSize: 11 }}>{paid} / {tenure} EMIs paid · view schedule →</div>
                  </>
                )}
                {tenure === 0 && <div className="muted" style={{ fontSize: 11 }}>view schedule →</div>}
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
  const [lender, setLender] = useState("");
  const [principal, setPrincipal] = useState("");
  const [emi, setEmi] = useState("");
  const [tenure, setTenure] = useState("");
  const [rate, setRate] = useState("");
  const [start, setStart] = useState(new Date().toISOString().slice(0, 10));
  const [paid, setPaid] = useState("0");

  async function save() {
    if (!lender.trim() && !principal) return;
    await insertRow("loans", {
      lender: lender.trim(), currency: base,
      principal: principal ? fromMajor(Number(principal), base).amount : 0,
      emi_amount: emi ? fromMajor(Number(emi), base).amount : null,
      interest_rate: rate ? Number(rate) : 0,
      tenure_months: tenure ? Number(tenure) : null,
      start_date: start || null,
      emis_paid: Number(paid) || 0,
    });
    onClose();
  }

  return (
    <Modal open onClose={onClose}>
      <div style={{ display: "grid", gap: 12 }}>
        <h2 style={{ margin: 0 }}>Add loan</h2>
        <FloatingInput label="Lender" value={lender} onChange={setLender} />
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label={`Principal (${base})`} group currency={base} value={principal} onChange={setPrincipal} style={{ flex: 1, minWidth: 130 }} />
          <FloatingInput label={`Monthly EMI (${base})`} group currency={base} value={emi} onChange={setEmi} style={{ flex: 1, minWidth: 130 }} />
        </div>
        <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
          <FloatingInput label="Tenure (months)" inputMode="numeric" value={tenure} onChange={(v) => setTenure(v.replace(/\D/g, ""))} style={{ flex: 1, minWidth: 120 }} />
          <FloatingInput label="Interest % p.a. (optional)" inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1, minWidth: 120 }} />
          <FloatingInput label="EMIs already paid" inputMode="numeric" value={paid} onChange={(v) => setPaid(v.replace(/\D/g, ""))} style={{ width: 130 }} />
        </div>
        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>EMIs started on
          <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
          <button className="btn ghost" onClick={onClose}>Cancel</button>
          <button className="btn" onClick={save} disabled={!lender.trim() && !principal}>Add</button>
        </div>
      </div>
    </Modal>
  );
}
