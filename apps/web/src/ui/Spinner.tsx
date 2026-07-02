"use client";

import { motion } from "framer-motion";

/** Smooth rotating ring spinner in the earthy accent. */
export function Spinner({ size = 28, stroke = 3 }: { size?: number; stroke?: number }) {
  return (
    <motion.span
      style={{
        display: "inline-block",
        width: size,
        height: size,
        borderRadius: "50%",
        border: `${stroke}px solid var(--accent-ghost)`,
        borderTopColor: "var(--accent)",
        boxSizing: "border-box",
      }}
      animate={{ rotate: 360 }}
      transition={{ repeat: Infinity, ease: "linear", duration: 0.8 }}
    />
  );
}

/** Full-area centered loader with an optional label. */
export function Loading({ label }: { label?: string }) {
  return (
    <div style={{ minHeight: "50vh", display: "grid", placeItems: "center", gap: 14 }}>
      <Spinner size={34} />
      {label && <span className="muted" style={{ fontSize: 14 }}>{label}</span>}
    </div>
  );
}

/** Skeleton shimmer block for list/card placeholders. */
export function Skeleton({ height = 20, width = "100%", radius = 8 }: { height?: number; width?: number | string; radius?: number }) {
  return (
    <motion.div
      style={{ height, width, borderRadius: radius, background: "var(--surface-2)" }}
      animate={{ opacity: [0.5, 1, 0.5] }}
      transition={{ repeat: Infinity, duration: 1.4, ease: "easeInOut" }}
    />
  );
}
