"use client";

import type { CatalogPhase } from "./hooks";

/**
 * First-time / status strip for the instruments catalog download. Shows a
 * progress bar while the global ticker list downloads, and a gentle fallback
 * note (with retry) if the device is offline or the fetch failed — the seed
 * list still powers the picker in the meantime, so it never blocks entry.
 */
export function CatalogProgress({ phase, pct, onRetry }: { phase: CatalogPhase; pct: number; onRetry: () => void }) {
  if (phase === "ready" || phase === "seed") return null;

  if (phase === "loading" || phase === "checking") {
    const indeterminate = phase === "checking" || pct <= 0;
    return (
      <div style={{ display: "grid", gap: 6 }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 12, color: "var(--text-2)" }}>
          <span>Setting up the global stock list (one-time)…</span>
          {!indeterminate && <span>{pct}%</span>}
        </div>
        <div style={{ height: 8, borderRadius: 999, background: "var(--surface-2)", overflow: "hidden", position: "relative" }}>
          <div
            style={{
              height: "100%",
              borderRadius: 999,
              background: "var(--accent)",
              width: indeterminate ? "35%" : `${Math.max(4, pct)}%`,
              transition: "width 200ms ease",
              animation: indeterminate ? "pc-cat-slide 1.1s ease-in-out infinite" : undefined,
            }}
          />
        </div>
        <style>{`@keyframes pc-cat-slide { 0%{margin-left:-35%} 100%{margin-left:100%} }`}</style>
      </div>
    );
  }

  // offline / error — seed still works, offer a retry.
  const msg = phase === "offline"
    ? "You're offline — showing common tickers for now. The full list will download next time you're connected."
    : "Couldn't download the full stock list — showing common tickers. You can retry.";
  return (
    <div className="card" style={{ padding: "10px 12px", background: "var(--surface-2)", display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10 }}>
      <span className="muted" style={{ fontSize: 13 }}>{msg}</span>
      <button className="chip" onClick={onRetry}>Retry</button>
    </div>
  );
}
