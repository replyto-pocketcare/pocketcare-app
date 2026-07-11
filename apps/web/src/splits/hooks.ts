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

export interface GroupOverview {
  group: Group;
  memberIds: string[];       // other members (excludes you), in join order
  peopleCount: number;       // total members incl. you
  net: number;               // your net within this group (+ = you're owed)
  perUser: FriendBalance[];  // your balance vs each member in this group
}
export interface SplitOverview {
  netPosition: number; // owed - owe across everything
  owed: number;
  owe: number;
  groups: GroupOverview[];   // non-direct groups & trips
  direct: FriendBalance[];   // aggregated 1:1 balances (+ = they owe you)
}

/** Everything the Splits ledger needs, computed in one pass. */
export function useSplitOverview(): SplitOverview {
  const me = useMyUserId();
  const { data: groups = [] } = useQuery<Group>(
    `SELECT id, created_by, name, kind, is_direct, start_date, end_date, auto_split, default_mode, currency
     FROM split_groups WHERE deleted_at IS NULL AND IFNULL(archived,0)=0 ORDER BY created_at DESC`,
  );
  const { data: members = [] } = useQuery<{ group_id: string; user_id: string }>(
    "SELECT group_id, user_id FROM split_group_members WHERE deleted_at IS NULL ORDER BY created_at",
  );
  const { data: parts = [] } = useQuery<{ group_id: string; expense_id: string; user_id: string; paid_amount: number; share_amount: number }>(
    "SELECT group_id, expense_id, user_id, paid_amount, share_amount FROM expense_participants WHERE deleted_at IS NULL",
  );
  const { data: setts = [] } = useQuery<{ group_id: string; from_user: string; to_user: string; amount: number }>(
    "SELECT group_id, from_user, to_user, amount FROM settlements WHERE deleted_at IS NULL",
  );

  return useMemo(() => {
    const partsByGroup = new Map<string, typeof parts>();
    for (const p of parts) { const a = partsByGroup.get(p.group_id) ?? []; a.push(p); partsByGroup.set(p.group_id, a); }
    const settsByGroup = new Map<string, typeof setts>();
    for (const s of setts) { const a = settsByGroup.get(s.group_id) ?? []; a.push(s); settsByGroup.set(s.group_id, a); }
    const membersByGroup = new Map<string, string[]>();
    for (const m of members) { const a = membersByGroup.get(m.group_id) ?? []; a.push(m.user_id); membersByGroup.set(m.group_id, a); }

    const groupViews: GroupOverview[] = [];
    const direct = new Map<string, number>();
    let owed = 0, owe = 0;

    for (const g of groups) {
      const perUser = computeBalances(partsByGroup.get(g.id) ?? [], settsByGroup.get(g.id) ?? [], me);
      const net = perUser.reduce((s, b) => s + b.net, 0);
      const allMembers = membersByGroup.get(g.id) ?? [];
      const others = allMembers.filter((u) => u !== me);
      owed += perUser.reduce((s, b) => s + Math.max(0, b.net), 0);
      owe += perUser.reduce((s, b) => s + Math.max(0, -b.net), 0);

      if (g.is_direct) {
        // Fold direct groups into per-person aggregate balances.
        for (const b of perUser) direct.set(b.userId, (direct.get(b.userId) ?? 0) + b.net);
      } else {
        groupViews.push({
          group: g,
          memberIds: others,
          peopleCount: allMembers.length || others.length + 1,
          net,
          perUser: perUser.filter((b) => b.net !== 0),
        });
      }
    }

    const directList = [...direct.entries()]
      .filter(([, n]) => n !== 0)
      .map(([userId, net]) => ({ userId, net }));

    return { netPosition: owed - owe, owed, owe, groups: groupViews, direct: directList };
  }, [groups, members, parts, setts, me]);
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
