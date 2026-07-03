"use client";

import { useEffect, useRef, useState } from "react";
import { MoreIcon } from "./icons";

export interface KebabItem {
  label: string;
  onClick: () => void;
  /** Render in the danger colour (e.g. Remove/Delete). */
  danger?: boolean;
}

/** A compact "⋮" button that opens a dropdown of row actions. */
export function KebabMenu({ items, label = "Actions" }: { items: KebabItem[]; label?: string }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    const onDoc = (e: MouseEvent) => {
      if (!ref.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onDoc);
    return () => document.removeEventListener("mousedown", onDoc);
  }, [open]);

  return (
    <div ref={ref} style={{ position: "relative", flexShrink: 0 }}>
      <button
        className="chip"
        aria-label={label}
        aria-haspopup="menu"
        aria-expanded={open}
        onClick={() => setOpen((v) => !v)}
        style={{ padding: 8, display: "inline-flex", alignItems: "center", justifyContent: "center", color: "var(--text-2)" }}
      >
        <MoreIcon size={18} />
      </button>
      {open && (
        <div
          role="menu"
          style={{
            position: "absolute", top: "calc(100% + 6px)", right: 0, zIndex: 30, minWidth: 148,
            background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10,
            boxShadow: "var(--shadow-lg)", overflow: "hidden",
          }}
        >
          {items.map((it, i) => (
            <button
              key={i}
              role="menuitem"
              onClick={() => { setOpen(false); it.onClick(); }}
              style={{
                display: "block", width: "100%", textAlign: "left", padding: "11px 14px",
                border: "none", borderTop: i ? "1px solid var(--border)" : "none",
                background: "transparent", cursor: "pointer", fontSize: 14,
                color: it.danger ? "var(--negative)" : "var(--text)",
              }}
            >
              {it.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
