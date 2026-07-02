"use client";

import { useMemo, useRef, useState } from "react";

export interface SelectOption { value: string; label: string; search?: string }

/** A type-to-search combobox (single select). */
export function SearchSelect({ value, onChange, options, placeholder = "Search…", allowClear = true }: {
  value: string | null;
  onChange: (value: string | null) => void;
  options: SelectOption[];
  placeholder?: string;
  allowClear?: boolean;
}) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const boxRef = useRef<HTMLDivElement>(null);

  const selected = options.find((o) => o.value === value) ?? null;
  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return options.slice(0, 50);
    return options.filter((o) => (o.search ?? o.label).toLowerCase().includes(q)).slice(0, 50);
  }, [query, options]);

  return (
    <div ref={boxRef} style={{ position: "relative" }} onBlur={(e) => { if (!boxRef.current?.contains(e.relatedTarget as Node)) setOpen(false); }}>
      <input
        className="input"
        value={open ? query : selected?.label ?? ""}
        placeholder={placeholder}
        onFocus={() => { setOpen(true); setQuery(""); }}
        onChange={(e) => { setQuery(e.target.value); setOpen(true); }}
      />
      {allowClear && selected && !open && (
        <button type="button" onMouseDown={(e) => { e.preventDefault(); onChange(null); }}
          aria-label="Clear" style={{ position: "absolute", right: 8, top: "50%", transform: "translateY(-50%)", border: "none", background: "transparent", cursor: "pointer", color: "var(--text-2)", fontSize: 16 }}>×</button>
      )}
      {open && (
        <div style={{ position: "absolute", zIndex: 20, top: "calc(100% + 4px)", left: 0, right: 0, maxHeight: 260, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, boxShadow: "var(--shadow)" }}>
          {filtered.length === 0 && <div className="muted" style={{ padding: "10px 12px", fontSize: 13 }}>No matches</div>}
          {filtered.map((o) => (
            <button key={o.value} type="button"
              onMouseDown={(e) => { e.preventDefault(); onChange(o.value); setOpen(false); }}
              style={{ display: "block", width: "100%", textAlign: "left", padding: "9px 12px", border: "none", background: o.value === value ? "var(--accent-ghost)" : "transparent", cursor: "pointer", fontSize: 14, color: "var(--text)" }}>
              {o.label}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
