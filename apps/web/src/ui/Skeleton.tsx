"use client";

import type { CSSProperties } from "react";

/** A single shimmering placeholder block. */
export function Skeleton({ h = 16, w = "100%", r = 8, style }: { h?: number | string; w?: number | string; r?: number; style?: CSSProperties }) {
  return <div className="skeleton" style={{ height: h, width: w, borderRadius: r, ...style }} />;
}

/** Grid of card placeholders — matches the accounts / dashboard card grid. */
export function CardsSkeleton({ count = 4, minWidth = 230 }: { count?: number; minWidth?: number }) {
  return (
    <div style={{ display: "grid", gridTemplateColumns: `repeat(auto-fill, minmax(min(${minWidth}px, 100%), 1fr))`, gap: 12 }}>
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="card" style={{ padding: 16, display: "grid", gap: 10 }}>
          <Skeleton h={12} w="40%" />
          <Skeleton h={24} w="70%" />
        </div>
      ))}
    </div>
  );
}

/** Vertical list of row placeholders. */
export function ListSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div style={{ display: "grid", gap: 10 }}>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} className="card" style={{ padding: 16, display: "flex", justifyContent: "space-between", gap: 12, alignItems: "center" }}>
          <Skeleton h={16} w="45%" />
          <Skeleton h={16} w="20%" />
        </div>
      ))}
    </div>
  );
}

/** Big hero-card placeholder (net worth, etc.). */
export function HeroSkeleton({ height = 120 }: { height?: number }) {
  return <div className="card" style={{ padding: 24 }}><Skeleton h={height} r={16} /></div>;
}
