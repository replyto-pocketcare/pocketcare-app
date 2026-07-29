"use client";

/**
 * How many list rows fit the space a dashboard tile actually has.
 *
 * Dashboard tiles are user-resizable (`grid-column: span W` / `grid-row: span H`)
 * and they **clip** — they never scroll, because a nested scroller captures the
 * wheel/swipe and refuses to chain it back to the page. So a hard-coded "show 4
 * rows" is wrong at every size but one: too few rows wastes a tall tile, too many
 * get silently cut off by `overflow: hidden`.
 *
 * `useFitRows` observes the list container and returns `floor(available / rowH)`.
 * Callers render `items.slice(0, fit)` plus a "+N more →" link.
 *
 * Two things worth knowing before you change this:
 *
 * 1. **The container must have a height that does not come from its children** —
 *    i.e. it must be the `.tile-flex` child (`flex: 1; min-height: 0`) of the
 *    tile's flex column. If its height were content-derived, `fit` would feed
 *    back into the measurement and settle at 1 row.
 * 2. **Below 860px tiles have natural height** (see the media query in
 *    globals.css: single column, `grid-auto-rows: auto`). There is nothing to fit
 *    into there, so the hook returns `max` and the list renders in full. This is
 *    the *same* width condition the layout already uses — not a second, divergent
 *    behaviour of the kind that let the scroll bug survive on one form factor.
 *
 * The initial value is `max`, so the first paint over-renders and then shrinks.
 * That direction is safe (the tile clips); starting small and growing would flash
 * an empty tile on every mount.
 */

import { useEffect, useRef, useState } from "react";

/** Matches the `@media (max-width: 860px)` block in globals.css. */
const NATURAL_HEIGHT_QUERY = "(max-width: 860px)";

export interface FitRowsOptions {
  /** Vertical gap between rows, in px (defaults to the 8px most tiles use). */
  gap?: number;
  /** Never return fewer than this many rows. */
  min?: number;
  /** Never return more than this many rows (also the value used on mobile). */
  max?: number;
}

export function useFitRows<T extends HTMLElement = HTMLDivElement>(
  rowHeight: number,
  { gap = 8, min = 1, max = 24 }: FitRowsOptions = {},
) {
  const ref = useRef<T | null>(null);
  const [fit, setFit] = useState(max);

  useEffect(() => {
    const el = ref.current;
    if (!el || typeof ResizeObserver === "undefined") return;
    const mq = typeof window.matchMedia === "function" ? window.matchMedia(NATURAL_HEIGHT_QUERY) : null;

    const measure = () => {
      if (mq?.matches) { setFit(max); return; }
      const h = el.clientHeight;
      if (h <= 0) return; // not laid out yet (or hidden) — keep the last value
      const n = Math.floor((h + gap) / (rowHeight + gap));
      setFit(Math.max(min, Math.min(max, n)));
    };

    const ro = new ResizeObserver(measure);
    ro.observe(el);
    measure();
    mq?.addEventListener("change", measure);
    return () => { ro.disconnect(); mq?.removeEventListener("change", measure); };
  }, [rowHeight, gap, min, max]);

  return { ref, fit };
}
