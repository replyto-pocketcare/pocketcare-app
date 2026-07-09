"use client";

import { getDb, getUserId } from "../powersync";
import { insertRow } from "../write";

/**
 * Get (or lazily create) the hidden virtual account that tracks money others owe
 * you ('receivable') or you owe others ('payable'), per currency. These are
 * excluded from account pickers and net worth; the Friends dashboard surfaces
 * their aggregate balance.
 */
export async function ensureVirtualAccount(kind: "receivable" | "payable", currency: string): Promise<string> {
  const db = getDb();
  if (!db) throw new Error("DB not ready");
  const existing = await db.getOptional<{ id: string }>(
    "SELECT id FROM accounts WHERE user_id = ? AND kind = ? AND currency = ? AND deleted_at IS NULL LIMIT 1",
    [getUserId(), kind, currency],
  );
  if (existing) return existing.id;
  return insertRow("accounts", {
    name: kind === "receivable" ? "Owed to me" : "I owe",
    type: "cash",
    currency,
    icon: null,
    color: kind === "receivable" ? "#5f7a52" : "#a8503a",
    is_archived: 0,
    include_in_net_worth: 0,
    kind,
  });
}
