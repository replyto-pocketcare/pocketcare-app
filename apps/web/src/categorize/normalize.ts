/**
 * Text normalization and tokenization for the auto-categorization engine.
 */

const STOP_WORDS = new Set([
  "the", "and", "or", "to", "for", "in", "on", "at", "with", "a", "an", "is", "of"
]);

export interface NormalizedResult {
  phrase: string;
  tokens: string[];
}

/**
 * Normalizes text by lowercasing, stripping punctuation,
 * and returning both the full normalized phrase and individual tokens/bigrams.
 */
export function normalizeText(text: string): NormalizedResult {
  if (!text) return { phrase: "", tokens: [] };

  // Lowercase and strip punctuation and digits
  const clean = text
    .toLowerCase()
    .replace(/[^\p{L}\s]/gu, " ") // keep only letters and spaces (unicode aware)
    .replace(/\s+/g, " ")
    .trim();

  if (!clean) return { phrase: "", tokens: [] };

  const rawWords = clean.split(" ");
  
  // Filter out short stop words but keep meaningful short words
  const words = rawWords.filter(w => w.length > 2 || (w.length === 2 && !STOP_WORDS.has(w)));
  if (words.length === 0) return { phrase: clean, tokens: [clean] };

  const tokens = new Set<string>();

  // Add individual words
  for (const w of words) {
    tokens.add(w);
  }

  // Add bigrams
  for (let i = 0; i < words.length - 1; i++) {
    tokens.add(`${words[i]} ${words[i + 1]}`);
  }

  return {
    phrase: clean,
    tokens: Array.from(tokens)
  };
}
