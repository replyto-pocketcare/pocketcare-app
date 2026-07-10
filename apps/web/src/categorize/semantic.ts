/**
 * On-device semantic auto-categorizer.
 *
 * Uses a small sentence-embedding model (transformers.js, all-MiniLM-L6-v2)
 * loaded lazily from a CDN and cached by the browser (offline after first use).
 * Each category is embedded from its example anchors into a centroid; an input
 * phrase is embedded and matched to the nearest category by cosine similarity —
 * so "chocolate" lands on Food even if it was never in a keyword list. User
 * corrections are stored on-device and folded into the centroids over time.
 *
 * Everything here is best-effort: any failure (offline first load, blocked CDN)
 * throws, and the caller falls back to the keyword engine — so it never breaks
 * the form.
 */
import { anchorsFor } from "./anchors";
import type { CategoryData } from "./seeds";

const TRANSFORMERS_URL = "https://cdn.jsdelivr.net/npm/@xenova/[email protected]";
const MODEL = "Xenova/all-MiniLM-L6-v2";
const THRESHOLD = 0.30; // min cosine similarity to accept a suggestion
const MAX_LEARNED_PER_CATEGORY = 40;

// ---- lazy embedding pipeline ----
let extractorPromise: Promise<(text: string, opts: object) => Promise<{ data: Float32Array }>> | null = null;

async function getExtractor() {
  if (!extractorPromise) {
    extractorPromise = (async () => {
      // Runtime CDN ESM import (kept out of the webpack graph so it isn't bundled).
      const T = await import(/* webpackIgnore: true */ TRANSFORMERS_URL);
      T.env.allowLocalModels = false;      // fetch weights from the HF CDN
      T.env.useBrowserCache = true;        // cache the model for offline reuse
      return T.pipeline("feature-extraction", MODEL, { quantized: true });
    })().catch((e) => { extractorPromise = null; throw e; });
  }
  return extractorPromise;
}

async function embed(text: string): Promise<Float32Array> {
  const ex = await getExtractor();
  const out = await ex(text, { pooling: "mean", normalize: true });
  return out.data;
}

/** Cosine similarity of two L2-normalized vectors (= dot product). */
function cosine(a: Float32Array, b: Float32Array): number {
  let s = 0;
  const n = Math.min(a.length, b.length);
  for (let i = 0; i < n; i++) s += a[i]! * b[i]!;
  return s;
}

// ---- learned corrections (IndexedDB) ----
const DB_NAME = "pocketcare-categorize";
const STORE = "learned";

function openDb(): Promise<IDBDatabase | null> {
  return new Promise((resolve) => {
    if (typeof indexedDB === "undefined") return resolve(null);
    const req = indexedDB.open(DB_NAME, 1);
    req.onupgradeneeded = () => { if (!req.result.objectStoreNames.contains(STORE)) req.result.createObjectStore(STORE); };
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => resolve(null);
  });
}
async function loadLearned(): Promise<Map<string, string[]>> {
  const db = await openDb();
  if (!db) return new Map();
  return new Promise((resolve) => {
    const tx = db.transaction(STORE, "readonly").objectStore(STORE).getAllKeys();
    tx.onsuccess = async () => {
      const keys = tx.result as string[];
      const map = new Map<string, string[]>();
      const store = db.transaction(STORE, "readonly").objectStore(STORE);
      let pending = keys.length;
      if (pending === 0) return resolve(map);
      for (const k of keys) {
        const g = store.get(k);
        g.onsuccess = () => { map.set(String(k), (g.result as string[]) ?? []); if (--pending === 0) resolve(map); };
        g.onerror = () => { if (--pending === 0) resolve(map); };
      }
    };
    tx.onerror = () => resolve(new Map());
  });
}
async function appendLearned(categoryId: string, phrase: string): Promise<void> {
  const db = await openDb();
  if (!db) return;
  await new Promise<void>((resolve) => {
    const store = db.transaction(STORE, "readwrite").objectStore(STORE);
    const g = store.get(categoryId);
    g.onsuccess = () => {
      const list = ((g.result as string[]) ?? []).filter((p) => p !== phrase);
      list.push(phrase);
      store.put(list.slice(-MAX_LEARNED_PER_CATEGORY), categoryId);
      resolve();
    };
    g.onerror = () => resolve();
  });
}

// ---- category centroids (cached, rebuilt on change) ----
let cache: { sig: string; map: Map<string, Float32Array> } | null = null;

function signature(categories: CategoryData[], learned: Map<string, string[]>): string {
  const cats = categories.map((c) => `${c.id}:${c.name}`).join("|");
  const learn = [...learned.entries()].map(([k, v]) => `${k}#${v.length}`).sort().join(",");
  return `${MODEL}::${cats}::${learn}`;
}

async function ensureCentroids(categories: CategoryData[]): Promise<Map<string, Float32Array>> {
  const learned = await loadLearned();
  const sig = signature(categories, learned);
  if (cache && cache.sig === sig) return cache.map;
  const map = new Map<string, Float32Array>();
  for (const c of categories) {
    const parts = [c.name, ...anchorsFor(c.name), ...(learned.get(c.id) ?? [])];
    map.set(c.id, await embed(parts.join(", ")));
  }
  cache = { sig, map };
  return map;
}

/** Classify free text to the nearest category, or null if nothing is confident enough. */
export async function semanticClassify(text: string, categories: CategoryData[]): Promise<{ categoryId: string; score: number } | null> {
  if (!text.trim() || categories.length === 0) return null;
  const map = await ensureCentroids(categories);
  const q = await embed(text.trim());
  let best: string | null = null;
  let bestScore = -1;
  for (const [id, v] of map) {
    const s = cosine(q, v);
    if (s > bestScore) { bestScore = s; best = id; }
  }
  return best && bestScore >= THRESHOLD ? { categoryId: best, score: bestScore } : null;
}

/** Fold a user-confirmed (phrase → category) into the on-device model. */
export async function semanticLearn(text: string, categoryId: string): Promise<void> {
  const phrase = text.trim().toLowerCase();
  if (!phrase || phrase.length > 120) return;
  await appendLearned(categoryId, phrase);
  cache = null; // force centroid rebuild to include the new example
}
