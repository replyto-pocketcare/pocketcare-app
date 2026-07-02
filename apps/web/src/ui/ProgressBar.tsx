"use client";

import { motion } from "framer-motion";

/** Animated progress bar (0–100). Colour can signal threshold/over states. */
export function ProgressBar({ pct, color = "var(--accent)", height = 10 }: { pct: number; color?: string; height?: number }) {
  const clamped = Math.min(100, Math.max(0, pct));
  return (
    <div style={{ height, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden" }}>
      <motion.div
        initial={{ width: 0 }}
        animate={{ width: `${clamped}%` }}
        transition={{ type: "spring", stiffness: 120, damping: 20 }}
        style={{ height, borderRadius: 999, background: color }}
      />
    </div>
  );
}
