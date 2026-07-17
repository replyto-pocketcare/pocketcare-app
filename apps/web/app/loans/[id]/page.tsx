"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { amortizationSchedule, emiDueDate, effectivePaidEmis } from "@pocketcare/finance";
import { useBaseCurrency, useAccountBalances } from "../../../src/hooks";
import { getRepositories } from "../../../src/powersync";
import { updateRow, softDelete } from "../../../src/write";
import { useMoneyFmt } from "../../../src/ui/Money";
import { FloatingInput } from "../../../src/ui/FloatingInput";
import { Modal } from "../../../src/ui/Modal";
import { useConfirm } from "../../../src/ui/Confirm";

interface Loan {
  id: string; lender: string; principal: number; currency: string;
  interest_rate: number | null; tenure_months: number | null; emi_amount: number | null;
  start_date: string | null; emis_paid: number | null; emi_payments: string | null;
  emi_due_day: number | null; auto_mark_paid: number | null;
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
const fmtDate = (iso: string | null) => (iso ? new Date(iso + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short", year: "numeric" }) : "—");
const fmtDateShort = (iso: string | null) => (iso ? new Date(iso + "T00:00:00").toLocaleDateString(undefined, { day: "numeric", month: "short" }) : "—");

export default function LoanDetailPage() {
  const { id } = useParams<{ id: string }>();
  const base = useBaseCurrency();
  const fmt = useMoneyFmt();
  const confirm = useConfirm();
  const { data: rows = [], isLoading } = useQuery<Loan>("SELECT * FROM loans WHERE id = ? AND deleted_at IS NULL", [id]);
  const loan = rows[0];
  const [editing, setEditing] = useState(false);
  const [payFor, setPayFor] = useState<{ month: number; due: string | null } | null>(null);

  if (isLoading) return <div className="muted">Loading…</div>;
  if (!loan) return <div className="card" style={{ padding: 24 }}>This loan no longer exists.</div>;

  const cur = loan.currency || base;
  const tenure = loan.tenure_months ?? 0;
  const emi = loan.emi_amount ?? 0;
  const dueDay = loan.emi_due_day ?? null;
  const autoMark = (loan.auto_mark_paid ?? 0) === 1;
  const schedule = emi > 0 ? amortizationSchedule(loan.principal, loan.interest_rate ?? 0, emi, tenure || 600) : [];
  const totalInterest = schedule.reduce((s, r) => s + r.interest, 0);
  const hasInterest = (loan.interest_rate ?? 0) > 0;
  const totalEmis = tenure || schedule.length;

  // Manual paid map is the source of truth; fall back to the emis_paid count
  // (first N marked) for loans created before per-EMI tracking existed.
  const manual = parsePaid(loan.emi_payments);
  if (Object.keys(manual).length === 0 && (loan.emis_paid ?? 0) > 0) {
    for (let m = 1; m <= (loan.emis_paid ?? 0); m++) manual[m] = "";
  }
  // Effective paid = manual ∪ (auto-mark ? past-due). Auto ones are DERIVED
  // (never written), so turning the toggle off instantly reverts them.
  const effective = effectivePaidEmis(Object.keys(manual).map(Number), totalEmis, {
    autoMark, startIso: loan.start_date, dueDay, asOfIso: todayIso(),
  });
  const isManual = (m: number) => m in manual;
  const isPaid = (m: number) => effective.has(m);
  const emisPaid = effective.size;
  const remaining = totalEmis ? Math.max(0, totalEmis - emisPaid) : null;
  const nextUnpaid = schedule.find((r) => !isPaid(r.month))?.month ?? null;
  const nextEmiDue = nextUnpaid ? emiDueDate(loan.start_date, dueDay, nextUnpaid) : null;

  async function setManualPaid(month: number, paidOn: string | null) {
    const next = { ...manual };
    if (paidOn) next[month] = paidOn; else delete next[month];
    const clean: Record<string, string> = {};
    for (const [k, v] of Object.entries(next)) clean[k] = v || todayIso();
    await updateRow("loans", loan!.id, { emi_payments: JSON.stringify(clean), emis_paid: Object.keys(clean).length });
  }

  async function toggleAutoMark() {
    await updateRow("loans", loan!.id, { auto_mark_paid: autoMark ? 0 : 1 });
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
          <div className="muted" style={{ fontSize: 12 }}>Next EMI due</div>
          <div style={{ fontSize: 20, fontWeight: 700 }}>{nextEmiDue && remaining !== 0 ? fmtDate(nextEmiDue) : "—"}</div>
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

      {/* Auto-mark policy */}
      {schedule.length > 0 && (
        <section className="card" style={{ padding: 16, display: "flex", gap: 14, flexWrap: "wrap", justifyContent: "space-between", alignItems: "center" }}>
          <div style={{ maxWidth: 460 }}>
            <div style={{ fontWeight: 650 }}>Auto-mark past-due EMIs as paid</div>
            <div className="muted" style={{ fontSize: 12 }}>
              {autoMark
                ? "EMIs are marked paid automatically once their due date passes. Turn off to mark each one yourself."
                : "You mark each EMI paid yourself. Turn on to auto-mark any EMI whose due date has passed."}
              {" "}Due on the {dueDay ? ordinal(dueDay) : (loan.start_date ? ordinal(new Date(loan.start_date + "T00:00:00").getDate()) : "—")} of each month.
            </div>
          </div>
          <button className={`btn ${autoMark ? "" : "ghost"}`} onClick={toggleAutoMark} role="switch" aria-checked={autoMark}>
            {autoMark ? "On" : "Off"}
          </button>
        </section>
      )}

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
                    const manualPaid = isManual(r.month);
                    const autoPaid = rowPaid && !manualPaid; // auto-marked, derived
                    const isNext = r.month === nextUnpaid;
                    const due = emiDueDate(loan.start_date, dueDay, r.month);
                    const paidOn = manual[r.month];
                    return (
                      <tr key={r.month} style={{ borderTop: "1px solid var(--border)", textAlign: "right",
                        background: isNext ? "var(--accent-ghost)" : "transparent", opacity: rowPaid ? 0.6 : 1 }}>
                        <td style={{ textAlign: "left", padding: "8px 14px" }}>{rowPaid ? "✓ " : ""}{r.month}</td>
                        <td style={{ padding: "8px 14px", color: "var(--text-2)" }}>{fmtDateShort(due)}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.emi, cur))}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.principal, cur))}</td>
                        <td style={{ padding: "8px 14px", color: hasInterest ? "var(--negative)" : "var(--text-3)" }}>{fmt(money(r.interest, cur))}</td>
                        <td style={{ padding: "8px 14px" }}>{fmt(money(r.balance, cur))}</td>
                        <td style={{ textAlign: "center", padding: "8px 14px", whiteSpace: "nowrap" }}>
                          {autoPaid ? (
                            <span className="chip" title={`Auto-marked — due ${fmtDate(due)}`} style={{ padding: "2px 8px", fontSize: 11, opacity: 0.85 }}>
                              Auto ✓
                            </span>
                          ) : manualPaid ? (
                            <button className="chip" title={paidOn ? `Paid on ${fmtDate(paidOn)} · click to undo` : "Paid · click to undo"} onClick={() => setManualPaid(r.month, null)} style={{ padding: "2px 8px", fontSize: 11 }}>
                              {paidOn ? fmtDateShort(paidOn) : "Paid"} ✓
                            </button>
                          ) : (
                            <button className="chip" onClick={() => setPayFor({ month: r.month, due })} style={{ padding: "2px 8px", fontSize: 11 }}>Mark paid</button>
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

      {payFor && (
        <MarkPaidDialog
          loan={loan}
          month={payFor.month}
          due={payFor.due}
          emiAmount={emi}
          currency={cur}
          onClose={() => setPayFor(null)}
          onConfirm={async (paidOn, accountId) => {
            await setManualPaid(payFor.month, paidOn);
            if (accountId && emi > 0) {
              await getRepositories().transactions.create({
                account_id: accountId,
                type: "expense",
                amount: money(emi, cur),
                description: `EMI #${payFor.month}${loan.lender ? ` — ${loan.lender}` : ""}`,
                occurred_at: new Date(paidOn + "T12:00:00").toISOString(),
              });
            }
            setPayFor(null);
          }}
        />
      )}
    </div>
  );
}

