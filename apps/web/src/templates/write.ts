"use client";

import { money, fromMajor, type Money } from "@pocketcare/money";
import type { CurrencyCode } from "@pocketcare/types";
import { getDb, getRepositories, getUserId } from "../powersync";
import { insertRow, updateRow } from "../write";
import { getBaseCurrency } from "../prefs";
import { createSplitExpense } from "../splits/write";

export type Freq = "daily" | "weekly" | "monthly" | "yearly";

/** Free plans can keep up to this many templates; Premium is unlimited. */
export const FREE_TEMPLATE_LIMIT = 5;

export interface TemplateInput {
  name: string;
  type: "expense" | "income" | "transfer";
  amount?: number | null;        // major units; null = ask at use time
  accountId?: string | null;
  toAccountId?: string | null;
  categoryId?: string | null;
  description?: string | null;
  note?: string | null;
  paymentMethod?: string | null;
  labels?: string[];
  splitGroupId?: string | null;
  splitMode?: "equal" | "exact" | "percent";
}

export async function createTemplate(t: TemplateInput): Promise<string> {
  const cur = getBaseCurrency();
  const db = getDb();
  const max = await db?.getOptional<{ s: number }>("SELECT MAX(IFNULL(sort,0)) AS s FROM transaction_templates WHERE deleted_at IS NULL");
  return insertRow("transaction_templates", {
    name: t.name.trim(), type: t.type,
    amount: t.amount != null ? fromMajor(t.amount, cur as CurrencyCode).amount : null,
    currency: cur, account_id: t.accountId ?? null, to_account_id: t.toAccountId ?? null,
    category_id: t.categoryId ?? null, description: t.description ?? null, note: t.note ?? null,
    payment_method: t.paymentMethod ?? null, labels: t.labels?.length ? t.labels.join(", ") : null,
    split_group_id: t.splitGroupId ?? null, split_mode: t.splitMode ?? "equal",
    sort: (max?.s ?? 0) + 1,
  });
}

/** Update an existing template's fields. */
export async function updateTemplate(id: string, t: TemplateInput): Promise<void> {
  const cur = getBaseCurrency();
  await updateRow("transaction_templates", id, {
    name: t.name.trim(), type: t.type,
    amount: t.amount != null ? fromMajor(t.amount, cur as CurrencyCode).amount : null,
    account_id: t.accountId ?? null, to_account_id: t.toAccountId ?? null,
    category_id: t.categoryId ?? null, description: t.description ?? null, note: t.note ?? null,
    payment_method: t.paymentMethod ?? null, labels: t.labels?.length ? t.labels.join(", ") : null,
    split_group_id: t.splitGroupId ?? null, split_mode: t.splitMode ?? "equal",
  });
}

/** Persist a new order (writes sort = position for each id). */
export async function reorderTemplates(orderedIds: string[]): Promise<void> {
  for (let i = 0; i < orderedIds.length; i++) await updateRow("transaction_templates", orderedIds[i]!, { sort: i });
}

export interface TemplateRow {
  id: string; name: string; type: string; amount: number | null; currency: string | null;
  account_id: string | null; to_account_id: string | null; category_id: string | null;
  description: string | null; note: string | null; payment_method: string | null; labels: string | null;
  split_group_id: string | null; split_mode: string | null;
}

/** Create a transaction (or equal split) from a template, dated at `occurredAtIso`. */
export async function materializeTemplate(tpl: TemplateRow, occurredAtIso: string): Promise<void> {
  const cur = (tpl.currency || getBaseCurrency()) as CurrencyCode;
  const total: Money = money(tpl.amount ?? 0, cur);
  const db = getDb();

  // Recurring split: equal split among current group members, you pay.
  if (tpl.split_group_id && tpl.account_id && db) {
    const members = await db.getAll<{ user_id: string }>(
      "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL", [tpl.split_group_id],
    );
    const ids = members.map((m) => m.user_id);
    if (ids.length >= 2) {
      await createSplitExpense({
        groupId: tpl.split_group_id, mode: "equal", total,
        participants: ids.map((id) => ({ userId: id })),
        payers: [{ userId: getUserId(), paid: total.amount, accountId: tpl.account_id }],
        categoryId: tpl.category_id, description: tpl.description, note: tpl.note, occurredAt: occurredAtIso,
      });
      return;
    }
  }

  const repos = getRepositories();
  const labels = tpl.labels ? tpl.labels.split(",").map((s) => s.trim()).filter(Boolean) : undefined;
  if (tpl.type === "transfer" && tpl.to_account_id && tpl.account_id) {
    await repos.transactions.create({ account_id: tpl.account_id, type: "transfer", amount: total, to_account_id: tpl.to_account_id, note: tpl.note, occurred_at: occurredAtIso });
  } else if (tpl.account_id) {
    await repos.transactions.create({
      account_id: tpl.account_id, type: tpl.type === "income" ? "income" : "expense", amount: total,
      category_id: tpl.category_id, description: tpl.description, note: tpl.note, payment_method: tpl.payment_method,
      labels: labels ?? [], occurred_at: occurredAtIso,
    });
  }
}

