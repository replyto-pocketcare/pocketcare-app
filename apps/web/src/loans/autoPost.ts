"use client";

/**
 * Post ledger transactions for EMIs that auto-mark already treats as paid.
 *
 * `auto_mark_paid` used to be **display only**: past-due EMIs flipped to "paid"
 * on the schedule, but no money left any account. So the funding account never
 * moved and — when the EMI is charged to a credit card — the card showed no
 * charge. The EMI looked settled while the ledger disagreed.
 *
 * This closes that gap for loans where a funding account is known (the last one
 * used to mark an EMI paid on this device — see `funding.ts`). Loans without
 * one keep the old display-only behaviour rather than guessing which account to
 * take money from.
 *
 * SAFETY — never post an EMI twice:
 *  - dedupe is a lookup in the **synced ledger** for a transaction with the
 *    exact `emiDescription(...)`, not a local flag, so a second device that
 *    runs the same catch-up finds the first device's row and skips;
 *  - a module-level guard stops concurrent runs within a tab;
 *  - only EMIs whose due date has actually passed are considered, and each is
 *    posted at its own due date, not today.
 */

import { effectivePaidEmis, emiDueDate } from "@pocketcare/finance";
import { money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { getDb, getRepositories } from "../powersync";
import { emiDescription, getLoanFundingAccount } from "./funding";

interface LoanRow {
  id: string; lender: string | null; currency: string | null;
  emi_amount: number | null; tenure_months: number | null;
  start_date: string | null; emis_paid: number | null; emi_payments: string | null;
  emi_amounts: string | null; emi_due_day: number | null; auto_mark_paid: number | null;
}

/** Catching up more than a year of missed EMIs at once is a bug, not a feature. */
const MAX_PER_LOAN = 12;

let running = false;

const parseMap = (json: string | null): Record<string, unknown> => {
  if (!json) return {};
  try { const v = JSON.parse(json); return v && typeof v === "object" ? v : {}; } catch { return {}; }
};

export async function runLoanAutoPost(): Promise<number> {
  if (running) return 0;
  running = true;
  const db = getDb();
  if (!db) { running = false; return 0; }

  try {
    const loans = await db.getAll<LoanRow>(
      `SELECT id, lender, currency, emi_amount, tenure_months, start_date, emis_paid,
              emi_payments, emi_amounts, emi_due_day, auto_mark_paid
         FROM loans
        WHERE deleted_at IS NULL AND IFNULL(auto_mark_paid, 0) = 1`,
    );

    let posted = 0;
    for (const loan of loans) {
      const accountId = getLoanFundingAccount(loan.id);
      if (!accountId) continue; // no known funding account → stay display-only

      // The account may have been deleted or archived since it was last used.
      const acct = await db.getOptional<{ id: string }>(
        "SELECT id FROM accounts WHERE id = ? AND deleted_at IS NULL AND IFNULL(is_archived,0) = 0",
        [accountId],
      );
      if (!acct) continue;

      const total = loan.tenure_months ?? 0;
      if (total <= 0) continue;

      const manualMap = parseMap(loan.emi_payments);
      const manual = Object.keys(manualMap).map(Number).filter(Number.isFinite);
      const paid = effectivePaidEmis(manual, total, {
        autoMark: true,
        startIso: loan.start_date,
        dueDay: loan.emi_due_day,
      });

      // Manually-marked EMIs already had their posting decision made in the
      // dialog (the user chose an account there, or chose not to record).
      const manualSet = new Set(manual);
      const amounts = parseMap(loan.emi_amounts) as Record<string, number>;
      const cur = (loan.currency || "INR") as CurrencyCode;

      let done = 0;
      for (const n of [...paid].sort((a, b) => a - b)) {
        if (done >= MAX_PER_LOAN) break;
        if (manualSet.has(n)) continue;

        const amount = Number(amounts[String(n)] ?? loan.emi_amount ?? 0);
        if (!Number.isFinite(amount) || amount <= 0) continue;

        const description = emiDescription(n, loan.lender);
        const existing = await db.getOptional<{ id: string }>(
          "SELECT id FROM transactions WHERE description = ? AND account_id = ? AND deleted_at IS NULL LIMIT 1",
          [description, accountId],
        );
        if (existing) continue;

        const due = emiDueDate(loan.start_date, loan.emi_due_day, n);
        try {
          await getRepositories().transactions.create({
            account_id: accountId,
            type: "expense",
            amount: money(Math.round(amount), cur),
            description,
            // Dated at the EMI's own due date, so it lands in the right month
            // and the right credit-card billing cycle.
            occurred_at: new Date(`${due}T12:00:00`).toISOString(),
          });
          posted++; done++;
        } catch {
          // e.g. an overdraft guard refusing the write. Leave it unposted and
          // move on rather than stalling every other loan.
          break;
        }
      }
    }
    return posted;
  } finally {
    running = false;
  }
}
