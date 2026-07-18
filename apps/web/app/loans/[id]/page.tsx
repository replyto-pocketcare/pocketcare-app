"use client";

import { useState } from "react";
import { useParams } from "next/navigation";
import { useQuery } from "@powersync/react";
import { money, fromMajor, toMajor } from "@pocketcare/money";
import { amortizationSchedule, emiDueDate, effectivePaidEmis, emiFromPrincipal } from "@pocketcare/finance";
import { AmountInput } from "../../../src/ui/AmountInput";
import { useBaseCurrency, useAccountBalances } from "../../../src/hooks";
import { getRepositories } from "../../../src/powersync";
import { updateRow, softDelete } from "../../../src/write";
import { useMoneyFmt } from "../../../src/ui/Money";
import { FloatingInput } from "../../../src/ui/FloatingInput";
import { Modal } from "../../../src/ui/Modal";
import { useConfirm } from "../../../src/ui/Confirm";
import { Pill, Field, EmiIcon } from "../../../src/loans/ui";

interface Loan {
  id: string; lender: string; principal: number; currency: string;
  interest_rate: number | null; tenure_months: number | null; emi_amount: number | null;
  start_date: string | null; emis_paid: number | null; emi_payments: string | null;
  emi_due_day: number | null; auto_mark_paid: number | null;
  rate_type: string | null; emi_amounts: string | null;
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

/** Parse the emi_amounts JSON map { emiNo: amountMinor } (variable-rate loans). */
function parseAmounts(json: string | null): Record<number, number> {
  if (!json) return {};
  try {
    const obj = JSON.parse(json) as Record<string, number>;
    const out: Record<number, number> = {};
    for (const [k, v] of Object.entries(obj)) if (typeof v === "number" && v > 0) out[Number(k)] = v;
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
  const isVariable = loan.rate_type === "variable";
  const schedule = !isVariable && emi > 0 ? amortizationSchedule(loan.principal, loan.interest_rate ?? 0, emi, tenure || 600) : [];
  const totalInterest = schedule.reduce((s, r) => s + r.interest, 0);
  const hasInterest = (loan.interest_rate ?? 0) > 0;

  // Manual paid map is the source of truth; fall back to the emis_paid count
  // (first N marked) for loans created before per-EMI tracking existed.
  const manual = parsePaid(loan.emi_payments);
  if (Object.keys(manual).length === 0 && (loan.emis_paid ?? 0) > 0) {
    for (let m = 1; m <= (loan.emis_paid ?? 0); m++) manual[m] = "";
  }
  const amounts = parseAmounts(loan.emi_amounts); // variable-rate per-month EMIs

  const knownMax = Math.max(0, ...Object.keys(amounts).map(Number), ...Object.keys(manual).map(Number));
  const totalEmis = tenure || (isVariable ? knownMax : schedule.length);
  // Variable loans show a month-by-month EMI list (user-entered amounts).
  const variableMonths = isVariable ? Array.from({ length: Math.max(totalEmis, knownMax, 1) }, (_, i) => i + 1) : [];

  // Effective paid = manual ∪ (auto-mark ? past-due). Auto ones are DERIVED
  // (never written), so turning the toggle off instantly reverts them.
  const effective = effectivePaidEmis(Object.keys(manual).map(Number), totalEmis, {
    autoMark, startIso: loan.start_date, dueDay, asOfIso: todayIso(),
  });
  const isManual = (m: number) => m in manual;
  const isPaid = (m: number) => effective.has(m);
  const emisPaid = effective.size;
  const remaining = totalEmis ? Math.max(0, totalEmis - emisPaid) : null;
  const monthsList = isVariable ? variableMonths : schedule.map((r) => r.month);
  const nextUnpaid = monthsList.find((m) => !isPaid(m)) ?? null;
  const nextEmiDue = nextUnpaid ? emiDueDate(loan.start_date, dueDay, nextUnpaid) : null;
  const variablePaidTotal = variableMonths.filter(isPaid).reduce((s, m) => s + (amounts[m] ?? 0), 0);

  async function setAmount(month: number, minor: number | null) {
    const next = { ...amounts };
    if (minor == null || minor <= 0) delete next[month]; else next[month] = minor;
    await updateRow("loans", loan!.id, { emi_amounts: JSON.stringify(next) });
  }

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
        <Card label="Monthly EMI" value={isVariable ? "Varies" : emi ? fmt(money(emi, cur)) : "—"} />
        <Card label={isVariable ? "Interest rate" : "Interest rate"} value={hasInterest ? `${loan.interest_rate}% p.a.${isVariable ? " · variable" : ""}` : (isVariable ? "Variable" : "—")} />
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
        {isVariable ? (
          <div>
            <div className="muted" style={{ fontSize: 12 }}>Paid so far</div>
            <div style={{ fontSize: 20, fontWeight: 700 }}>{fmt(money(variablePaidTotal, cur))}</div>
          </div>
        ) : hasInterest && (
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
      {(schedule.length > 0 || variableMonths.length > 0) && (
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

      {/* Variable-rate: month-by-month EMIs entered by the user */}
      {isVariable && (
        <section style={{ display: "grid", gap: 10 }}>
          <div className="eyebrow">Monthly EMIs · you enter each month’s amount</div>
          <div style={{ display: "grid", gap: 10 }}>
            {variableMonths.map((m) => {
              const rowPaid = isPaid(m);
              const manualPaid = isManual(m);
              const isNext = m === nextUnpaid;
              const due = emiDueDate(loan.start_date, dueDay, m);
              const paidOn = manual[m];
              return (
                <div key={m} className="card" style={{ padding: 0, overflow: "hidden", borderColor: isNext ? "var(--accent-soft)" : undefined }}>
                  <div style={{ padding: "12px 14px", display: "flex", alignItems: "center", gap: 10, background: isNext ? "var(--accent-ghost)" : "transparent" }}>
                    <EmiIcon state={rowPaid ? "paid" : "due"} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="muted" style={{ fontSize: 11 }}>{ordinal(m)} EMI</div>
                      <div style={{ fontWeight: 700, fontSize: 15 }}>{amounts[m] ? fmt(money(amounts[m]!, cur)) : "—"}</div>
                    </div>
                    <div style={{ display: "grid", gap: 3, justifyItems: "end" }}>
                      <EmiStatusPill rowPaid={rowPaid} manualPaid={manualPaid} due={due} onMark={() => setPayFor({ month: m, due })} onUnmark={() => setManualPaid(m, null)} />
                      <span className="muted" style={{ fontSize: 11 }}>{rowPaid ? `On ${fmtDateShort(paidOn || due)}` : `Due ${fmtDateShort(due)}`}</span>
                    </div>
                  </div>
                  <div style={{ borderTop: "1px solid var(--border)", padding: "10px 14px", display: "flex", justifyContent: "space-between", alignItems: "center", gap: 10 }}>
                    <span className="muted" style={{ fontSize: 11 }}>EMI this month</span>
                    <VariableAmountCell key={`amt-${m}-${amounts[m] ?? 0}`} value={amounts[m] ?? null} currency={cur} onSave={(minor) => setAmount(m, minor)} />
                  </div>
                </div>
              );
            })}
          </div>
          <p className="muted" style={{ fontSize: 12, margin: 0 }}>Variable-rate loans re-price over time, so enter each month’s EMI as your bank sets it. {tenure ? "" : "Add a tenure (edit) to lay out the full schedule."}</p>
        </section>
      )}

      {/* Amortization schedule (fixed-rate) — stacked cards, no horizontal scroll */}
      {!isVariable && (schedule.length > 0 ? (
        <section style={{ display: "grid", gap: 10 }}>
          <div className="eyebrow">Amortization schedule {hasInterest ? "· principal vs interest" : "· principal only"}</div>
          <div style={{ display: "grid", gap: 10 }}>
            {schedule.map((r) => {
              const rowPaid = isPaid(r.month);
              const manualPaid = isManual(r.month);
              const isNext = r.month === nextUnpaid;
              const due = emiDueDate(loan.start_date, dueDay, r.month);
              const paidOn = manual[r.month];
              return (
                <div key={r.month} className="card" style={{ padding: 0, overflow: "hidden", borderColor: isNext ? "var(--accent-soft)" : undefined }}>
                  <div style={{ padding: "12px 14px", display: "flex", alignItems: "center", gap: 10, background: isNext ? "var(--accent-ghost)" : "transparent" }}>
                    <EmiIcon state={rowPaid ? "paid" : "due"} />
                    <div style={{ flex: 1, minWidth: 0 }}>
                      <div className="muted" style={{ fontSize: 11 }}>{ordinal(r.month)} EMI</div>
                      <div style={{ fontWeight: 700, fontSize: 15 }}>{fmt(money(r.emi, cur))}</div>
                    </div>
                    <div style={{ display: "grid", gap: 3, justifyItems: "end" }}>
                      <EmiStatusPill rowPaid={rowPaid} manualPaid={manualPaid} due={due} onMark={() => setPayFor({ month: r.month, due })} onUnmark={() => setManualPaid(r.month, null)} />
                      <span className="muted" style={{ fontSize: 11 }}>{rowPaid ? `On ${fmtDateShort(paidOn || due)}` : `Due ${fmtDateShort(due)}`}</span>
                    </div>
                  </div>
                  <div style={{ borderTop: "1px solid var(--border)", padding: "10px 14px", display: "flex", justifyContent: "space-between", gap: 12 }}>
                    <Field label="Principal Amount" value={fmt(money(r.principal, cur))} />
                    {hasInterest
                      ? <Field label="Interest Amount" align="right" tone="var(--negative)" value={fmt(money(r.interest, cur))} />
                      : <Field label="Balance" align="right" value={fmt(money(r.balance, cur))} />}
                  </div>
                </div>
              );
            })}
          </div>
          {!hasInterest && <p className="muted" style={{ fontSize: 12, margin: 0 }}>Add an interest rate (edit) to see the principal-vs-interest split each month.</p>}
        </section>
      ) : (
        <div className="card" style={{ padding: 24, color: "var(--text-3)", fontSize: 13, textAlign: "center" }}>
          Add a monthly EMI (and tenure) to generate the amortization schedule.
        </div>
      ))}

      {payFor && (() => {
        const payAmount = isVariable ? (amounts[payFor.month] ?? 0) : emi;
        return (
          <MarkPaidDialog
            loan={loan}
            month={payFor.month}
            due={payFor.due}
            emiAmount={payAmount}
            currency={cur}
            onClose={() => setPayFor(null)}
            onConfirm={async (paidOn, accountId) => {
              await setManualPaid(payFor.month, paidOn);
              if (accountId && payAmount > 0) {
                await getRepositories().transactions.create({
                  account_id: accountId,
                  type: "expense",
                  amount: money(payAmount, cur),
                  description: `EMI #${payFor.month}${loan.lender ? ` — ${loan.lender}` : ""}`,
                  occurred_at: new Date(paidOn + "T12:00:00").toISOString(),
                });
              }
              setPayFor(null);
            }}
          />
        );
      })()}
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

/** Status pill for an EMI row: Paid (manual → tap to undo), Auto (derived), or Due (tap to mark paid). */
function EmiStatusPill({ rowPaid, manualPaid, due, onMark, onUnmark }: {
  rowPaid: boolean; manualPaid: boolean; due: string | null; onMark: () => void; onUnmark: () => void;
}) {
  if (rowPaid && !manualPaid) return <Pill tone="positive" title={`Auto-marked — due ${fmtDate(due)}`}>Auto ✓</Pill>;
  if (rowPaid) return <Pill tone="positive" onClick={onUnmark} title="Paid · tap to undo">Paid ✓</Pill>;
  return <Pill tone="amber" onClick={onMark} title="Tap to mark paid">Mark paid</Pill>;
}

/** Inline editable EMI amount for a variable-rate month; saves on blur.
 *  Keyed by its saved value in the parent, so it re-seeds when the value changes. */
function VariableAmountCell({ value, currency, onSave }: { value: number | null; currency: string; onSave: (minor: number | null) => void }) {
  const [raw, setRaw] = useState(value != null ? String(toMajor(money(value, currency))) : "");
  return (
    <AmountInput
      style={{ width: 120, textAlign: "right" }}
      currency={currency}
      placeholder="0"
      value={raw}
      ariaLabel="EMI this month"
      onChange={setRaw}
      onBlur={() => onSave(raw ? fromMajor(Number(raw), currency).amount : null)}
    />
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
  const fmt = useMoneyFmt();
  const cur = loan.currency;
  const [lender, setLender] = useState(loan.lender ?? "");
  const [principal, setPrincipal] = useState(String(toMajor(money(loan.principal, cur))));
  const [emi, setEmi] = useState(loan.emi_amount ? String(toMajor(money(loan.emi_amount, cur))) : "");
  const [emiTouched, setEmiTouched] = useState(false);
  const [rate, setRate] = useState(loan.interest_rate != null ? String(loan.interest_rate) : "");
  const [rateType, setRateType] = useState<"fixed" | "variable">(loan.rate_type === "variable" ? "variable" : "fixed");
  const [tenure, setTenure] = useState(loan.tenure_months != null ? String(loan.tenure_months) : "");
  const [start, setStart] = useState(loan.start_date ?? new Date().toISOString().slice(0, 10));
  const [dueDay, setDueDay] = useState(loan.emi_due_day != null ? String(loan.emi_due_day) : "");

  const principalMinor = fromMajor(Number(principal) || 0, cur).amount;
  const computedEmiMinor = rateType === "fixed" ? emiFromPrincipal(principalMinor, Number(rate) || 0, Number(tenure) || 0) : 0;
  const computedEmiMajor = computedEmiMinor ? String(toMajor(money(computedEmiMinor, cur))) : "";
  const emiValue = rateType === "variable" ? "" : (emiTouched ? emi : (emi || computedEmiMajor));

  async function save() {
    const dd = dueDay ? Math.min(31, Math.max(1, Number(dueDay))) : null;
    const emiToUse = rateType === "variable" ? null : (emiTouched ? emi : (emi || computedEmiMajor));
    await updateRow("loans", loan.id, {
      lender: lender.trim() || null,
      principal: principalMinor,
      emi_amount: emiToUse ? fromMajor(Number(emiToUse), cur).amount : null,
      interest_rate: rate ? Number(rate) : 0,
      tenure_months: tenure ? Number(tenure) : null,
      start_date: start || null,
      emi_due_day: dd,
      rate_type: rateType,
    });
    onDone();
  }

  return (
    <div style={{ display: "grid", gap: 14, maxWidth: 520 }} className="fade-up">
      <h1 style={{ margin: 0 }}>Edit loan</h1>
      <FloatingInput label="Lender" value={lender} onChange={setLender} />
      <div style={{ display: "grid", gap: 4 }}>
        <span className="muted" style={{ fontSize: 12 }}>Interest type</span>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="chip" data-active={rateType === "fixed"} onClick={() => setRateType("fixed")}>Fixed</button>
          <button className="chip" data-active={rateType === "variable"} onClick={() => setRateType("variable")}>Variable</button>
        </div>
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label={`Principal (${cur})`} group currency={cur} value={principal} onChange={setPrincipal} style={{ flex: 1 }} />
        <FloatingInput label="Tenure (months)" inputMode="numeric" value={tenure} onChange={(v) => setTenure(v.replace(/\D/g, ""))} style={{ flex: 1 }} />
      </div>
      <div style={{ display: "flex", gap: 8 }}>
        <FloatingInput label={rateType === "variable" ? "Current interest % p.a." : "Interest % p.a."} inputMode="decimal" value={rate} onChange={(v) => setRate(v.replace(/[^0-9.]/g, ""))} style={{ flex: 1 }} />
        {rateType === "fixed" && (
          <FloatingInput label={`Monthly EMI (${cur})`} group currency={cur} value={emiValue} onChange={(v) => { setEmi(v); setEmiTouched(true); }} style={{ flex: 1 }} />
        )}
      </div>
      {rateType === "fixed" ? (
        computedEmiMinor > 0 && <div className="muted" style={{ fontSize: 12, marginTop: -6 }}>Auto-calculated EMI: {fmt(money(computedEmiMinor, cur))}. <button className="chip" style={{ padding: "1px 8px", fontSize: 11 }} onClick={() => { setEmi(computedEmiMajor); setEmiTouched(true); }}>Use it</button></div>
      ) : (
        <div style={{ padding: "9px 12px", borderRadius: 10, fontSize: 12, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", color: "var(--text-2)" }}>
          Variable-rate loan — enter each month’s EMI on the loan’s schedule below. The single EMI field is disabled.
        </div>
      )}
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
