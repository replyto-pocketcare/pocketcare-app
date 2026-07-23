"use client";

/**
 * Bulk auto-categorize job. Scans the user's uncategorized expense transactions,
 * runs the (preloaded) on-device classifier over each description, and — when
 * applying — writes every match inside ONE writeTransaction so the change syncs
 * as a single batched request instead of one PATCH per row.
 *
 * `apply: false` is a dry run used to preview how many rows would be categorized
 * before the user commits.
 */
import { getDb, getUserId } from "../powersync";
import { nowIso } from "../write";
import { buildClassifier } from "./engine";
import type { CategoryData } from "./seeds";

export interface AutoCatResult {
  scanned: number;
  categorized: number;
}

interface Uncat { id: string; description: string | null; note: string | null }

async function loadUncategorized(): Promise<Uncat[]> {
  const db = getDb();
  if (!db) return [];
  // Only expenses: income rows rarely carry a merchant and the seed set targets
  // spend categories. Skip transfers/opening_balance/adjustment entirely.
  return db.getAll<Uncat>(
    `SELECT id, description, note FROM transactions
     WHERE deleted_at IS NULL AND category_id IS NULL AND type = 'expense'`,
  );
}

/**
 * Classify uncategorized expenses. When `apply` is true, persist matches.
 * Categories are passed in (the caller already has them via useQuery).
 */
export async function autoCategorize(
  categories: CategoryData[],
  opts: { apply: boolean },
): Promise<AutoCatResult> {
  const db = getDb();
  if (!db) return { scanned: 0, categorized: 0 };
  const userId = getUserId();

  const rows = await loadUncategorized();
  if (rows.length === 0) return { scanned: 0, categorized: 0 };

  const classifier = await buildClassifier(db, userId, categories);
  const matches: { id: string; categoryId: string }[] = [];
  for (const r of rows) {
    const text = [r.description, r.note].filter(Boolean).join(" ");
    if (!text) continue;
    const catId = classifier.classify(text);
    if (catId) matches.push({ id: r.id, categoryId: catId });
  }

  if (opts.apply && matches.length) {
    const ts = nowIso();
    await db.writeTransaction(async (tx) => {
      for (const m of matches) {
        await tx.execute(
          "UPDATE transactions SET category_id = ?, updated_at = ? WHERE id = ? AND category_id IS NULL",
          [m.categoryId, ts, m.id],
        );
      }
    });
  }

  return { scanned: rows.length, categorized: matches.length };
}
