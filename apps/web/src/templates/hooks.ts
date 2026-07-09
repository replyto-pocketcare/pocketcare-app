"use client";

import { useQuery } from "@powersync/react";

export interface Template {
  id: string; name: string; type: string; amount: number | null; currency: string | null;
  account_id: string | null; to_account_id: string | null; category_id: string | null;
  description: string | null; note: string | null; payment_method: string | null; labels: string | null;
  split_group_id: string | null; split_mode: string | null;
}

export function useTemplates(): Template[] {
  const { data = [] } = useQuery<Template>(
    "SELECT id, name, type, amount, currency, account_id, to_account_id, category_id, description, note, payment_method, labels, split_group_id, split_mode FROM transaction_templates WHERE deleted_at IS NULL ORDER BY name",
  );
  return data;
}

export interface RecurringRule {
  id: string; template_id: string; template_name: string; type: string; amount: number | null; currency: string | null;
  frequency: string; interval_count: number; next_due: string; auto_post: number; active: number;
}

export function useRules(): RecurringRule[] {
  const { data = [] } = useQuery<RecurringRule>(
    `SELECT r.id, r.template_id, t.name AS template_name, t.type AS type, t.amount AS amount, t.currency AS currency,
            r.frequency, r.interval_count, r.next_due, r.auto_post, r.active
     FROM recurring_rules r JOIN transaction_templates t ON t.id = r.template_id
     WHERE r.deleted_at IS NULL AND t.deleted_at IS NULL ORDER BY r.next_due`,
  );
  return data;
}

/** Rules that are due and require confirmation (auto_post = 0). */
export function useDueRules(): RecurringRule[] {
  const today = new Date().toISOString().slice(0, 10);
  const { data = [] } = useQuery<RecurringRule>(
    `SELECT r.id, r.template_id, t.name AS template_name, t.type AS type, t.amount AS amount, t.currency AS currency,
            r.frequency, r.interval_count, r.next_due, r.auto_post, r.active
     FROM recurring_rules r JOIN transaction_templates t ON t.id = r.template_id
     WHERE r.deleted_at IS NULL AND t.deleted_at IS NULL AND r.active = 1 AND r.auto_post = 0 AND r.next_due <= ?
     ORDER BY r.next_due`,
    [today],
  );
  return data;
}
