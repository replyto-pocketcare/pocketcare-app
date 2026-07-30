"use client";

/**
 * Recurring groups — the buckets behind the three sections on /recurring.
 *
 * Plan: docs/plans/ui-redesign-2026-07.md §3.
 *
 * The invariant is **every recurring item belongs to a group**. It is enforced
 * here and in the UI, NOT by a `NOT NULL` + foreign key in Postgres — see the
 * long comment in migration 0046 for why (two rows, two upload transactions,
 * head-of-line block). `pocketcare.audit_ungrouped_recurring()` makes any
 * violation observable server-side.
 */

import { useMemo } from "react";
import { useQuery } from "@powersync/react";
import { getDb, getUserId } from "../powersync";
import { insertRow, updateRow, softDelete } from "../write";
import type { MaterialIconName } from "../ui/MaterialIcon";
import type { RecurringDirection } from "../cashflow/recurring";

export interface RecurringGroup {
  id: string;
  name: string;
  direction: RecurringDirection;
  icon: string | null;
  color: string | null;
  sort: number | null;
  is_system: number | null;
}

/**
 * Seeded defaults.
 *
 * Labels are taken from the existing `BUCKETS` taxonomy in
 * `src/cashflow/model.ts`, which Planned Cashflow and the dashboard's
 * upcoming-payments tile already use. Inventing a second set of names for the
 * same idea would leave the two screens quietly disagreeing.
 */
export const DEFAULT_GROUPS: Record<RecurringDirection, { slug: string; name: string; icon: MaterialIconName }[]> = {
  income: [
    { slug: "salary", name: "Salary", icon: "work" },
    { slug: "freelance", name: "Freelance", icon: "payments" },
    { slug: "rental", name: "Rental", icon: "apartment" },
    { slug: "dividends", name: "Dividends & interest", icon: "trending_up" },
    { slug: "other-income", name: "Other income", icon: "more_horiz" },
  ],
  payment: [
    { slug: "household", name: "Household", icon: "home" },
    { slug: "subscription", name: "Subscription", icon: "subscriptions" },
    { slug: "loan", name: "Loan / EMI", icon: "request_quote" },
    { slug: "insurance", name: "Insurance", icon: "health_and_safety" },
    { slug: "transport", name: "Transport", icon: "directions_car" },
    { slug: "other-payment", name: "Other", icon: "more_horiz" },
  ],
  saving: [
    { slug: "sip", name: "SIP", icon: "autorenew" },
    { slug: "fd", name: "Fixed Deposit", icon: "savings" },
    { slug: "emergency", name: "Emergency Fund", icon: "health_and_safety" },
    { slug: "mutual_fund", name: "Mutual Fund", icon: "pie_chart" },
    { slug: "stocks", name: "Stocks", icon: "show_chart" },
    { slug: "crypto", name: "Crypto", icon: "currency_bitcoin" },
    { slug: "other-saving", name: "Other", icon: "more_horiz" },
  ],
};

/**
 * A stable UUID for (user, slug) — the same inputs always give the same id.
 *
 * This is what makes seeding safe on two devices at once: both produce
 * identical rows, so the connector's array upsert treats the second as a no-op
 * instead of a primary-key violation, which would be classified permanent and
 * quarantined.
 *
 * SHA-1 based, in the shape of UUID v5 (RFC 4122 §4.3). Not a security
 * primitive — it only needs to be deterministic and collision-free in practice.
 */