/** 1 → "1st", 2 → "2nd", … day-of-month ordinal. */
function ordinal(n: number): string {
  const s = ["th", "st", "nd", "rd"] as const, v = n % 100;
  const suffix = s[(v - 20) % 10] ?? s[v] ?? "th";
  return `${n}${suffix}`;
}

function Card({ label, value }: { label: string; value: string }) {
  return (
    <div className="card" style={{ padding: 16, display: "grid", gap: 4 }}>
      <span className="eyebrow">{label}</span>
      <div style={{ fontSize: 20, fontWeight: 720, letterSpacing: "-0.01em" }}>{value}</div>
    </div>
  );
}

/** Mark an EMI paid: pick the paid date, and optionally post an expense from a
 *  funding account (checklist follow-up — EMI mark-paid → ledger transaction). */
function MarkPaidDialog({ loan, month, due, emiAmount, currency, onClose, onConfirm }: {
  loan: Loan; month: number; due: string | null; emiAmount: number; currency: string;
  onClose: () => void; onConfirm: (paidOn: string, accountId: string | null) => Promise<void>;
}) {
  const fmt = useMoneyFmt();
  const accounts = useAccountBalances();
  const [paidOn, setPaidOn] = useState(due && due <= todayIso() ? due : todayIso());
  const [accountId, setAccountId] = useState<string>("");
  const [saving, setSaving] = useState(false);
  const canRecord = emiAmount > 0;

  return (
    <Modal open onClose={onClose}>
      <div style={{ display: "grid", gap: 14 }}>
        <div>
          <h2 style={{ margin: 0 }}>Mark EMI #{month} paid</h2>
          {due && <p className="muted" style={{ margin: "4px 0 0", fontSize: 13 }}>Due {fmtDate(due)}{emiAmount > 0 ? ` · ${fmt(money(emiAmount, currency))}` : ""}</p>}
        </div>
        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Paid on
          <input className="input" type="date" max={todayIso()} value={paidOn} onChange={(e) => setPaidOn(e.target.value)} />
        </label>
        {canRecord && (
          <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4 }}>Also record a payment (optional)
            <select className="input" value={accountId} onChange={(e) => setAccountId(e.target.value)}>
              <option value="">Don’t record a transaction</option>
              {accounts.map(({ account, balance }) => (
                <option key={account.id} value={account.id}>{account.name} · {fmt(balance)}</option>
              ))}
            </select>
          </label>
        )}
        {accountId && <p className="muted" style={{ margin: 0, fontSize: 12 }}>Posts a {fmt(money(emiAmount, currency))} expense from the selected account on {fmtDate(paidOn)}.</p>}
        <div style={{ display: "flex", gap: 8, justifyContent: "flex-end", marginTop: 4 }}>
          <button className="btn ghost" onClick={onClose} disabled={saving}>Cancel</button>
          <button className="btn" disabled={saving || !paidOn} onClick={async () => { setSaving(true); try { await onConfirm(paidOn, accountId || null); } finally { setSaving(false); } }}>
            {saving ? "Saving…" : accountId ? "Mark paid & record" : "Mark paid"}
          </button>
        </div>
      </div>
    </Modal>
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
  const [dueDay, setDueDay] = useState(loan.emi_due_day != null ? String(loan.emi_due_day) : "");

  async function save() {
    const dd = dueDay ? Math.min(31, Math.max(1, Number(dueDay))) : null;
    await updateRow("loans", loan.id, {
      lender: lender.trim() || null,
      principal: fromMajor(Number(principal) || 0, cur).amount,
      emi_amount: emi ? fromMajor(Number(emi), cur).amount : null,
      interest_rate: rate ? Number(rate) : 0,
      tenure_months: tenure ? Number(tenure) : null,
      start_date: start || null,
      emi_due_day: dd,
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
        <label className="muted" style={{ fontSize: 12, display: "grid", gap: 4, flex: 1, minWidth: 150 }}>Loan started on
          <input className="input" type="date" value={start} onChange={(e) => setStart(e.target.value)} />
        </label>
        <FloatingInput label="EMI due day (1–31)" inputMode="numeric" value={dueDay} onChange={(v) => setDueDay(v.replace(/\D/g, "").slice(0, 2))} style={{ width: 150 }} />
      </div>
      <p className="muted" style={{ fontSize: 12, margin: 0 }}>Leave the due day blank to use the start date’s day. EMIs already paid can be marked individually in the schedule.</p>
      <div style={{ display: "flex", gap: 8 }}>
        <button className="btn" onClick={save}>Save</button>
        <button className="btn ghost" onClick={onDone}>Cancel</button>
      </div>
    </div>
  );
}
