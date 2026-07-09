"use client";

import { useMemo } from "react";
import { useQuery } from "@powersync/react";
import { getUserId } from "../powersync";
import { pairwiseEdges, type Party } from "./math";

export function useMyUserId(): string {
  try { return getUserId(); } catch { return ""; }
}

export interface UserProfile { id: string; name: string; email: string | null }

/** All users we can see (self + co-members + connections), for display. */
export function useUserProfiles(): Map<string, UserProfile> {
  const { data = [] } = useQuery<{ id: string; display_name: string | null; email: string | null }>(
    "SELECT id, display_name, email FROM profiles",
  );
  return useMemo(() => {
    const m = new Map<string, UserProfile>();
    for (const p of data) m.set(p.id, { id: p.id, name: p.display_name || (p.email ? p.email.split("@")[0]! : "Someone"), email: p.email });
    return m;
  }, [data]);
}

/** Users you're connected to (accepted invites / shared groups). */
export function useConnections(): UserProfile[] {
  const me = useMyUserId();
  const { data = [] } = useQuery<{ id: string; display_name: string | null; email: string | null }>(
    `SELECT p.id AS id, p.display_name AS display_name, p.email AS email
     FROM connections c
     JOIN profiles p ON p.id = (CASE WHEN c.user_a = ? THEN c.user_b ELSE c.user_a END)
     WHERE c.deleted_at IS NULL AND (c.user_a = ? OR c.user_b = ?)`,
    [me, me, me],
  );
  return data.map((p) => ({ id: p.id, name: p.display_name || (p.email ? p.email.split("@")[0]! : "Someone"), email: p.email }));
}

export interface Group {
  id: string; created_by: string; name: string; kind: string; is_direct: number;
  start_date: string | null; end_date: string | null; auto_split: number; default_mode: string; currency: string;
}
export function useGroups(includeDirect = false): Group[] {
  const { data = [] } = useQuery<Group>(
    `SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
     FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 ${includeDirect ? "" : "AND IFNULL(is_direct,0)=0"} ORDER BY created_at DESC`,
  );
  return data;
}
export function useGroup(id: string): Group | null {
  const { data = [] } = useQuery<Group>(
    "SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency FROM split_groups WHERE id = ? AND deleted_at IS NULL",
    [id],
  );
  return data[0] ?? null;
}

export function useGroupMemberIds(groupId: string): string[] {
  const { data = [] } = useQuery<{ user_id: string }>(
    "SELECT user_id FROM split_group_members WHERE group_id = ? AND deleted_at IS NULL ORDER BY created_at",
    [groupId],
  );
  return data.map((r) => r.user_id);
}

export interface GroupExpense { id: string; description: string | null; amount: number; currency: string; occurred_at: string }
export function useGroupExpenses(groupId: string): GroupExpense[] {
  const { data = [] } = useQuery<GroupExpense>(
    "SELECT id, description, amount, currency, occurred_at FROM expenses WHERE group_id = ? AND deleted_at IS NULL ORDER BY occurred_at DESC",
    [groupId],
  );
  return data;
}

export interface FriendBalance { userId: string; net: number } // + = they owe you

function computeBalances(
  parts: { expense_id: string; user_id: string; paid_amount: number; share_amount: number }[],
  settlements: { from_user: string; to_user: string; amount: number }[],
  me: string,
): FriendBalance[] {
  const byExpense = new Map<string, Party[]>();
  for (const p of parts) {
    const arr = byExpense.get(p.expense_id) ?? [];
    arr.push({ userId: p.user_id, share: p.share_amount, paid: p.paid_amount });
    byExpense.set(p.expense_id, arr);
  }
  const net = new Map<string, number>();
  for (const [, parties] of byExpense) {
    for (const e of pairwiseEdges(parties, me)) net.set(e.userId, (net.get(e.userId) ?? 0) + e.amount);
  }
  for (const s of settlements) {
    if (s.to_user === me) net.set(s.from_user, (net.get(s.from_user) ?? 0) - s.amount);      // they paid me back
    else if (s.from_user === me) net.set(s.to_user, (net.get(s.to_user) ?? 0) + s.amount);   // I paid them
  }
  return [...net.entries()].map(([userId, n]) => ({ userId, net: n }));
}

/** Global per-user balances across all your groups. */
export function useFriendBalances(): FriendBalance[] {
  const me = useMyUserId();
  const { data: parts = [] } = useQuery<{ expense_id: string; user_id: string; paid_amount: number; share_amount: number }>(
    "SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL AND expense_id IN (SELECT id FROM expenses WHERE deleted_at IS NULL)",
  );
  const { data: setts = [] } = useQuery<{ from_user: string; to_user: string; amount: number }>(
    "SELECT from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL",
  );
  return useMemo(() => computeBalances(parts, setts, me), [parts, setts, me]);
}

/** Per-user balances within a single group. */
export function useGroupBalances(groupId: string): FriendBalance[] {
  const me = useMyUserId();
  const { data: parts = [] } = useQuery<{ expense_id: string; user_id: string; paid_amount: number; share_amount: number }>(
    "SELECT expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE group_id = ? AND deleted_at IS NULL",
    [groupId],
  );
  const { data: setts = [] } = useQuery<{ from_user: string; to_user: string; amount: number }>(
    "SELECT from_user, to_user, amount FROM settlements WHERE group_id = ? AND deleted_at IS NULL",
    [groupId],
  );
  return useMemo(() => computeBalances(parts, setts, me), [parts, setts, me]);
}
