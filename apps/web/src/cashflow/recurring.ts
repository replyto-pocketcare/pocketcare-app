"use client";

/**
 * Recurring-rule-backed Planned Cashflow items. Instead of standalone
 * planned_cashflow rows, incomes / payments / savings are real recurring rules
 * (a `transaction_templates` row + a `recurring_rules` row) that actually post
 * transactions via the recurring engine. Direction maps to the template type:
 *   income  → income template
 *   payment → expense template
 *   saving  → transfer template (into an investment account)
 */
import { useQuery } from "@powersync/react";
import type { Freq } from "../templates/write";
import { createTemplate, createRule, updateTemplate } from "../templates/write";
import { updateRow, softDelete } from "../write";

export type RecurringDirection = "income" | "payment" | "saving";

export interface RecurringItem {
  ruleId: string;
  templateId: string;
  direction: RecurringDirection;
  name: string;
  amount: number;         // minor units, in `currency`
  currency: string;
  frequency: string;      // daily | weekly | monthly | yearly
  next_due: string;
  account_id: string | null;
  to_account_id: string | null;
  category_id: string | null;
  auto_post: number;
}

const directionOf = (type: string): RecurringDirection =>
  type === "income" ? "income" : type === "transfer" ? "saving" : "payment";

export const typeForDirection = (d: RecurringDirection): "income" | "expense" | "transfer" =>
  d === "income" ? "income" : d === "saving" ? "transfer" : "expense";

interface Row {
  ruleId: string; templateId: string; type: string; name: string; amount: number | null; currency: string | null;
  account_id: string | null; to_account_id: string | null; category_id: string | null;
  frequency: string; next_due: string; auto_post: number;
}

export function useRecurringItems(): RecurringItem[] {
  const { data = [] } = useQuery<Row>(
    `SELECT r.id AS ruleId, r.template_id AS templateId, t.type AS type, t.name AS name,
            t.amount AS amount, t.currency AS currency, t.account_id AS account_id,
            t.to_account_id AS to_account_id, t.category_id AS category_id,
            r.frequency AS frequency, r.next_due AS next_due, r.auto_post AS auto_post
     FROM recurring_rules r JOIN transaction_templates t ON t.id = r.template_id
     WHERE r.deleted_at IS NULL AND t.deleted_at IS NULL AND r.active = 1
     ORDER BY r.next_due`,
  );
  return data.map((d) => ({
    ruleId: d.ruleId, templateId: d.templateId, direction: directionOf(d.type),
    name: d.name, amount: d.amount ?? 0, currency: d.currency ?? "",
    frequency: d.frequency, next_due: d.next_due, account_id: d.account_id,
    to_account_id: d.to_account_id, category_id: d.category_id, auto_post: d.auto_post,
  }));
}

export interface RecurringInput {
  direction: RecurringDirection;
  name: string;
  amount: number;              // major units
  accountId: string | null;
  toAccountId?: string | null; // saving → destination investment account
  categoryId?: string | null;  // payment → optional category
  frequency: Freq;
  firstDue: string;            // YYYY-MM-DD
  autoPost: boolean;
}

/** Create a recurring item = a template + a recurring rule, in one step. */
export async function createRecurring(inp: RecurringInput): Promise<string> {
  const templateId = await createTemplate({
    name: inp.name,
    type: typeForDirection(inp.direction),
    amount: inp.amount,
    accountId: inp.accountId,
    toAccountId: inp.toAccountId ?? null,
    categoryId: inp.categoryId ?? null,
  });
  return createRule({ templateId, frequency: inp.frequency, firstDue: inp.firstDue, autoPost: inp.autoPost });
}

/** Update the template + rule behind a recurring item. */
export async function updateRecurring(ruleId: string, templateId: string, inp: RecurringInput): Promise<void> {
  await updateTemplate(templateId, {
    name: inp.name,
    type: typeForDirection(inp.direction),
    amount: inp.amount,
    accountId: inp.accountId,
    toAccountId: inp.toAccountId ?? null,
    categoryId: inp.categoryId ?? null,
  });
  await updateRow("recurring_rules", ruleId, { frequency: inp.frequency, next_due: inp.firstDue, auto_post: inp.autoPost ? 1 : 0 });
}

/** Soft-delete both the rule and its template. */
export async function removeRecurring(ruleId: string, templateId: string): Promise<void> {
  await softDelete("recurring_rules", ruleId);
  await softDelete("transaction_templates", templateId);
}
