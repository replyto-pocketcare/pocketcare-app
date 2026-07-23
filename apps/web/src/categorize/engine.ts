import type { AbstractPowerSyncDatabase } from "@powersync/common";
import { normalizeText } from "./normalize";
import { buildSeedMap, buildSeedList, type CategoryData } from "./seeds";

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
 * Score a normalized description against learned token rules + cold-start seeds.
 * Shared by the single-shot and bulk paths so they always agree.
 */
function scoreTokens(
  norm: ReturnType<typeof normalizeText>,
  tokenRules: Map<string, { category_id: string; weight: number; corrections: number }[]>,
  seedMap: Map<string, string>,
  seedList: { keyword: string; categoryId: string }[],
): string | null {
  const scores = new Map<string, number>();
  const add = (catId: string, pts: number) => scores.set(catId, (scores.get(catId) ?? 0) + pts);

  // 1. Learned token rules (exact token match).
  for (const tok of norm.tokens) {
    const hits = tokenRules.get(tok);
    if (hits) for (const h of hits) add(h.category_id, h.weight + h.corrections * CORRECTION_BOOST);
  }

  // 2. Cold-start seeds — exact token match (worth 2, enough to clear threshold).
  for (const tok of norm.tokens) {
    const seedCat = seedMap.get(tok);
    if (seedCat) add(seedCat, 2);
  }

  // 3. Cold-start seeds — substring match on the merchant blob. Catches mangled
  // merchant names like "swiggylimited" / "amazonin" that never tokenize cleanly.
  if (norm.merchant.length >= 3) {
    for (const { keyword, categoryId } of seedList) {
      if (keyword.length >= 4 && norm.merchant.includes(keyword)) add(categoryId, 2);
    }
  }

  let best: string | null = null;
  let max = 0;
  for (const [catId, score] of scores) {
    if (score > max) { max = score; best = catId; }
  }
  return max >= CONFIDENCE_THRESHOLD ? best : null;
}

/**
 * Suggests a category based on the transaction description/note.
 * Deterministic, offline, <10ms. Used by the live add-transaction form.
 */
export async function suggestCategory(
  text: string,
  db: AbstractPowerSyncDatabase,
  userId: string,
  categories: CategoryData[]
): Promise<string | null> {
  const norm = normalizeText(text);
  if (!norm.phrase) return null;

  // 1. Exact learned-phrase match wins outright.
  const phraseHit = await db.getOptional<CategoryRule>(
    `SELECT category_id FROM category_rules WHERE user_id = ? AND kind = 'phrase' AND key = ? AND deleted_at IS NULL ORDER BY weight DESC LIMIT 1`,
    [userId, norm.phrase]
  );
  if (phraseHit) return phraseHit.category_id;

  if (norm.tokens.length === 0 && !norm.merchant) return null;

  // 2. Learned token rules for the tokens we extracted.
  const tokenRules = new Map<string, { category_id: string; weight: number; corrections: number }[]>();
  if (norm.tokens.length) {
    const placeholders = norm.tokens.map(() => "?").join(",");
    const hits = await db.getAll<CategoryRule>(
      `SELECT category_id, key, weight, corrections FROM category_rules WHERE user_id = ? AND kind = 'token' AND key IN (${placeholders}) AND deleted_at IS NULL`,
      [userId, ...norm.tokens]
    );
    for (const h of hits) {
      const arr = tokenRules.get(h.key) ?? [];
      arr.push({ category_id: h.category_id, weight: h.weight, corrections: h.corrections });
      tokenRules.set(h.key, arr);
    }
  }

  return scoreTokens(norm, tokenRules, buildSeedMap(categories), buildSeedList(categories));
}

/**
 * A preloaded classifier for BULK work (statement import, auto-categorize job).
 * Reads every learned rule + builds the seed maps ONCE, then classifies many
 * descriptions in memory with zero further DB round-trips.
 */
export interface BulkClassifier {
  classify(text: string): string | null;
}

export async function buildClassifier(
  db: AbstractPowerSyncDatabase,
  userId: string,
  categories: CategoryData[],
): Promise<BulkClassifier> {
  const rules = await db.getAll<CategoryRule>(
    `SELECT kind, key, category_id, weight, corrections FROM category_rules WHERE user_id = ? AND deleted_at IS NULL`,
    [userId],
  );
  const phraseRules = new Map<string, string>();
  const tokenRules = new Map<string, { category_id: string; weight: number; corrections: number }[]>();
  for (const r of rules) {
    if (r.kind === "phrase") {
      // Highest-weight phrase wins for a given key.
      if (!phraseRules.has(r.key)) phraseRules.set(r.key, r.category_id);
    } else {
      const arr = tokenRules.get(r.key) ?? [];
      arr.push({ category_id: r.category_id, weight: r.weight, corrections: r.corrections });
      tokenRules.set(r.key, arr);
    }
  }
  const seedMap = buildSeedMap(categories);
  const seedList = buildSeedList(categories);

  return {
    classify(text: string): string | null {
      const norm = normalizeText(text);
      if (!norm.phrase) return null;
      const phraseHit = phraseRules.get(norm.phrase);
      if (phraseHit) return phraseHit;
      if (norm.tokens.length === 0 && !norm.merchant) return null;
      return scoreTokens(norm, tokenRules, seedMap, seedList);
    },
  };
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
    // 1. Upsert exact phrase rule (weight 1000 so it always wins future phrase checks).
    await tx.execute(
      `INSERT INTO category_rules (id, user_id, kind, key, category_id, weight, corrections, created_at, updated_at)
       VALUES (uuid(), ?, 'phrase', ?, ?, 1000, ?, ?, ?)
       ON CONFLICT(user_id, kind, key, category_id) WHERE deleted_at IS NULL
       DO UPDATE SET weight = category_rules.weight + 1, corrections = category_rules.corrections + ?, updated_at = ?`,
      [userId, norm.phrase, chosenCategoryId, correctionVal, now, now, correctionVal, now]
    );

    // 2. Upsert token rules.
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
