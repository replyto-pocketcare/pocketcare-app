"use client";

/**
 * How many list rows a dashboard tile should render.
 *
 * HISTORY, because this hook used to do something quite different and the
 * reason it stopped matters:
 *
 * Tiles were once fixed-height (`grid-row: span H` against a tile-sized row
 * unit), so a list had a known amount of room and the job was to fit rows into
 * it — observe the container, return `floor(available / rowH)`, clip the rest
 * behind a "+N more" link. That required an invariant, documented here in
 * capitals at the time: the measured container's height must NOT come from its
 * children, or `fit` feeds back into its own measurement and settles at 1 row.
 *
 * Tiles are now sized to their CONTENT (see DraggableGrid in app/page.tsx),
 * which breaks that invariant by design — the tile's height is derived from
 * the list, so the list can no longer derive itself from the tile. Keeping the
 * observer would collapse every list to a single row, which is exactly what it
 * did until this was fixed.
 *
 * So the responsibility is inverted: the list renders up to `max` rows and the
 * tile grows to fit them. This is what the hook already did below 860px, where
 * tiles have always had natural height — that special case is simply now the
 * only case.
 *
 * Kept as a hook, rather than deleted, so callers keep their `ref` and their
 * `max` row budget in one place, and so this note survives next to them.
 */

import { useRef } from "react";

export interface FitRowsOptions {
  /** Vertical gap between rows, in px (defaults to the 8px most tiles use). */
  gap?: number;
  /** Never return fewer than this many rows. */
  min?: number;
  /** Never return more than this many rows (also the value used on mobile). */
  max?: number;
}

export function useFitRows<T extends HTMLElement = HTMLDivElement>(
  _rowHeight: number,
  { max = 24 }: FitRowsOptions = {},
) {
  // No measurement: a content-sized tile takes its height from this list, so
  // measuring the list against the tile would be circular. `max` is the row
  // budget each tile chooses for itself.
  const ref = useRef<T | null>(null);
  return { ref, fit: max };
}
