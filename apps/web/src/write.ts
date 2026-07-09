"use client";

import { getDb, getUserId } from "./powersync";
import { withLoading } from "./ui/GlobalLoader";

export const uuid = () => globalThis.crypto.randomUUID();
export const nowIso = () => new Date().toISOString();

/**
 * Insert a row into a synced table, filling id/user_id/timestamps.
 * Generic helper for the lighter feature pages (goals, subscriptions, etc.).
 */
export async function insertRow(table: string, values: Record<string, unknown>): Promise<string> {
  const db = getDb();
  if (!db) throw new Error("DB not ready");
  const id = uuid();
  const ts = nowIso();
  const row: Record<string, unknown> = { id, created_at: ts, updated_at: ts, ...values };
  if (!("user_id" in values) && !["split_groups", "expenses", "settlements", "split_invitations", "connections", "profiles"].includes(table)) {
    row.user_id = getUserId();
  }
  const keys = Object.keys(row);
  const placeholders = keys.map(() => "?").join(",");
  await withLoading(db.execute(
    `INSERT INTO ${table} (${keys.join(",")}) VALUES (${placeholders})`,
    keys.map((k) => row[k] as never),
  ));
  return id;
}

/** Update columns on a synced row by id (sets updated_at automatically). */
export async function updateRow(table: string, id: string, values: Record<string, unknown>): Promise<void> {
  const db = getDb();
  if (!db) return;
  const entries = Object.entries(values);
  if (entries.length === 0) return;
  const sets = entries.map(([k]) => `${k} = ?`).concat("updated_at = ?");
  const params = entries.map(([, v]) => v as never).concat(nowIso() as never, id as never);
  await withLoading(db.execute(`UPDATE ${table} SET ${sets.join(", ")} WHERE id = ?`, params));
}

/** Soft-delete a row (sets deleted_at) so the change syncs. */
export async function softDelete(table: string, id: string): Promise<void> {
  const db = getDb();
  if (!db) return;
  await withLoading(db.execute(`UPDATE ${table} SET deleted_at = ?, updated_at = ? WHERE id = ?`, [nowIso(), nowIso(), id]));
}
