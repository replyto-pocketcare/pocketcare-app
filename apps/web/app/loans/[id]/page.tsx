"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { amortizationSchedule } from "@pocketcare/finance";
import { useBaseCurrency } from "../../../src/hooks";
import { updateRow, softDelete } from "../../../src/write";
import { useMoneyFmt } from "../../../src/ui/Money";
import { FloatingInput } from "../../../src/ui/FloatingInput";
import { useConfirm } from "../../../src/ui/Confirm";

interface Loan {
  id: string; lender: string; principal: number; currency: string;
  interest_rate: number | null; tenure_months: number | null; emi_amount: number | null;
  start_date: string | null; emis_paid: number | null; emi_payments: string | null;
}

/** Parse the emi_payments JSON map { emiNo: paidOnISO }. */
function parsePaid(json: string | null): Record<number, string> {
  if (!json) return {};
  try {
    const obj = JSON.parse(json) as Record<string, string>;
    const out: Record<number, string> = {};
    for (const [k, v] of Object.entries(obj)) if (v) out[Number(k)] = v;
    return out;
  } catch { return {}; }
}

const todayIso = () => new Date().toISOString().slice(0, 10);

/** Add whole months to a date, clamping the day. */
function addMonths(iso: string | null, n: number): Date | null {
  if (!iso) return null;
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return null;
  const nd = new Date(d);
  nd.setMonth(nd.getMonth() + n);
  return nd;
}

