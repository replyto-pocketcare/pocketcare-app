"use client";

/**
 * Recurring commitments, standing on their own table.
 *
 * They used to be stored as a PAIR — a `transaction_templates` row describing
 * the transaction plus a `recurring_rules` row describing the schedule — which
 * meant the Templates feature and the recurring engine could never be separated:
 * deleting a template deleted a commitment. Migration 0060 introduced
 * `recurring_items` to hold both halves, and 0064 gave it the fields the posting
 * engine actually reads. This module is the app finally switching over.
 *
 * Everything a due item needs to become a transaction now lives on one row.
 */
import { useQuery } from "@powersync/react";
import { money, type Money } from "@sanvya/money";
import type { CurrencyCode } from "@sanvya/types";
import { getDb, getRepositories, getUserId } from "../powersync";
import { getBaseCurrency } from "../prefs";
import { insertRow, updateRow, softDelete } from "../write";
import { createSplitExpense } from "../splits/write";

export type Freq = "daily" | "weekly" | "monthly" | "yearly";
export type RecurringDirection = "income" | "payment" | "saving";

/** A row of `recurring_items`, as the app reads it. */
export interface RecurringRow {
  id: string;
  direction: string;
  name: string;
  amount: number | null;
  currency: string | null;
  frequency: Freq;
  interval_count: number | null;
  next_due: string;
  account_id: string | null;
  to_account_id: string | null;
  category_id: string | null;
  group_id: string | null;
  auto_post: number;
  active: number;
  alert_time_utc: string | null;
  description: string | null;
  note: string | null;
  payment_method: string | null;
  labels: string | null;
  split_group_id: string | null;
}

export const RECURRING_COLUMNS =
  `id, direction, name, amount, currency, frequency, interval_count, next_due,
   account_id, to_account_id, category_id, group_id, auto_post, active, alert_time_utc,
   description, note, payment_method, labels, split_group_id`;

/** Direction → the transaction type it posts. Savings are a transfer into an
 *  investment account; payments are expenses; income is income. */
export const typeForDirection = (d: RecurringDirection): "income" | "expense" | "transfer" =>
  d === "income" ? "income" : d === "saving" ? "transfer" : "expense";

const directionOf = (d: string): RecurringDirection =>
  d === "income" ? "income" : d === "saving" ? "saving" : "payment";

export function advance(dateStr: string, freq: Freq, n: number): string {
  const d = new Date(dateStr + "T00:00:00");
  if (freq === "daily") d.setDate(d.getDate() + n);
  else if (freq === "weekly") d.setDate(d.getDate() + 7 * n);
  else if (freq === "monthly") d.setMonth(d.getMonth() + n);
  else d.setFullYear(d.getFullYear() + n);
  return d.toISOString().slice(0, 10);
}

const dueIso = (day: string) => `${day}T12:00:00.000Z`;

/**
 * Turn one due occurrence into a real transaction.
 *
 * Carries the same fields the template-backed version did — description, note,
 * payment method, labels, transfer destination and the recurring split — so
 * moving off templates does not quietly strip detail from posted transactions.
 */
export async function materialize(item: RecurringRow, occurredAtIso: string): Promise<void> {
  const cur = (item.currency || getBaseCurrency()) as CurrencyCode;
  const total: Money = money(item.amount ?? 0, cur);
  const db = getDb();
  const type = typeForDirection(directionOf(item.direction));

  // Recurring split: equal split among current group members, you pay.
  if (item.split_group_id && item.account_id && db) {
    const members = await db.getAll<{ user_id: string }>(
      "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL",
      [item.split_group_id],
    );
    const ids = members.map((m) => m.user_id);
    if (ids.length >= 2) {
      await createSplitExpense({
        groupId: item.split_group_id, mode: "equal", total,
        participants: ids.map((id) => ({ userId: id })),
        payers: [{ userId: getUserId(), paid: total.amount, accountId: item.account_id }],
        categoryId: item.category_id, description: item.description, note: item.note,
        occurredAt: occurredAtIso,
      });
      return;
    }
  }

  const repos = getRepositories();
  const labels = item.labels ? item.labels.split(",").map((s) => s.trim()).filter(Boolean) : undefined;
  if (type === "transfer" && item.to_account_id && item.account_id) {
    await repos.transactions.create({
      account_id: item.account_id, type: "transfer", amount: total,
      to_account_id: item.to_account_id, note: item.note, occurred_at: occurredAtIso,
    });
  } else if (item.account_id) {
    await repos.transactions.create({
      account_id: item.account_id, type: type === "income" ? "income" : "expense", amount: total,
      category_id: item.category_id, description: item.description, note: item.note,
      payment_method: item.payment_method, labels: labels ?? [], occurred_at: occurredAtIso,
    });
  }
}

