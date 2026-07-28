"use client";

/**
 * Writing an itemized split.
 *
 * The critical design point: this does NOT introduce a second balance model.
 * Per-item shares are allocated, rolled up per person, and written into
 * `expense_participants` — the same table `createSplitExpense` writes and the
 * same table every balance, settle-up and friend-graph query already reads.
 * `expense_items` / `expense_item_shares` are the BREAKDOWN, kept so the split
 * can be explained and re-opened later.
 *
 * Consequence: nothing in `hooks.ts`, `math.ts`, `collapse.ts` or the settle-up
 * flow needs to change to support itemized bills.
 */
import { money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import {
  allocateReceipt,
  isCharge,
  reconcile,
  type LineAssignment,
  type ReceiptDraft,
} from "@pocketcare/receipts";

import { getRepositories, getUserId } from "../powersync";
import { insertRow } from "../write";
import { ensureVirtualAccount } from "./accounts";

export interface ItemizedSplitInput {
  readonly groupId: string;
  readonly draft: ReceiptDraft;
  /** Per-line participants and mode, keyed by `ReceiptLine.id`. */
  readonly assignments: readonly LineAssignment[];
  /** Who actually paid, and from which account. Usually just you. */
  readonly payers: ReadonlyArray<{ userId: string; paid: number; accountId?: string | null }>;
  readonly categoryId?: string | null;
  readonly note?: string | null;
  readonly occurredAt: string;
}

export class ItemizedSplitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ItemizedSplitError";
  }
}

/**
 * Create a shared, itemized expense and project your own share into your
 * private ledger.
 *
 * Mirrors `createSplitExpense`'s contract exactly, so callers (and everything
 * downstream) see no difference beyond `expenses.has_items = 1`.
 */
export async function createSplitExpenseItemized(input: ItemizedSplitInput): Promise<string> {
  const me = getUserId();
  const { draft, groupId } = input;
  const currency = draft.currency;
  const cur = currency as CurrencyCode;
  const repos = getRepositories();

  // Refuse to write a bill that doesn't add up. The UI blocks this too, but a
  // corrupted expense is unrecoverable from, so it's worth checking twice.
  const rec = reconcile(draft);
  if (!rec.ok) {
    throw new ItemizedSplitError(
      `Receipt doesn't reconcile: lines total ${rec.computed}, receipt says ${rec.stated}`,
    );
  }

  // Allocation throws if any line is unassigned or an exact split is off, so a
  // partial write can never begin.
  const allocation = allocateReceipt(draft.lines, input.assignments);

  const paidByUser = new Map<string, number>();
  for (const p of input.payers) paidByUser.set(p.userId, (paidByUser.get(p.userId) ?? 0) + p.paid);
  const totalPaid = [...paidByUser.values()].reduce((a, b) => a + b, 0);
  if (totalPaid !== allocation.total) {
    throw new ItemizedSplitError(
      `Payments total ${totalPaid} but the bill is ${allocation.total}`,
    );
  }

  // ---- shared facts ----
  const expenseId = await insertRow("expenses", {
    group_id: groupId,
    created_by: me,
    description: draft.merchant ?? null,
    amount: allocation.total,
    currency,
    occurred_at: input.occurredAt,
    split_mode: "itemized",
    has_items: 1,
    version: 1,
  });

  const byLineId = new Map(input.assignments.map((a) => [a.lineId, a]));
  let sort = 0;
  for (const line of draft.lines) {
    const assignment = byLineId.get(line.id);
    const itemId = await insertRow("expense_items", {
      expense_id: expenseId,
      group_id: groupId,
      kind: line.kind,
      description: line.description,
      quantity: line.quantity,
      unit: line.unit,
      unit_price: line.unitPrice,
      amount: line.amount,
      // Guard the DB constraint: only charges may be proportional.
      split_mode:
        assignment?.mode === "proportional" && !isCharge(line.kind) ? "equal" : assignment?.mode ?? "equal",
      sort: sort++,
    });

    const shares = allocation.perLine.get(line.id) ?? [];
    const weightByUser = new Map(
      (assignment?.shares ?? []).map((s) => [s.userId, Math.round(s.weight ?? 0)]),
    );
    for (const share of shares) {
      await insertRow("expense_item_shares", {
        item_id: itemId,
        expense_id: expenseId,
        group_id: groupId,
        user_id: share.userId,
        weight: weightByUser.get(share.userId) ?? 0,
        share_amount: share.amount,
      });
    }
  }

  // ---- the roll-up that keeps every existing balance query working ----
  const users = new Set<string>([...allocation.byUser.keys(), ...paidByUser.keys()]);
  for (const uid of users) {
    await insertRow("expense_participants", {
      expense_id: expenseId,
      group_id: groupId,
      user_id: uid,
      paid_amount: paidByUser.get(uid) ?? 0,
      share_amount: allocation.byUser.get(uid) ?? 0,
    });
  }

  // ---- your private projection ----
  const myShare = allocation.byUser.get(me) ?? 0;
  const myPaid = paidByUser.get(me) ?? 0;
  const myAccountId = input.payers.find((p) => p.userId === me)?.accountId ?? null;

  await projectPersonalItemized({
    repos,
    cur,
    currency,
    myShare,
    myPaid,
    myAccountId,
    expenseId,
    categoryId: input.categoryId ?? null,
    description: draft.merchant ?? null,
    note: input.note ?? null,
    occurredAt: input.occurredAt,
    // Your own-share transaction carries the lines YOU are on, so the personal
    // breakdown matches what you actually ate.
    myLines: draft.lines
      .map((line) => {
        const amount = (allocation.perLine.get(line.id) ?? []).find((s) => s.userId === me)?.amount ?? 0;
        return { description: line.description || line.kind.replace("_", " "), amount };
      })
      .filter((l) => l.amount !== 0),
  });

  return expenseId;
}

