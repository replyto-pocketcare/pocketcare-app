"use client";

import { money, type Money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { getRepositories, getUserId, getDb, getSupabase } from "../powersync";
import { insertRow, nowIso } from "../write";
import { ensureVirtualAccount } from "./accounts";
import { splitEqual, splitByWeights } from "./math";

export type SplitMode = "equal" | "exact" | "percent";

// ---------------- Groups ----------------

/** Create a group/trip. Adds you as owner; connected users can be added directly. */
export async function createGroup(opts: {
  name: string; kind: "group" | "trip"; currency: string;
  startDate?: string | null; endDate?: string | null; autoSplit?: boolean;
  isDirect?: boolean; memberUserIds?: string[];
}): Promise<string> {
  const me = getUserId();
  const groupId = await insertRow("split_groups", {
    created_by: me, name: opts.name.trim(), kind: opts.kind, is_direct: opts.isDirect ? 1 : 0,
    start_date: opts.startDate ?? null, end_date: opts.endDate ?? null,
    auto_split: opts.autoSplit ? 1 : 0, default_mode: "equal", currency: opts.currency, archived: 0,
  });
  await insertRow("split_group_members", { group_id: groupId, user_id: me, role: "owner" });
  for (const uid of opts.memberUserIds ?? []) {
    if (uid !== me) await insertRow("split_group_members", { group_id: groupId, user_id: uid, role: "member" });
  }
  return groupId;
}

/** Find (or create) the hidden 2-person group for a 1:1 split with a connection. */
export async function getOrCreateDirectGroup(otherUserId: string, otherName: string, currency: string): Promise<string> {
  const me = getUserId();
  const db = getDb();
  if (db) {
    const row = await db.getOptional<{ id: string }>(
      `SELECT g.id FROM split_groups g
       WHERE g.is_direct = 1 AND g.deleted_at IS NULL
         AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL) = 2
         AND (SELECT COUNT(*) FROM split_group_members m WHERE m.group_id = g.id AND m.deleted_at IS NULL AND m.user_id IN (?, ?)) = 2
       LIMIT 1`,
      [me, otherUserId],
    );
    if (row) return row.id;
  }
  return createGroup({ name: otherName || "Direct", kind: "group", currency, isDirect: true, memberUserIds: [otherUserId] });
}

// ---------------- Expenses ----------------

export interface ParticipantInput { userId: string; value?: number | undefined } // value = exact minor / percent
export interface PayerInput { userId: string; paid: number; accountId?: string | null | undefined }
export interface SplitExpenseInput {
  groupId: string;
  mode: SplitMode;
  total: Money;
  participants: ParticipantInput[];
  payers: PayerInput[];
  categoryId?: string | null;
  description?: string | null;
  note?: string | null;
  occurredAt: string;
}

function computeShares(input: SplitExpenseInput): number[] {
  const n = input.participants.length;
  if (input.mode === "equal") return splitEqual(input.total.amount, n);
  if (input.mode === "percent") return splitByWeights(input.total.amount, input.participants.map((p) => p.value ?? 0));
  return input.participants.map((p) => Math.max(0, Math.round(p.value ?? 0)));
}

/**
 * Create a shared expense in a group, then project YOUR share into your private
 * ledger (expense on your account / hidden Payable, transfer to hidden
 * Receivable). Other members project their own share on their own devices.
 */
export async function createSplitExpense(input: SplitExpenseInput): Promise<string> {
  const me = getUserId();
  const currency = input.total.currency;
  const cur = currency as CurrencyCode;
  const repos = getRepositories();

  const shares = computeShares(input);
  const shareByUser = new Map<string, number>();
  input.participants.forEach((p, i) => shareByUser.set(p.userId, (shareByUser.get(p.userId) ?? 0) + (shares[i] ?? 0)));
  const paidByUser = new Map<string, number>();
  for (const p of input.payers) paidByUser.set(p.userId, (paidByUser.get(p.userId) ?? 0) + p.paid);

  // Shared fact.
  const expenseId = await insertRow("expenses", {
    group_id: input.groupId, created_by: me, description: input.description ?? null,
    amount: input.total.amount, currency, occurred_at: input.occurredAt, split_mode: input.mode, version: 1,
  });
  const users = new Set<string>([...shareByUser.keys(), ...paidByUser.keys()]);
  for (const uid of users) {
    await insertRow("expense_participants", {
      expense_id: expenseId, group_id: input.groupId, user_id: uid,
      paid_amount: paidByUser.get(uid) ?? 0, share_amount: shareByUser.get(uid) ?? 0,
    });
  }

  // ---- your private projection ----
  const myShare = shareByUser.get(me) ?? 0;
  const myPaid = paidByUser.get(me) ?? 0;
  const myAccountId = input.payers.find((p) => p.userId === me)?.accountId ?? null;
  await projectPersonal({ repos, cur, currency, myShare, myPaid, myAccountId, expenseId,
    categoryId: input.categoryId ?? null, description: input.description ?? null, note: input.note ?? null, occurredAt: input.occurredAt });

  return expenseId;
}

async function projectPersonal(o: {
  repos: ReturnType<typeof getRepositories>; cur: CurrencyCode; currency: string;
  myShare: number; myPaid: number; myAccountId: string | null; expenseId: string;
  categoryId: string | null; description: string | null; note: string | null; occurredAt: string;
}): Promise<void> {
  const paidToOwn = Math.min(o.myPaid, o.myShare);
  const underpay = Math.max(0, o.myShare - o.myPaid);
  const overpay = Math.max(0, o.myPaid - o.myShare);
  const post = async (txId: string, role: string) => { await insertRow("expense_postings", { expense_id: o.expenseId, transaction_id: txId, role }); };

  if (paidToOwn > 0 && o.myAccountId) {
    const tx = await o.repos.transactions.create({ account_id: o.myAccountId, type: "expense", amount: money(paidToOwn, o.cur), category_id: o.categoryId, note: o.note, description: o.description, occurred_at: o.occurredAt });
    await post(tx.id, "own_share");
  }
  if (underpay > 0) {
    const payable = await ensureVirtualAccount("payable", o.currency);
    const tx = await o.repos.transactions.create({ account_id: payable, type: "expense", amount: money(underpay, o.cur), category_id: o.categoryId, note: o.note, description: o.description, occurred_at: o.occurredAt });
    await post(tx.id, "borrow");
  }
  if (overpay > 0 && o.myAccountId) {
    const receivable = await ensureVirtualAccount("receivable", o.currency);
    const tx = await o.repos.transactions.create({ account_id: o.myAccountId, type: "transfer", amount: money(overpay, o.cur), to_account_id: receivable, note: "Split — lent to friends", occurred_at: o.occurredAt });
    await post(tx.id, "lend");
  }
}

// ---------------- Settlements ----------------

export async function settleUp(opts: {
  otherUserId: string; groupId: string; amount: number; direction: "received" | "paid";
  accountId: string | null; currency: string; note?: string;
}): Promise<void> {
  const me = getUserId();
  const cur = opts.currency as CurrencyCode;
  const fromUser = opts.direction === "received" ? opts.otherUserId : me;
  const toUser = opts.direction === "received" ? me : opts.otherUserId;

  const settlementId = await insertRow("settlements", {
    group_id: opts.groupId, from_user: fromUser, to_user: toUser, amount: opts.amount,
    currency: opts.currency, method: opts.accountId ? "account" : "none", note: opts.note ?? null,
    settled_at: nowIso(), created_by: me,
  });

  if (opts.accountId && opts.amount > 0) {
    const repos = getRepositories();
    let txId: string;
    if (opts.direction === "received") {
      const recv = await ensureVirtualAccount("receivable", opts.currency);
      const tx = await repos.transactions.create({ account_id: recv, type: "transfer", amount: money(opts.amount, cur), to_account_id: opts.accountId, note: "Settlement received", occurred_at: nowIso() });
      txId = tx.id;
    } else {
      const pay = await ensureVirtualAccount("payable", opts.currency);
      const tx = await repos.transactions.create({ account_id: opts.accountId, type: "transfer", amount: money(opts.amount, cur), to_account_id: pay, note: "Settlement paid", occurred_at: nowIso() });
      txId = tx.id;
    }
    await insertRow("expense_postings", { settlement_id: settlementId, transaction_id: txId, role: "settlement" });
  }
}

// ---------------- Invites ----------------

export interface InviteResult {
  added: boolean;                    // true = a registered user was added directly
  already?: boolean | undefined;     // they were already a member
  name?: string | undefined;         // added user's display name
  link?: string | undefined;         // share link (when not added directly)
}

/**
 * Invite to a group (edge function; you must be a member). If `email` belongs to
 * a registered PocketCare user they're added to the group directly; otherwise a
 * shareable invite link is returned. With no email, always returns a link.
 */
export async function createInvite(groupId: string, email?: string): Promise<InviteResult> {
  const { data, error } = await getSupabase().functions.invoke("split-invite", { body: { group_id: groupId, email } });
  if (error) throw new Error(error.message);
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error);
  const d = data as { added: boolean; already?: boolean; name?: string; token?: string; link?: string | null };
  if (d.added) return { added: true, already: d.already, name: d.name };
  const link = d.link ?? `${typeof window !== "undefined" ? window.location.origin : ""}/join?token=${d.token}`;
  return { added: false, link };
}

/** Accept an invite by token (edge function). Returns the joined group id. */
export async function acceptInvite(token: string): Promise<string> {
  const { data, error } = await getSupabase().functions.invoke("split-invite-accept", { body: { token } });
  if (error) throw new Error(error.message);
  if ((data as { error?: string })?.error) throw new Error((data as { error: string }).error);
  return (data as { group_id: string }).group_id;
}