// ---- recurring rules ----
export async function createRule(opts: { templateId: string; frequency: Freq; intervalCount?: number; firstDue: string; autoPost?: boolean }): Promise<string> {
  return insertRow("recurring_rules", {
    template_id: opts.templateId, frequency: opts.frequency, interval_count: opts.intervalCount ?? 1,
    next_due: opts.firstDue, last_generated: null, auto_post: opts.autoPost ? 1 : 0, active: 1,
  });
}

function advance(dateStr: string, freq: Freq, n: number): string {
  const d = new Date(dateStr + "T00:00:00");
  if (freq === "daily") d.setDate(d.getDate() + n);
  else if (freq === "weekly") d.setDate(d.getDate() + 7 * n);
  else if (freq === "monthly") d.setMonth(d.getMonth() + n);
  else d.setFullYear(d.getFullYear() + n);
  return d.toISOString().slice(0, 10);
}

const dueIso = (day: string) => `${day}T12:00:00.000Z`;

interface RuleRow { id: string; template_id: string; frequency: Freq; interval_count: number; next_due: string }

/** Post one occurrence of a rule now and advance it (used by "Post now" / confirming a due rule). */
export async function postRuleOnce(ruleId: string): Promise<void> {
  const db = getDb(); if (!db) return;
  const r = await db.getOptional<RuleRow>("SELECT id, template_id, frequency, interval_count, next_due FROM recurring_rules WHERE id = ? AND deleted_at IS NULL", [ruleId]);
  if (!r) return;
  const tpl = await db.getOptional<TemplateRow>("SELECT * FROM transaction_templates WHERE id = ? AND deleted_at IS NULL", [r.template_id]);
  if (!tpl) return;
  await materializeTemplate(tpl, dueIso(r.next_due));
  await updateRow("recurring_rules", r.id, { next_due: advance(r.next_due, r.frequency, r.interval_count || 1), last_generated: r.next_due });
}

/** Skip one occurrence of a due rule without posting (just advance next_due). */
export async function skipRuleOnce(ruleId: string): Promise<void> {
  const db = getDb(); if (!db) return;
  const r = await db.getOptional<RuleRow>("SELECT id, template_id, frequency, interval_count, next_due FROM recurring_rules WHERE id = ? AND deleted_at IS NULL", [ruleId]);
  if (!r) return;
  await updateRow("recurring_rules", r.id, { next_due: advance(r.next_due, r.frequency, r.interval_count || 1) });
}

/**
 * Generate-on-open: auto-post every AUTO rule that's due (catching up missed
 * occurrences, capped). Non-auto due rules are left for the user to confirm
 * (surfaced via useDueRules). Returns how many transactions were posted.
 */
export async function runRecurring(): Promise<number> {
  const db = getDb(); if (!db) return 0;
  const today = new Date().toISOString().slice(0, 10);
  const rules = await db.getAll<RuleRow>(
    "SELECT id, template_id, frequency, interval_count, next_due FROM recurring_rules WHERE deleted_at IS NULL AND active = 1 AND auto_post = 1 AND next_due <= ?",
    [today],
  );
  let posted = 0;
  for (const r of rules) {
    const tpl = await db.getOptional<TemplateRow>("SELECT * FROM transaction_templates WHERE id = ? AND deleted_at IS NULL", [r.template_id]);
    if (!tpl) continue;
    let due = r.next_due;
    let guard = 0;
    while (due <= today && guard++ < 24) {
      try {
        await materializeTemplate(tpl, dueIso(due));
      } catch {
        // e.g. an overdraft-blocked auto-post: leave next_due where it is so it
        // shows as still-due, and move on to other rules instead of stalling.
        break;
      }
      const next = advance(due, r.frequency, r.interval_count || 1);
      await updateRow("recurring_rules", r.id, { next_due: next, last_generated: due });
      due = next;
      posted++;
    }
  }
  return posted;
}
