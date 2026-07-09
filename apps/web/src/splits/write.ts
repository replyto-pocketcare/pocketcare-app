"use client";

import { money, type Money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { getRepositories, getUserId } from "../powersync";
import { insertRow } from "../write";
import { ensureVirtualAccount } from "./accounts";
import { splitEqual } from "./math";

const CONTACT_COLORS = ["#b06a4f", "#5f7a52", "#c08a3e", "#9cae8e", "#3e4a38", "#c98a72", "#7c7264", "#5f6647"];
const pickColor = () => CONTACT_COLORS[Math.floor(Math.random() * CONTACT_COLORS.length)]!;

/** Create a local contact (placeholder) to split with. */
export async function addContact(name: string, email?: string): Promise<string> {
  return insertRow("contacts", {
    name: name.trim(),
    email: email?.trim() || null,
    avatar_color: pickColor(),
    is_placeholder: 1,
    archived: 0,
  });
}

export interface EqualSplitInput {
  total: Money;                 // the full bill, minor units
  accountId: string;            // account you paid from (you are the sole payer in Phase 1)
  categoryId?: string | null;
  description?: string | null;
  note?: string | null;
  occurredAt: string;           // ISO
  groupId?: string | null;
  /** Contact ids of the OTHER participants (you are added automatically). */
  otherContactIds: string[];
}

/**
 * Phase 1 — you pay the full bill and split it equally among yourself + the
 * chosen contacts. Books YOUR share as an expense and the remainder as a
 * transfer to the hidden Receivable account, so budgets/insights count only
 * your share while the account reflects the full outflow. Records the shared
 * fact (expense + shares + payer) and links the private postings back to it.
 * Returns the shared-expense id.
 */
export async function createEqualSplitExpense(input: EqualSplitInput): Promise<string> {
  const currency = input.total.currency;
  const repos = getRepositories();
  const userId = getUserId();

  const participants: (string | null)[] = [null, ...input.otherContactIds]; // null = self
  const n = participants.length;
  const shares = splitEqual(input.total.amount, n);
  const ownShare = shares[0] ?? 0; // self is index 0
  const lent = input.total.amount - ownShare;

  // 1) Your own share → expense on the paying account.
  const expenseTx = await repos.transactions.create({
    account_id: input.accountId,
    type: "expense",
    amount: money(ownShare, currency as CurrencyCode),
    category_id: input.categoryId ?? null,
    note: input.note ?? null,
    description: input.description ?? null,
    occurred_at: input.occurredAt,
  });

  // 2) The rest (what friends owe you) → transfer to the hidden Receivable.
  let transferTxId: string | null = null;
  if (lent > 0) {
    const receivableId = await ensureVirtualAccount("receivable", currency);
    const tx = await repos.transactions.create({
      account_id: input.accountId,
      type: "transfer",
      amount: money(lent, currency as CurrencyCode),
      to_account_id: receivableId,
      note: "Split — lent to friends",
      occurred_at: input.occurredAt,
    });
    transferTxId = tx.id;
  }

  // 3) Shared fact.
  const expenseId = await insertRow("shared_expenses", {
    created_by: userId,
    group_id: input.groupId ?? null,
    description: input.description ?? null,
    total_amount: input.total.amount,
    currency,
    occurred_at: input.occurredAt,
    split_mode: "equal",
    category_id: input.categoryId ?? null,
  });
  for (let i = 0; i < participants.length; i++) {
    await insertRow("shared_expense_shares", { expense_id: expenseId, contact_id: participants[i], share_amount: shares[i] });
  }
  await insertRow("shared_expense_payers", { expense_id: expenseId, contact_id: null, paid_amount: input.total.amount, account_id: input.accountId });

  // 4) Link private postings to the shared fact (idempotent handle for edits).
  await insertRow("expense_postings", { expense_id: expenseId, transaction_id: expenseTx.id, role: "own_share" });
  if (transferTxId) await insertRow("expense_postings", { expense_id: expenseId, transaction_id: transferTxId, role: "lend" });

  return expenseId;
}