async function deterministicId(userId: string, slug: string): Promise<string> {
  const data = new TextEncoder().encode(`pocketcare:recurring-group:${userId}:${slug}`);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-1", data));
  const b = digest.slice(0, 16);
  b[6] = (b[6]! & 0x0f) | 0x50; // version 5
  b[8] = (b[8]! & 0x3f) | 0x80; // RFC 4122 variant
  const hex = [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

export function useRecurringGroups(): RecurringGroup[] {
  const { data = [] } = useQuery<RecurringGroup>(
    `SELECT id, name, direction, icon, color, sort, is_system
       FROM recurring_groups WHERE deleted_at IS NULL
      ORDER BY sort, name COLLATE NOCASE`,
  );
  return data;
}

export function useGroupsByDirection(): Record<RecurringDirection, RecurringGroup[]> {
  const groups = useRecurringGroups();
  return useMemo(() => ({
    income: groups.filter((g) => g.direction === "income"),
    payment: groups.filter((g) => g.direction === "payment"),
    saving: groups.filter((g) => g.direction === "saving"),
  }), [groups]);
}

/**
 * Create the default groups, once, idempotently.
 *
 * Guarded on "has this user any system group at all" rather than per-slug, so a
 * user who deletes the defaults doesn't get them silently resurrected on the
 * next visit — deleting them was a decision.
 */
export async function ensureDefaultGroups(): Promise<void> {
  const db = getDb();
  if (!db) return;
  const existing = await db.getOptional<{ c: number }>(
    "SELECT COUNT(*) AS c FROM recurring_groups WHERE deleted_at IS NULL",
  );
  if ((existing?.c ?? 0) > 0) return;

  // Anything already grouped means seeding has happened before on some device
  // and the rows just haven't synced down yet. Don't race them.
  const grouped = await db.getOptional<{ c: number }>(
    "SELECT COUNT(*) AS c FROM transaction_templates WHERE deleted_at IS NULL AND group_id IS NOT NULL",
  );
  if ((grouped?.c ?? 0) > 0) return;

  const userId = getUserId();
  let sort = 0;
  for (const direction of ["income", "payment", "saving"] as const) {
    for (const def of DEFAULT_GROUPS[direction]) {
      const id = await deterministicId(userId, `${direction}:${def.slug}`);
      await insertRow("recurring_groups", {
        id, name: def.name, direction, icon: def.icon, color: null,
        sort: sort++, is_system: 1,
      });
    }
  }
}

export async function createGroup(input: { name: string; direction: RecurringDirection; icon?: MaterialIconName }): Promise<string> {
  return insertRow("recurring_groups", {
    name: input.name.trim(),
    direction: input.direction,
    icon: input.icon ?? "folder",
    color: null,
    sort: 999,
    is_system: 0,
  });
}

export async function renameGroup(id: string, name: string): Promise<void> {
  await updateRow("recurring_groups", id, { name: name.trim() });
}

/**
 * Delete a group, moving its items somewhere first.
 *
 * `moveTo` is REQUIRED when the group has items — a group is never deleted out
 * from under them, because "nothing may be ungrouped" is the whole point. The
 * caller (the delete dialog) is what enforces choosing a destination; this
 * throws if it didn't, so the rule can't be bypassed by a future caller.
 */
export async function deleteGroup(id: string, moveTo: string | null): Promise<void> {
  const db = getDb();
  if (!db) return;
  const items = await db.getAll<{ id: string }>(
    "SELECT id FROM transaction_templates WHERE group_id = ? AND deleted_at IS NULL",
    [id],
  );
  if (items.length > 0) {
    if (!moveTo) throw new Error("Choose where to move this group's items before deleting it.");
    for (const it of items) await updateRow("transaction_templates", it.id, { group_id: moveTo });
  }
  await softDelete("recurring_groups", id);
}

/** Assign one recurring item (by its template id) to a group. */
export async function assignGroup(templateId: string, groupId: string): Promise<void> {
  await updateRow("transaction_templates", templateId, { group_id: groupId });
}

/**
 * Best-effort suggestion for a legacy item with no group, used to pre-select
 * the triage picker. Name-based and deliberately shallow — a wrong guess the
 * user can see and change beats an invisible one.
 */
export function suggestGroup(name: string, groups: RecurringGroup[]): RecurringGroup | null {
  const n = name.toLowerCase();
  const hit = (...words: string[]) => words.some((w) => n.includes(w));
  const bySlugName = (label: string) => groups.find((g) => g.name.toLowerCase() === label.toLowerCase()) ?? null;

  if (hit("netflix", "prime", "spotify", "hotstar", "youtube", "subscription", "membership")) return bySlugName("Subscription");
  if (hit("rent", "electric", "water", "gas", "broadband", "internet", "maid", "grocer")) return bySlugName("Household");
  if (hit("emi", "loan", "mortgage")) return bySlugName("Loan / EMI");
  if (hit("insurance", "premium", "lic", "mediclaim")) return bySlugName("Insurance");
  if (hit("petrol", "fuel", "metro", "uber", "ola", "cab")) return bySlugName("Transport");
  if (hit("salary", "payroll")) return bySlugName("Salary");
  if (hit("freelance", "consult", "invoice")) return bySlugName("Freelance");
  if (hit("dividend", "interest")) return bySlugName("Dividends & interest");
  if (hit("sip")) return bySlugName("SIP");
  if (hit("fd", "fixed deposit")) return bySlugName("Fixed Deposit");
  if (hit("mutual")) return bySlugName("Mutual Fund");
  return null;
}

/**
 * Pick a group for an item created OUTSIDE the recurring modal — e.g. the
 * statement analyzer turning a detected pattern into a recurring payment.
 *
 * Those call sites have no group picker, but the invariant still holds: seed
 * the defaults if needed, guess from the name, and fall back to the direction's
 * "Other" bucket. Returning null would put an item on the triage strip, which
 * is for legacy rows — not for something we just created.
 */
export async function resolveGroupForImport(direction: RecurringDirection, name: string): Promise<string> {
  await ensureDefaultGroups();
  const db = getDb();
  if (!db) throw new Error("DB not ready");
  const groups = await db.getAll<RecurringGroup>(
    "SELECT id, name, direction, icon, color, sort, is_system FROM recurring_groups WHERE deleted_at IS NULL AND direction = ?",
    [direction],
  );
  const guess = suggestGroup(name, groups);
  if (guess) return guess.id;
  const other = groups.find((g) => /^other/i.test(g.name));
  if (other) return other.id;
  if (groups[0]) return groups[0].id;
  // Every default was deleted — make one rather than leaving the item orphaned.
  return createGroup({ name: "Other", direction });
}
