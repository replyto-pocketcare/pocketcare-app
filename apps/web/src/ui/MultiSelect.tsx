"use client";

import { useMemo, useRef, useState } from "react";

export interface MultiOption { value: string; label: string; search?: string }

/** Type-to-search multi-select. Selected shown as removable pills. */
export function MultiSelect({ options, selected, onChange, placeholder = "Search…" }: {
  options: MultiOption[];
  selected: string[];
  onChange: (next: string[]) => void;
  placeholder?: string;
}) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);
  const labelOf = (v: string) => options.find((o) => o.value === v)?.label ?? v;

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    return options
      .filter((o) => !selected.includes(o.value) && (!q || (o.search ?? o.label).toLowerCase().includes(q)))
      .slice(0, 40);
  }, [query, options, selected]);

  const add = (v: string) => { if (!selected.includes(v)) onChange([...selected, v]); setQuery(""); };
  const remove = (v: string) => onChange(selected.filter((s) => s !== v));

  return (
    <div style={{ display: "grid", gap: 8 }}>
      {selected.length > 0 && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
          {selected.map((v) => (
            <span key={v} style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "5px 10px", borderRadius: 999, border: "1px solid var(--border)", background: "var(--surface-2)", fontSize: 13 }}>
              {labelOf(v)}
              <button type="button" onClick={() => remove(v)} aria-label={`Remove ${labelOf(v)}`}
                style={{ border: "none", background: "transparent", cursor: "pointer", color: "var(--text-2)", lineHeight: 1, fontSize: 15, padding: 0 }}>×</button>
            </span>
          ))}
        </div>
      )}
      <div ref={boxRef} style={{ position: "relative" }} onBlur={(e) => { if (!boxRef.current?.contains(e.relatedTarget as Node)) setOpen(false); }}>
        <input className="input" value={query} placeholder={placeholder}
          onFocus={() => setOpen(true)} onChange={(e) => { setQuery(e.target.value); setOpen(true); }} />
        {open && matches.length > 0 && (
          <div style={{ position: "absolute", zIndex: 20, top: "calc(100% + 4px)", left: 0, right: 0, maxHeight: 240, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, boxShadow: "var(--shadow)" }}>
            {matches.map((o) => (
              <button key={o.value} type="button" onMouseDown={(e) => { e.preventDefault(); add(o.value); }}
                style={{ display: "block", width: "100%", textAlign: "left", padding: "9px 12px", border: "none", background: "transparent", cursor: "pointer", fontSize: 14, color: "var(--text)" }}>
                {o.label}
              </button>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