export default function LoanDetailPage() {
  const { id } = useParams<{ id: string }>();
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const { data: rows = [], isLoading } = useQuery<Loan>("SELECT * FROM loans WHERE id = ? AND deleted_at IS NULL", [id]);
  const loan = rows[0];
  const [editing, setEditing] = useState(false);

  if (isLoading) return <div className="muted">Loading…</div>;
  if (!loan) return <div className="card" style={{ padding: 24 }}>This loan no longer exists.</div>;

  const cur = loan.currency || base;
  const tenure = loan.tenure_months ?? 0;
  const emi = loan.emi_amount ?? 0;
  const schedule = emi > 0 ? amortizationSchedule(loan.principal, loan.interest_rate ?? 0, emi, tenure || 600) : [];
  const totalInterest = schedule.reduce((s, r) => s + r.interest, 0);
  const hasInterest = (loan.interest_rate ?? 0) > 0;

  // Per-EMI paid map is the source of truth; fall back to the emis_paid count
  // (first N marked) for loans created before per-EMI tracking existed.
  const paid = parsePaid(loan.emi_payments);
  if (Object.keys(paid).length === 0 && (loan.emis_paid ?? 0) > 0) {
    for (let m = 1; m <= (loan.emis_paid ?? 0); m++) paid[m] = "";
  }
  const isPaid = (m: number) => m in paid;
  const emisPaid = Object.keys(paid).length;
  const totalEmis = tenure || schedule.length;
  const remaining = totalEmis ? Math.max(0, totalEmis - emisPaid) : null;
  const nextUnpaid = schedule.find((r) => !isPaid(r.month))?.month ?? null;
  const nextEmi = nextUnpaid ? addMonths(loan.start_date, nextUnpaid - 1) : null;

  async function togglePaid(month: number, on: boolean) {
    const next = { ...paid };
    if (on) next[month] = todayIso(); else delete next[month];
    const clean: Record<string, string> = {};
    for (const [k, v] of Object.entries(next)) clean[k] = v || todayIso();
    await updateRow("loans", loan!.id, { emi_payments: JSON.stringify(clean), emis_paid: Object.keys(clean).length });
  }

  if (editing) return <EditLoan loan={loan} onDone={() => setEditing(false)} />;

  return (
    <div style={{ display: "grid", gap: 20 }} className="fade-up">
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
        <h1 style={{ margin: 0 }}>{loan.lender || "Loan"}</h1>
        <div style={{ display: "flex", gap: 8 }}>
          <button className="btn ghost" onClick={() => setEditing(true)}>Edit</button>
          <button className="chip" onClick={async () => { if (await confirm({ title: "Delete this loan?", message: `“${loan.lender || "Loan"}” will be removed.`, confirmLabel: "Delete" })) { softDelete("loans", loan.id); history.back(); } }}>Delete</button>
        </div>
      </div>

      {/* Summary */}
      <div className="pc-hero">
        <Card label="Principal" value={fmt(money(loan.principal, cur))} />
        <Card label="Monthly EMI" value={emi ? fmt(money(emi, cur)) : "—"} />
        <Card label="Interest rate" value={hasInterest ? `${loan.interest_rate}% p.a.` : "—"} />
        <Card label="EMIs paid" value={tenure ? `${emisPaid} / ${tenure}` : String(emisPaid)} />
      </div>

      <section className="card" style={{ padding: 18, display: "flex", gap: 24, flexWrap: "wrap", justifyContent: "space-between", alignItems: "center" }}>
        <div>
          <div className="muted" style={{ fontSize: 12 }}>Next EMI</div>
          <div style={{ fontSize: 20, fontWeight: 700 }}>{nextEmi && remaining !== 0 ? nextEmi.toLocaleDateString() : "—"}</div>
        </div>
        <div>
          <div className="muted" style={{ fontSize: 12 }}>Remaining</div>
          <div style={{ fontSize: 20, fontWeight: 700 }}>{remaining != null ? `${remaining} EMIs` : "—"}</div>
        </div>
        {hasInterest && (
          <div>
            <div className="muted" style={{ fontSize: 12 }}>Total interest (schedule)</div>
            <div style={{ fontSize: 20, fontWeight: 700, color: "var(--negative)" }}>{fmt(money(totalInterest, cur))}</div>
          </div>
        )}
        {tenure > 0 && (
          <div style={{ flex: 1, minWidth: 160 }}>
            <div style={{ height: 8, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
              <div style={{ width: `${Math.min(100, (emisPaid / tenure) * 100)}%`, height: "100%", background: "var(--accent)" }} />
            </div>
          </div>
        )}
      </section>

      {/* Amortization schedule */}
      {schedule.length > 0 ? (
        <section style={{ display: "grid", gap: 10 }}>
          <div className="eyebrow">Amortization schedule {hasInterest ? "· principal vs interest" : "· principal only"}</div>
          <div className="card" style={{ padding: 0, overflow: "hidden" }}>
            <div style={{ overflowX: "auto" }}>
              <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 13, minWidth: 460 }}>
                <thead>
                  <tr style={{ textAlign: "right", color: "var(--text-2)" }}>
                    <th style={{ textAlign: "left", padding: "10px 14px", fontWeight: 600 }}>#</th>
                    <th style={{ padding: "10px 14px", fontWeight: 600 }}>Due</th>
                    <th style={{ padding: "10px 14px", fontWeight: 600 }}>EMI</th>
                    <th style={{ padding: "10px 14px", fontWeight: 600 }}>Principal</th>
                    <th style={{ padding: "10px 14px", fontWeight: 600 }}>Interest</th>
                    <th style={{ padding: "10px 14px", fontWeight: 600 }}>Balance</th>
                    <th style={{ textAlign: "center", padding: "10px 14px", fontWeight: 600 }}>Paid</th>
                  </tr>
                </thead>
                <tbody>
                  {schedule.map((r) => {
                    const rowPaid = isPaid(r.month);
                    const isNext = r.month === nextUnpaid;
                    const due = addMonths(loan.start_date, r.month - 1);
                    const paidOn = paid[r.month];
                    return (
                      <tr key={r.month} style={{ borderTop: "1px solid var(--border)", textAlign: "right",
                        background: isNext ? "var(--accent-ghost)" : "transparent", opacity: rowPaid ? 0.55 : 1 }}>
                        <td style={{ textAlign: "left", padding: "8px 14px" }}>{rowPaid ? "✓ " : ""}{r.month}</td>
                        <td style={{ padding: "8px 14px", color: "var(--text-2)" }}>{due ? due.toLocaleDateString(undefined, { month: "short", year: "2-digit" }) : "—"}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.emi, cur))}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.principal, cur))}</td>
                        <td style={{ padding: "8px 14px", color: hasInterest ? "var(--negative)" : "var(--text-3)" }}>{fmt(money(r.interest, cur))}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.balance, cur))}</td>
                        <td style={{ textAlign: "center", padding: "8px 14px", whiteSpace: "nowrap" }}>
                          {rowPaid ? (
                            <button className="chip" title={paidOn ? `Paid on ${new Date(paidOn).toLocaleDateString()}` : "Paid"} onClick={() => togglePaid(r.month, false)} style={{ padding: "2px 8px", fontSize: 11 }}>
                              {paidOn ? new Date(paidOn).toLocaleDateString(undefined, { day: "numeric", month: "short" }) : "Paid"} ✓
                            </button>
                          ) : (
                            <button className="chip" onClick={() => togglePaid(r.month, true)} style={{ padding: "2px 8px", fontSize: 11 }}>Mark paid</button>
                          )}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          </div>
          {!hasInterest && <p className="muted" style={{ fontSize: 12, margin: 0 }}>Add an interest rate (edit) to see the principal-vs-interest split each month.</p>}
        </section>
      ) : (
        <div className="card" style={{ padding: 24, color: "var(--text-3)", fontSize: 13, textAlign: "center" }}>
          Add a monthly EMI (and tenure) to generate the amortization schedule.
        </div>
      )}
    </div>
  );
}

