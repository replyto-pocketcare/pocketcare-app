"use client";

import { useMemo } from "react";
import { useQuery } from "@powersync/react";
import { contactEdges, type PartyAgg } from "./math";

export interface Contact {
  id: string;
  name: string;
  email: string | null;
  avatar_color: string | null;
}

/** Active (non-archived) contacts you split with. */
export function useContacts(): Contact[] {
  const { data = [] } = useQuery<Contact>(
    "SELECT id, name, email, avatar_color FROM contacts WHERE deleted_at IS NULL AND IFNULL(archived,0) = 0 ORDER BY name",
  );
  return data;
}

export interface FriendBalance {
  contactId: string;
  /** Minor units. Positive = they owe you; negative = you owe them. */
  net: number;
}

/**
 * Per-contact running balance, derived (never materialised, so offline merges
 * can't corrupt it): pairwise edges from every expense's shares+payers, minus
 * settlements. Works for multi-payer and contact-paid splits.
 */
export function useFriendBalances(): FriendBalance[] {
  const { data: shares = [] } = useQuery<{ expense_id: string; contact_id: string | null; share_amount: number }>(
    "SELECT expense_id, contact_id, share_amount FROM shared_expense_shares WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM shared_expenses WHERE deleted_at IS NULL)",
  );
  const { data: payers = [] } = useQuery<{ expense_id: string; contact_id: string | null; paid_amount: number }>(
    "SELECT expense_id, contact_id, paid_amount FROM shared_expense_payers WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM shared_expenses WHERE deleted_at IS NULL)",
  );
  const { data: settlements = [] } = useQuery<{ contact_id: string; direction: string; amount: number }>(
    "SELECT contact_id, direction, amount FROM settlements WHERE deleted_at IS NULL",
  );

  return useMemo(() => {
    // Group shares + payers by expense into party aggregates.
    const byExpense = new Map<string, Map<string | null, { share: number; paid: number }>>();
    const bucket = (eid: string, cid: string | null) => {
      let m = byExpense.get(eid);
      if (!m) { m = new Map(); byExpense.set(eid, m); }
      let p = m.get(cid);
      if (!p) { p = { share: 0, paid: 0 }; m.set(cid, p); }
      return p;
    };
    for (const s of shares) bucket(s.expense_id, s.contact_id).share += s.share_amount;
    for (const p of payers) bucket(p.expense_id, p.contact_id).paid += p.paid_amount;

    const net = new Map<string, number>();
    for (const [, parties] of byExpense) {
      const arr: PartyAgg[] = [...parties.entries()].map(([id, v]) => ({ id, share: v.share, paid: v.paid }));
      for (const e of contactEdges(arr)) net.set(e.id, (net.get(e.id) ?? 0) + e.amount);
    }
    // Apply settlements: received reduces what they owe; paid reduces what you owe.
    for (const s of settlements) {
      const delta = s.direction === "received" ? -s.amount : s.amount;
      net.set(s.contact_id, (net.get(s.contact_id) ?? 0) + delta);
    }
    return [...net.entries()].map(([contactId, n]) => ({ contactId, net: n }));
  }, [shares, payers, settlements]);
}

// ---------------- Groups / trips ----------------

export interface Group {
  id: string;
  name: string;
  kind: string;              // 'group' | 'trip'
  start_date: string | null;
  end_date: string | null;
  auto_split: number;
  default_mode: string;
  currency: string;
}

export function useGroups(): Group[] {
  const { data = [] } = useQuery<Group>(
    "SELECT id, name, kind, start_date, end_date, auto_split, default_mode, currency FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 ORDER BY created_at DESC",
  );
  return data;
}

export function useGroup(id: string): Group | null {
  const { data = [] } = useQuery<Group>(
    "SELECT id, name, kind, start_date, end_date, auto_split, default_mode, currency FROM split_groups WHERE id = ? AND deleted_at IS NULL",
    [id],
  );
  return data[0] ?? null;
}

/** Contact ids that are members of a group (excludes self). */
export function useGroupMemberContactIds(groupId: string): string[] {
  const { data = [] } = useQuery<{ contact_id: string | null }>(
    "SELECT contact_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL AND contact_id IS NOT NULL",
    [groupId],
  );
  return data.map((r) => r.contact_id!).filter(Boolean);
}

export interface GroupExpense {
  id: string;
  description: string | null;
  total_amount: number;
  currency: string;
  occurred_at: string;
}
export function useGroupExpenses(groupId: string): GroupExpense[] {
  const { data = [] } = useQuery<GroupExpense>(
    "SELECT id, description, total_amount, currency, occurred_at FROM shared_expenses WHERE group_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC",
    [groupId],
  );
  return data;
}

/** Per-contact balance WITHIN a group (gross of global settlements). */
export function useGroupBalances(groupId: string): FriendBalance[] {
  const { data: shares = [] } = useQuery<{ expense_id: string; contact_id: string | null; share_amount: number }>(
    "SELECT s.expense_id, s.contact_id, s.share_amount FROM shared_expense_shares s JOIN shared_expenses e ON e.id = s.expense_id WHERE e.group_id = ? AND s.deleted_at IS NULL AND e.deleted_at IS NULL",
    [groupId],
  );
  const { data: payers = [] } = useQuery<{ expense_id: string; contact_id: string | null; paid_amount: number }>(
    "SELECT p.expense_id, p.contact_id, p.paid_amount FROM shared_expense_payers p JOIN shared_expenses e ON e.id = p.expense_id WHERE e.group_id = ? AND p.deleted_at IS NULL AND e.deleted_at IS NULL",
    [groupId],
  );
  return useMemo(() => {
    const byExpense = new Map<string, Map<string | null, { share: number; paid: number }>>();
    const bucket = (eid: string, cid: string | null) => {
      let m = byExpense.get(eid);
      if (!m) { m = new Map(); byExpense.set(eid, m); }
      let p = m.get(cid);
      if (!p) { p = { share: 0, paid: 0 }; m.set(cid, p); }
      return p;
    };
    for (const s of shares) bucket(s.expense_id, s.contact_id).share += s.share_amount;
    for (const p of payers) bucket(p.expense_id, p.contact_id).paid += p.paid_amount;
    const net = new Map<string, number>();
    for (const [, parties] of byExpense) {
      const arr: PartyAgg[] = [...parties.entries()].map(([id, v]) => ({ id, share: v.share, paid: v.paid }));
      for (const e of contactEdges(arr)) net.set(e.id, (net.get(e.id) ?? 0) + e.amount);
    }
    return [...net.entries()].map(([contactId, n]) => ({ contactId, net: n }));
  }, [shares, payers]);
}
