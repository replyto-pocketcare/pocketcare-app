"use client";

import { money, type Money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { getRepositories, getUserId } from "../powersync";
import { insertRow, nowIso } from "../write";
import { ensureVirtualAccount } from "./accounts";
import { splitEqual, splitByWeights } from "./math";

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

export type SplitMode = "equal" | "exact" | "percent";

export interface ParticipantInput {
  contactId: string | null; // null = self
  /** exact minor amount (exact mode) or percentage (percent mode); ignored for equal */
  value?: number | undefined;
}
export interface PayerInput {
  contactId: string | null;       // null = self
  paid: number;                    // minor
  accountId?: string | null | undefined; // only the self payer carries this
}
export interface SplitExpenseInput {
  mode: SplitMode;
  total: Money;                    // full bill, minor
  participants: ParticipantInput[];
  payers: PayerInput[];
  categoryId?: string | null;
  description?: string | null;
  note?: string | null;
  occurredAt: string;              // ISO
  groupId?: string | null;
}

/** Compute each participant's share (minor) for the chosen mode. */
function computeShares(input: SplitExpenseInput): number[] {
  const n = input.participants.length;
  if (input.mode === "equal") return splitEqual(input.total.amount, n);
  if (input.mode === "percent") return splitByWeights(input.total.amount, input.participants.map((p) => p.value ?? 0));
  return input.participants.map((p) => Math.max(0, Math.round(p.value ?? 0))); // exact (caller validates the sum)
}

/**
 * Create a split expense with your private ledger postings. Handles who-paid
 * (you and/or contacts, multi-payer) independently of who-owes. Your books get:
 *   - an expense for the part of your share you actually paid (on your account),
 *   - an expense for the part of your share a contact covered (on the hidden
 *     Payable account → you owe it, still counted in your budget),
 *   - a transfer of any amount you overpaid to the hidden Receivable account.
 * Cash out = exactly what you paid; budget = exactly your share. Returns the
 * shared-expense id. Per-contact balances are DERIVED from shares+payers.
 */
export async function createSplitExpense(input: SplitExpenseInput): Promise<string> {
  const currency = input.total.currency;
  const cur = currency as CurrencyCode;
  const repos = getRepositories();
  const userId = getUserId();

  const shares = computeShares(input);
  const selfIdx = input.participants.findIndex((p) => p.contactId === null);
  const selfShare = selfIdx >= 0 ? shares[selfIdx] ?? 0 : 0;
  const selfPayer = input.payers.find((p) => p.contactId === null);
  const selfPaid = input.payers.filter((p) => p.contactId === null).reduce((s, p) => s + p.paid, 0);
  const selfAccountId = selfPayer?.accountId ?? null;

  const paidToOwn = Math.min(selfPaid, selfShare);
  const underpay = Math.max(0, selfShare - selfPaid); // a contact covered this part of your share → you owe it
  const overpay = Math.max(0, selfPaid - selfShare);  // you covered others → they owe you

  if ((paidToOwn > 0 || overpay > 0) && !selfAccountId) {
    throw new Error("Pick the account you paid from.");
  }

  const postings: { txId: string; role: string }[] = [];

  // Part of your share you paid in cash.
  if (paidToOwn > 0) {
    const tx = await repos.transactions.create({
      account_id: selfAccountId!, type: "expense", amount: money(paidToOwn, cur),
      category_id: input.categoryId ?? null, note: input.note ?? null, description: input.description ?? null,
      occurred_at: input.occurredAt,
    });
    postings.push({ txId: tx.id, role: "own_share" });
  }
  // Part of your share a contact covered → expense on Payable (you owe it).
  if (underpay > 0) {
    const payableId = await ensureVirtualAccount("payable", currency);
    const tx = await repos.transactions.create({
      account_id: payableId, type: "expense", amount: money(underpay, cur),
      category_id: input.categoryId ?? null, note: input.note ?? null, description: input.description ?? null,
      occurred_at: input.occurredAt,
    });
    postings.push({ txId: tx.id, role: "borrow" });
  }
  // Amount you overpaid on others' behalf → transfer to Receivable.
  if (overpay > 0) {
    const receivableId = await ensureVirtualAccount("receivable", currency);
    const tx = await repos.transactions.create({
      account_id: selfAccountId!, type: "transfer", amount: money(overpay, cur),
      to_account_id: receivableId, note: "Split — lent to friends", occurred_at: input.occurredAt,
    });
    postings.push({ txId: tx.id, role: "lend" });
  }

  // Shared fact.
  const expenseId = await insertRow("shared_expenses", {
    created_by: userId, group_id: input.groupId ?? null, description: input.description ?? null,
    total_amount: input.total.amount, currency, occurred_at: input.occurredAt, split_mode: input.mode,
    category_id: input.categoryId ?? null,
  });
  for (let i = 0; i < input.participants.length; i++) {
    await insertRow("shared_expense_shares", { expense_id: expenseId, contact_id: input.participants[i]!.contactId, share_amount: shares[i] });
  }
  for (const p of input.payers) {
    await insertRow("shared_expense_payers", { expense_id: expenseId, contact_id: p.contactId, paid_amount: p.paid, account_id: p.contactId === null ? p.accountId ?? null : null });
  }
  for (const pg of postings) {
    await insertRow("expense_postings", { expense_id: expenseId, transaction_id: pg.txId, role: pg.role });
  }
  return expenseId;
}

/** Back-compat: equal split where you are the sole payer of the full bill. */
export async function createEqualSplitExpense(opts: {
  total: Money; accountId: string; categoryId?: string | null; description?: string | null;
  note?: string | null; occurredAt: string; groupId?: string | null; otherContactIds: string[];
}): Promise<string> {
  return createSplitExpense({
    mode: "equal", total: opts.total,
    participants: [{ contactId: null }, ...opts.otherContactIds.map((id) => ({ contactId: id }))],
    payers: [{ contactId: null, paid: opts.total.amount, accountId: opts.accountId }],
    categoryId: opts.categoryId ?? null, description: opts.description ?? null, note: opts.note ?? null,
    occurredAt: opts.occurredAt, groupId: opts.groupId ?? null,
  });
}

/**
 * Settle a balance with a contact. With an account, books the offsetting ledger
 * transfer (received: Receivable→account; paid: account→Payable). With
 * accountId=null ("None"), records the settlement only (no cash movement).
 */
export async function settleUp(opts: {
  contactId: string; amount: number; direction: "received" | "paid"; accountId: string | null;
  currency: string; note?: string;
}): Promise<void> {
  const cur = opts.currency as CurrencyCode;
  let offsetId: string | null = null;
  if (opts.accountId && opts.amount > 0) {
    const repos = getRepositories();
    if (opts.direction === "received") {
      const recv = await ensureVirtualAccount("receivable", opts.currency);
      const tx = await repos.transactions.create({
        account_id: recv, type: "transfer", amount: money(opts.amount, cur),
        to_account_id: opts.accountId, note: "Settlement received", occurred_at: nowIso(),
      });
      offsetId = tx.id;
    } else {
      const pay = await ensureVirtualAccount("payable", opts.currency);
      const tx = await repos.transactions.create({
        account_id: opts.accountId, type: "transfer", amount: money(opts.amount, cur),
        to_account_id: pay, note: "Settlement paid", occurred_at: nowIso(),
      });
      offsetId = tx.id;
    }
  }
  await insertRow("settlements", {
    contact_id: opts.contactId, amount: opts.amount, direction: opts.direction,
    account_id: opts.accountId, offset_transaction_id: offsetId, settled_at: nowIso(), note: opts.note ?? null,
  });
}
