/** Account/card color palette — earthy base with a few jewel tones (incl. indigo). */
export const ACCOUNT_COLORS = [
  "#3e4a38", // forest
  "#5f6647", // olive
  "#6b7a4f", // moss
  "#9cae8e", // sage
  "#b06a4f", // terracotta
  "#c98a72", // clay
  "#a8503a", // rust
  "#7c4a3a", // sienna
  "#5f4636", // coffee
  "#c9b79c", // sand
  "#c08a3e", // gold
  "#4f46e5", // indigo
  "#6d5acf", // violet
  "#3f5a8a", // denim
  "#2f6f6a", // teal
  "#7a4a6b", // plum
  "#4b5563", // slate
  "#2b2723", // ink
] as const;

export const DEFAULT_ACCOUNT_COLOR = ACCOUNT_COLORS[0];

/** Fallback color derived deterministically from an id (when none is set). */
export function colorForId(id: string | null | undefined, fallback = "#7c7264"): string {
  if (!id) return fallback;
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return ACCOUNT_COLORS[h % ACCOUNT_COLORS.length];
}
