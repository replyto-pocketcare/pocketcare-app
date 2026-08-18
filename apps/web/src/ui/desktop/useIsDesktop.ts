"use client";

import { useEffect, useState } from "react";

/**
 * True only on wide screens (the desktop dashboard breakpoint).
 *
 * Deliberately starts `false` and flips in an effect: server rendering has no
 * viewport, and the mobile layout is the safe default to paint first. Anything
 * gated on this must therefore be presentation-only — never the sole route to
 * a feature — so a phone (or the first paint on desktop) never loses access.
 *
 * Kept in sync with the `@media (min-width: 1024px)` block in globals.css. If
 * you change one, change the other.
 */
export const DESKTOP_MIN_WIDTH = 1024;

export function useIsDesktop(): boolean {
  const [desktop, setDesktop] = useState(false);
  useEffect(() => {
    const mq = window.matchMedia(`(min-width: ${DESKTOP_MIN_WIDTH}px)`);
    const sync = () => setDesktop(mq.matches);
    sync();
    mq.addEventListener("change", sync);
    return () => mq.removeEventListener("change", sync);
  }, []);
  return desktop;
}
