/**
 * Re-export only.
 *
 * The palette and `colorForId` moved to `@sanvya/catalog` so Android and iOS
 * can be generated from the same declaration — the palette existed four times
 * across the three apps, and the two Android copies (ARGB and hex) had to be
 * kept byte-identical by hand.
 *
 * This file stays so the ~dozen web imports of it keep working; delete it once
 * they point at the package directly.
 */
export {
  ACCOUNT_COLORS,
  DEFAULT_ACCOUNT_COLOR,
  FALLBACK_ACCOUNT_COLOR,
  colorForId,
} from "@sanvya/catalog";