function Card({ label, value }: { label: string; value: string }) {
  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 4 }}>
      <span className="eyebrow">{label}</span>
      <div style={{ fontSize: 20, fontWeight: 720, letterSpacing: "-0.01em" }}>{value}</div>
    </div>
  );
}

function EditLoan({ loan, onDone }: { loan: Loan; onDone: () => void }) {
  const cur = loan.currency;
  const [lender, setLender] = useState(loan.lender ?? "");
  const [principal, setPrincipal] = useState(String(toMajor(money(loan.principal, cur))));
  const [emi, setEmi] = useState(loan.emi_amount ? String(toMajor(money(loan.emi_amount, cur))) : "");
  const [rate, setRate] = useState(loan.interest_rate != null ? String(loan.interest_rate) : "");
  const [tenure, setTenure] = useState(loan.tenure_months != null ? String(loan.tenure_months) : "");
  const [start, setStart] = useState(loan.start_date ?? new Date().toISOString().slice(0, 10));
  const [paid, setPaid] = useState(String(loan.emis_paid ?? 0));

  async function save() {
    await updateRow("loans", loan.id, {
      lender: lender.trim() || null,
      principal: fromMajor(Number(principal) || 0, cur).amount,
      emi_amount: emi ? fromMajor(Number(emi), cur).amount : null,
      interest_rate: rate ? Number(rate) : 0,
      tenure_months: tenure ? Number(tenure) : null,
      start_date: start || null,
      emis_paid: Number(paid) || 0,
    });
    onDone();
  }

  return (
    <div style={{ display: "grid", gap: 14, maxWidth: 520 }} className="fade-up">
      <h1 style={{ margin: 0 }}>Edit loan</h1>
      <FloatingInput label="Lender" value={lender} onChange={setLender} />
      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label={`Principal (${cur})`} group currency={cur} value={principal} onChange={setPrincipal} style={{ flex: 1 }} />
        <FloatingInput label={`Monthly EMI (${cur})`} group currency={cur} value={emi} onChange={setEmi} style={{ flex: 1 }} />
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label="Interest % p.a. (optional)" inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        <FloatingInput label="Tenure (months)" inputMode="numeric" value={tenure} onChange={(v) => setTenure(v.replace(/\D/g, ""))} style={{ flex: 1 }} />
      </div>
      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, flex: 1, minWidth: 150 }}>EMIs started on
          <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <FloatingInput label="EMIs already paid" inputMode="numeric" value={paid} onChange={(v) => setPaid(v.replace(/\D/g, ""))} style={{ width: 150 }} />
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <button className="btn" onClick={save}>Save</button>
        <button className="btn ghost" onClick={onDone}>Cancel</button>
      </div>
    </div>
  );
}
