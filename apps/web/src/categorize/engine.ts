import type { AbstractPowerSyncDatabase } from "@powersync/common";
import { normalizeText } from "./normalize";
import { buildSeedMap, type CategoryData } from "./seeds";

// If a category achieves this combined weight, we confidently auto-select it.
// Phrases have infinite weight (exact match), so they always win.
// Tokens usually have weight 1 initially. Corrections boost weight by +5.
const CONFIDENCE_THRESHOLD = 2;
const CORRECTION_BOOST = 5;

interface CategoryRule {
  kind: "phrase" | "token";
  key: string;
  category_id: string;
  weight: number;
  corrections: number;
}

/**
 * Suggests a category based on the transaction description/note.
 * Deterministic, offline, <10ms.
 */
export async function suggestCategory(
  text: string,
  db: AbstractPowerSyncDatabase,
  userId: string,
  categories: CategoryData[]
): Promise<string | null> {
  const norm = normalizeText(text);
  if (!norm.phrase) return null;

  // 1. Check for an exact phrase match (highest priority, immediate return).
  // getOptional (not get) — get() throws "Result set is empty" when there's no rule.
  const phraseHit = await db.getOptional<CategoryRule>(
    `SELECT category_id FROM category_rules WHERE user_id = ? AND kind = 'phrase' AND key = ? AND deleted_at IS NULL ORDER BY weight DESC LIMIT 1`,
    [userId, norm.phrase]
  );
  if (phraseHit) {
    return phraseHit.category_id;
  }

  if (norm.tokens.length === 0) return null;

  // 2. Fetch all matching token rules for the extracted tokens
  // e.g. WHERE key IN ('uber', 'eats', 'uber eats')
  const placeholders = norm.tokens.map(() => "?").join(",");
  const tokenHits = await db.getAll<CategoryRule>(
    `SELECT category_id, weight, corrections FROM category_rules WHERE user_id = ? AND kind = 'token' AND key IN (${placeholders}) AND deleted_at IS NULL`,
    [userId, ...norm.tokens]
  );

  // 3. Accumulate scores per category
  const scores = new Map<string, number>();

  // Add DB token weights
  for (const hit of tokenHits) {
    const current = scores.get(hit.category_id) ?? 0;
    scores.set(hit.category_id, current + hit.weight + (hit.corrections * CORRECTION_BOOST));
  }

  // 4. Add cold-start seed weights (worth 2 points to just clear the threshold)
  const seedMap = buildSeedMap(categories);
  for (const token of norm.tokens) {
    const seedCategoryId = seedMap.get(token);
    if (seedCategoryId) {
      const current = scores.get(seedCategoryId) ?? 0;
      scores.set(seedCategoryId, current + 2); // Seed hit is enough to trigger threshold
    }
  }

  // 5. Find the highest scoring category
  let bestCategory: string | null = null;
  let maxScore = 0;

  for (const [catId, score] of scores.entries()) {
    if (score > maxScore) {
      maxScore = score;
      bestCategory = catId;
    }
  }

  if (maxScore >= CONFIDENCE_THRESHOLD) {
    return bestCategory;
  }

  return null;
}

/**
 * Learns from the user's saved transaction.
 * Saves an exact phrase mapping, and increments token weights.
 */
export async function learnFromSave(
  text: string,
  chosenCategoryId: string | null,
  suggestedCategoryId: string | null,
  db: AbstractPowerSyncDatabase,
  userId: string
): Promise<void> {
  if (!text || !chosenCategoryId) return;

  const norm = normalizeText(text);
  if (!norm.phrase) return;

  const isCorrection = suggestedCategoryId !== null && chosenCategoryId !== suggestedCategoryId;
  const correctionVal = isCorrection ? 1 : 0;
  const now = new Date().toISOString();

  await db.writeTransaction(async (tx) => {
    // 1. Upsert exact phrase rule (weight 1000 so it always wins future phrase checks, though we query phrase first anyway)
    await tx.execute(
      `INSERT INTO category_rules (id, user_id, kind, key, category_id, weight, corrections, created_at, updated_at)
       VALUES (uuid(), ?, 'phrase', ?, ?, 1000, ?, ?, ?)
       ON CONFLICT(user_id, kind, key, category_id) WHERE deleted_at IS NULL 
       DO UPDATE SET weight = category_rules.weight + 1, corrections = category_rules.corrections + ?, updated_at = ?`,
      [userId, norm.phrase, chosenCategoryId, correctionVal, now, now, correctionVal, now]
    );

    // 2. Upsert token rules
    for (const token of norm.tokens) {
      await tx.execute(
        `INSERT INTO category_rules (id, user_id, kind, key, category_id, weight, corrections, created_at, updated_at)
         VALUES (uuid(), ?, 'token', ?, ?, 1, ?, ?, ?)
         ON CONFLICT(user_id, kind, key, category_id) WHERE deleted_at IS NULL 
         DO UPDATE SET weight = category_rules.weight + 1, corrections = category_rules.corrections + ?, updated_at = ?`,
        [userId, token, chosenCategoryId, correctionVal, now, now, correctionVal, now]
      );
    }
  });
}
