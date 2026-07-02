"use client";

import { getDb, getUserId } from "./powersync";

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
  const row: Record<string, unknown> = { id, user_id: getUserId(), created_at: ts, updated_at: ts, ...values };
  const keys = Object.keys(row);
  const placeholders = keys.map(() => "?").join(",");
  await db.execute(
    `INSERT INTO ${table} (${keys.join(",")}) VALUES (${placeholders})`,
    keys.map((k) => row[k] as never),
  );
  return id;
}

/** Soft-delete a row (sets deleted_at) so the change syncs. */
export async function softDelete(table: string, id: string): Promise<void> {
  const db = getDb();
  if (!db) return;
  await db.execute(`UPDATE ${table} SET deleted_at = ?, updated_at = ? WHERE id = ?`, [nowIso(), nowIso(), id]);
}