/**
 * Private ledger projection. Deliberately identical in shape and roles
 * (`own_share` / `borrow` / `lend`) to `projectPersonal` in `write.ts` — see
 * the 2026-07-23 change-log entry for why the covered portion books as an
 * expense rather than a transfer.
 */
async function projectPersonalItemized(o: {
  repos: ReturnType<typeof getRepositories>;
  cur: CurrencyCode;
  currency: string;
  myShare: number;
  myPaid: number;
  myAccountId: string | null;
  expenseId: string;
  categoryId: string | null;
  description: string | null;
  note: string | null;
  occurredAt: string;
  myLines: ReadonlyArray<{ description: string; amount: number }>;
}): Promise<void> {
  const paidToOwn = Math.min(o.myPaid, o.myShare);
  const underpay = Math.max(0, o.myShare - o.myPaid);
  const overpay = Math.max(0, o.myPaid - o.myShare);
  const post = async (txId: string, role: string) => {
    await insertRow("expense_postings", { expense_id: o.expenseId, transaction_id: txId, role });
  };

  if (paidToOwn > 0 && o.myAccountId) {
    // Breakdown items must sum EXACTLY to the transaction amount, so they can
    // only ride along when this leg is your whole share.
    const itemsMatch = o.myLines.reduce((s, l) => s + l.amount, 0) === paidToOwn;
    const tx = await o.repos.transactions.create({
      account_id: o.myAccountId,
      type: "expense",
      amount: money(paidToOwn, o.cur),
      category_id: o.categoryId,
      note: o.note,
      description: o.description,
      occurred_at: o.occurredAt,
      ...(itemsMatch
        ? { items: o.myLines.map((l) => ({ description: l.description, amount: money(l.amount, o.cur) })) }
        : {}),
    });
    await post(tx.id, "own_share");
  }
  if (underpay > 0) {
    const payable = await ensureVirtualAccount("payable", o.currency);
    const tx = await o.repos.transactions.create({
      account_id: payable,
      type: "expense",
      amount: money(underpay, o.cur),
      category_id: o.categoryId,
      note: o.note,
      description: o.description,
      occurred_at: o.occurredAt,
    });
    await post(tx.id, "borrow");
  }
  if (overpay > 0 && o.myAccountId) {
    const tx = await o.repos.transactions.create({
      account_id: o.myAccountId,
      type: "expense",
      amount: money(overpay, o.cur),
      category_id: o.categoryId,
      note: o.note,
      description: o.description,
      occurred_at: o.occurredAt,
    });
    await post(tx.id, "lend");
  }
}
