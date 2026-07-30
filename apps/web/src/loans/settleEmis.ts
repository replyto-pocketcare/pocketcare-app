"use client";

/**
 * Settling a credit-card bill can clear EMIs that were charged to that card.
 *
 * The charge and the payment are two different events (see `autoPost.ts`): the
 * EMI lands on the card when it falls due, and it becomes PAID when you settle
 * the bill that contains it. This finds the EMIs a given settlement plausibly
 * covers so the UI can ASK before changing anything.
 *
 * It deliberately does not act on its own. Marking a loan instalment paid is a
 * money-state change inferred from a payment amount, and a partial payment
 * would otherwise silently clear an EMI the user hasn't actually cleared.
 */

import { effectivePaidEmis, emiDueDate } from "@pocketcare/finance";
import { getDb } from "../powersync";
import { updateRow } from "../write";

export interface CoveredEmi {
  loanId: string;
  lender: string | null;
  emiNo: number;
  amount: number;   // minor units
  dueDate: string;  // YYYY-MM-DD
}

interface LoanRow {
  id: string; lender: string | null; emi_amount: number | null; tenure_months: number | null;
  start_date: string | null; emi_payments: string | null; emi_amounts: string | null;
  emi_due_day: number | null; auto_mark_paid: number | null;
}

const parseMap = (json: string | null): Record<string, unknown> => {
  if (!json) return {};
  try { const v = JSON.parse(json); return v && typeof v === "object" ? v : {}; } catch { return {}; }
};

/**
 * EMIs charged to `cardAccountId` that are due, not yet marked paid, and fit
 * inside `amountMinor` — oldest first.
 *
 * FIFO and bounded by the amount: paying half the bill shouldn't offer to clear
 * every instalment on the card. An EMI larger than the remaining headroom stops
 * the walk rather than being skipped, because clearing a later, smaller EMI
 * while an older one stays open would misrepresent the order things were paid.
 */
export async function findCoveredEmis(cardAccountId: string, amountMinor: number): Promise<CoveredEmi[]> {
  const db = getDb();
  if (!db || amountMinor <= 0) return [];

  const loans = await db.getAll<LoanRow>(
    `SELECT id, lender, emi_amount, tenure_months, start_date, emi_payments,
            emi_amounts, emi_due_day, auto_mark_paid
       FROM loans
      WHERE deleted_at IS NULL AND funding_account_id = ?`,
    [cardAccountId],
  );

  const candidates: CoveredEmi[] = [];
  for (const loan of loans) {
    const total = loan.tenure_months ?? 0;
    if (total <= 0) continue;

    const manual = Object.keys(parseMap(loan.emi_payments)).map(Number).filter(Number.isFinite);
    const manualSet = new Set(manual);
    // Due-ness ignores auto_mark_paid here: we want what's OWED, and only
    // explicitly-marked EMIs count as already settled.
    const due = effectivePaidEmis([], total, {
      autoMark: true,
      startIso: loan.start_date,
      dueDay: loan.emi_due_day,
    });
    const amounts = parseMap(loan.emi_amounts) as Record<string, number>;

    for (const n of due) {
      if (manualSet.has(n)) continue;
      const amount = Number(amounts[String(n)] ?? loan.emi_amount ?? 0);
      if (!Number.isFinite(amount) || amount <= 0) continue;
      // No start date → no schedule, so nothing is due. `emiDueDate` returns
      // null there rather than guessing a date.
      const dueDate = emiDueDate(loan.start_date, loan.emi_due_day, n);
      if (!dueDate) continue;
      candidates.push({ loanId: loan.id, lender: loan.lender, emiNo: n, amount: Math.round(amount), dueDate });
    }
  }

  candidates.sort((a, b) => a.dueDate.localeCompare(b.dueDate) || a.emiNo - b.emiNo);

  const covered: CoveredEmi[] = [];
  let left = amountMinor;
  for (const c of candidates) {
    if (c.amount > left) break;
    covered.push(c);
    left -= c.amount;
  }
  return covered;
}

/** Mark the confirmed EMIs paid, dated at the settlement. */
export async function markEmisPaid(covered: CoveredEmi[], paidOnIso: string): Promise<void> {
  const db = getDb();
  if (!db || covered.length === 0) return;

  const byLoan = new Map<string, CoveredEmi[]>();
  for (const c of covered) {
    const a = byLoan.get(c.loanId) ?? [];
    a.push(c);
    byLoan.set(c.loanId, a);
  }

  const day = paidOnIso.slice(0, 10);
  for (const [loanId, list] of byLoan) {
    // Re-read rather than trusting a snapshot: another device may have marked
    // one of these in between, and emi_payments is a whole-column JSON blob —
    // writing a stale copy would silently drop their change.
    const row = await db.getOptional<{ emi_payments: string | null }>(
      "SELECT emi_payments FROM loans WHERE id = ? AND deleted_at IS NULL",
      [loanId],
    );
    if (!row) continue;
    const map = parseMap(row.emi_payments) as Record<string, string>;
    for (const c of list) map[String(c.emiNo)] = day;
    await updateRow("loans", loanId, {
      emi_payments: JSON.stringify(map),
      emis_paid: Object.keys(map).length,
    });
  }
}
