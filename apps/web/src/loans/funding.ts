"use client";

/**
 * Which account an EMI is paid from — including a credit card, so an EMI
 * charged to a card shows up against that card.
 *
 * Stored per-loan in localStorage rather than on the `loans` row, so there's no
 * migration. The trade-off is real and worth stating: this is **per device**.
 * A loan you've been paying on your phone won't auto-post on your laptop until
 * you mark one EMI paid there. Marking paid manually always works everywhere;
 * only the convenience is local.
 */

const KEY = (loanId: string) => `sanvya:loanFunding:${loanId}`;

export function getLoanFundingAccount(loanId: string): string | null {
  try { return localStorage.getItem(KEY(loanId)); } catch { return null; }
}

export function setLoanFundingAccount(loanId: string, accountId: string | null): void {
  try {
    if (accountId) localStorage.setItem(KEY(loanId), accountId);
    else localStorage.removeItem(KEY(loanId));
  } catch { /* private mode / storage full — the manual path still works */ }
}

/**
 * The description an EMI transaction carries. Deterministic, because it is also
 * the **dedupe key**: before auto-posting we look for an existing transaction
 * with this exact description.
 *
 * Checking the synced ledger rather than local state is what makes auto-post
 * safe across devices — two phones both running the catch-up on the same
 * morning will each find the other's row (once synced) and skip. Persisted
 * ledger text stays English by design; it's data, not UI chrome.
 */
export function emiDescription(emiNo: number, lender: string | null): string {
  return `EMI #${emiNo}${lender ? ` — ${lender}` : ""}`;
}
