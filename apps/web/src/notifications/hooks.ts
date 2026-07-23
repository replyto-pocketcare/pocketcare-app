"use client";

/**
 * Client-side reads/writes for the notification inbox + preferences. Everything
 * is local-first: rows arrive via PowerSync sync and we read them with useQuery,
 * so the bell badge and inbox work offline. The notify-dispatch edge function is
 * what *creates* rows server-side; the client only marks them read / dismisses.
 */
import { useQuery } from "@powersync/react";
import { updateRow, softDelete, insertRow, nowIso } from "../write";
import { getDb, getUserId } from "../powersync";

export interface Notification {
  id: string;
  kind: string;
  title: string;
  body: string | null;
  severity: string;
  href: string | null;
  read_at: string | null;
  created_at: string;
}

export function useNotifications(limit = 50): Notification[] {
  const { data = [] } = useQuery<Notification>(
    `SELECT id, kind, title, body, severity, href, read_at, created_at
     FROM notifications WHERE deleted_at IS NULL ORDER BY created_at DESC LIMIT ?`,
    [limit],
  );
  return data;
}

export function useUnreadCount(): number {
  const { data = [] } = useQuery<{ c: number }>(
    "SELECT COUNT(*) AS c FROM notifications WHERE deleted_at IS NULL AND read_at IS NULL",
  );
  return data[0]?.c ?? 0;
}

export async function markRead(id: string): Promise<void> {
  await updateRow("notifications", id, { read_at: nowIso() });
}

export async function markAllRead(): Promise<void> {
  const db = getDb();
  if (!db) return;
  const ts = nowIso();
  await db.writeTransaction(async (tx) => {
    await tx.execute(
      "UPDATE notifications SET read_at = ?, updated_at = ? WHERE read_at IS NULL AND deleted_at IS NULL",
      [ts, ts],
    );
  });
}

export async function dismiss(id: string): Promise<void> {
  await softDelete("notifications", id);
}

// --- Preferences ------------------------------------------------------------
export interface NotifPrefs {
  id: string;
  push_enabled: number;
  emi_due: number;
  budget: number;
  low_balance: number;
  outlier: number;
  group_invite: number;
  group_expense: number;
  low_balance_threshold: number;
  emi_lead_days: number;
}

export function useNotifPrefs(): NotifPrefs | null {
  const { data = [] } = useQuery<NotifPrefs>(
    `SELECT id, push_enabled, emi_due, budget, low_balance, outlier, group_invite, group_expense, low_balance_threshold, emi_lead_days
     FROM notification_prefs WHERE deleted_at IS NULL LIMIT 1`,
  );
  return data[0] ?? null;
}

/** Find-or-create the single prefs row for this user, returning its id. */
export async function ensurePrefs(): Promise<string | null> {
  const db = getDb();
  if (!db) return null;
  const existing = await db.getOptional<{ id: string }>(
    "SELECT id FROM notification_prefs WHERE deleted_at IS NULL LIMIT 1",
  );
  if (existing) return existing.id;
  return insertRow("notification_prefs", {
    user_id: getUserId(),
    push_enabled: 0, emi_due: 1, budget: 1, low_balance: 1, outlier: 1,
    group_invite: 1, group_expense: 1,
    low_balance_threshold: 0, emi_lead_days: 3,
  });
}

export async function updatePrefs(patch: Partial<Omit<NotifPrefs, "id">>): Promise<void> {
  const id = await ensurePrefs();
  if (id) await updateRow("notification_prefs", id, patch);
}