/** Post every auto-post item that has come due, catching up missed occurrences. */
export async function runRecurring(): Promise<number> {
  const db = getDb();
  if (!db) return 0;
  const today = new Date().toISOString().slice(0, 10);
  const items = await db.getAll<RecurringRow>(
    `SELECT ${RECURRING_COLUMNS} FROM recurring_items
      WHERE deleted_at IS NULL AND active = 1 AND auto_post = 1 AND next_due <= ?`,
    [today],
  );
  let posted = 0;
  for (const item of items) {
    let due = item.next_due;
    let guard = 0;
    while (due <= today && guard++ < 24) {
      try {
        await materialize(item, dueIso(due));
      } catch {
        // e.g. an overdraft-blocked auto-post: leave next_due where it is so it
        // shows as still-due, and move on instead of stalling every other item.
        break;
      }
      const next = advance(due, item.frequency, item.interval_count || 1);
      await updateRow("recurring_items", item.id, { next_due: next, last_generated: due });
      due = next;
      posted++;
    }
  }
  return posted;
}

/** Post one occurrence now and advance ("Post now" / confirming a due item). */
export async function postOnce(id: string): Promise<void> {
  const db = getDb();
  if (!db) return;
  const item = await db.getOptional<RecurringRow>(
    `SELECT ${RECURRING_COLUMNS} FROM recurring_items WHERE id = ? AND deleted_at IS NULL`, [id],
  );
  if (!item) return;
  await materialize(item, dueIso(item.next_due));
  await updateRow("recurring_items", id, {
    next_due: advance(item.next_due, item.frequency, item.interval_count || 1),
    last_generated: item.next_due,
  });
}

/** Skip one occurrence without posting (just advance next_due). */
export async function skipOnce(id: string): Promise<void> {
  const db = getDb();
  if (!db) return;
  const item = await db.getOptional<{ next_due: string; frequency: Freq; interval_count: number | null }>(
    "SELECT next_due, frequency, interval_count FROM recurring_items WHERE id = ? AND deleted_at IS NULL", [id],
  );
  if (!item) return;
  await updateRow("recurring_items", id, {
    next_due: advance(item.next_due, item.frequency, item.interval_count || 1),
  });
}

export interface RecurringInput {
  direction: RecurringDirection;
  name: string;
  amount: number;              // major units
  accountId: string | null;
  toAccountId?: string | null;
  categoryId?: string | null;
  frequency: Freq;
  firstDue: string;            // YYYY-MM-DD
  autoPost: boolean;
  groupId: string;
  alert_time_utc: string | null;
}

const toRow = (inp: RecurringInput) => ({
  direction: inp.direction,
  name: inp.name.trim(),
  amount: Math.round(inp.amount * 100),
  currency: getBaseCurrency(),
  frequency: inp.frequency,
  interval_count: 1,
  next_due: inp.firstDue,
  account_id: inp.accountId,
  to_account_id: inp.toAccountId ?? null,
  category_id: inp.categoryId ?? null,
  group_id: inp.groupId,
  auto_post: inp.autoPost ? 1 : 0,
  alert_time_utc: inp.alert_time_utc,
});

export async function createRecurring(inp: RecurringInput): Promise<string> {
  return insertRow("recurring_items", { ...toRow(inp), active: 1, last_generated: null });
}

export async function updateRecurring(id: string, inp: RecurringInput): Promise<void> {
  await updateRow("recurring_items", id, toRow(inp));
}

export async function removeRecurring(id: string): Promise<void> {
  await softDelete("recurring_items", id);
}

/** Items due now that DON'T auto-post — the ones asking to be confirmed. */
export interface DueItem {
  id: string; template_id: string; template_name: string; type: string;
  amount: number | null; currency: string | null;
  frequency: Freq; interval_count: number | null; next_due: string; auto_post: number; active: number;
}

export function useDueItems(): DueItem[] {
  const today = new Date().toISOString().slice(0, 10);
  const { data = [] } = useQuery<DueItem>(
    `SELECT id, id AS template_id, name AS template_name, direction AS type, amount, currency,
            frequency, interval_count, next_due, auto_post, active
       FROM recurring_items
      WHERE deleted_at IS NULL AND active = 1 AND auto_post = 0 AND next_due <= ?
      ORDER BY next_due`,
    [today],
  );
  return data;
}
