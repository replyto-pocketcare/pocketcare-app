"use client";

/**
 * Recurring items, read from `recurring_items`.
 *
 * These used to be a `transaction_templates` row plus a `recurring_rules` row.
 * They are now a single self-sufficient row (see src/recurring/engine.ts and
 * migration 0064), which is what lets the Templates feature be removed without
 * taking every recurring commitment with it.
 *
 * `RecurringItem` keeps its shape so the /recurring page and its components did
 * not all need rewriting; `ruleId` and `templateId` are both the item's id now,
 * which keeps existing call sites honest while they still pass a pair around.
 */
import { useQuery } from "@powersync/react";
import {
  RECURRING_COLUMNS, createRecurring as create, updateRecurring as update,
  removeRecurring as remove, typeForDirection,
  type Freq, type RecurringDirection, type RecurringInput, type RecurringRow,
} from "../recurring/engine";

export type { RecurringDirection, RecurringInput, Freq };
export { typeForDirection };

export interface RecurringItem {
  ruleId: string;
  templateId: string;
  direction: RecurringDirection;
  name: string;
  amount: number;
  currency: string;
  frequency: string;
  next_due: string;
  account_id: string | null;
  to_account_id: string | null;
  category_id: string | null;
  group_id: string | null;
  auto_post: number;
  alert_time_utc: string | null;
}

const directionOf = (d: string): RecurringDirection =>
  d === "income" ? "income" : d === "saving" ? "saving" : "payment";

export function useRecurringItems(): RecurringItem[] {
  const { data = [] } = useQuery<RecurringRow>(
    `SELECT ${RECURRING_COLUMNS} FROM recurring_items
      WHERE deleted_at IS NULL AND active = 1 ORDER BY next_due`,
  );
  return data.map((d) => ({
    ruleId: d.id,
    templateId: d.id,
    direction: directionOf(d.direction),
    name: d.name,
    amount: d.amount ?? 0,
    currency: d.currency ?? "",
    frequency: d.frequency,
    next_due: d.next_due,
    account_id: d.account_id,
    to_account_id: d.to_account_id,
    category_id: d.category_id,
    group_id: d.group_id,
    auto_post: d.auto_post,
    alert_time_utc: d.alert_time_utc,
  }));
}

export const createRecurring = create;

/** Signature keeps both ids so callers need no change; they are the same row. */
export async function updateRecurring(ruleId: string, _templateId: string, inp: RecurringInput): Promise<void> {
  await update(ruleId, inp);
}

export async function removeRecurring(ruleId: string, _templateId?: string): Promise<void> {
  await remove(ruleId);
}
