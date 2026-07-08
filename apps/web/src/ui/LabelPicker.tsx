"use client";

import { useMemo, useRef, useState } from "react";

export interface LabelOption { id: string; name: string; color: string | null }

/** Multi-select labels with type-to-search + custom add; selected shown as pills. */
export function LabelPicker({ labels, selected, onChange }: {
  labels: LabelOption[];
  selected: string[];
  onChange: (next: string[]) => void;
}) {
  const [query, setQuery] = useState("");
  const [open, setOpen] = useState(false);
  const boxRef = useRef<HTMLDivElement>(null);
  const colorOf = (name: string) => labels.find((l) => l.name === name)?.color || "#b06a4f";

  const matches = useMemo(() => {
    const q = query.trim().toLowerCase();
    
    // Sort recently used labels first
    let recentLabels: string[] = [];
    try {
      const stored = localStorage.getItem("pocketcare:recent-labels");
      if (stored) recentLabels = JSON.parse(stored);
    } catch (e) {}

    const filtered = labels
      .filter((l) => !selected.includes(l.name) && (!q || l.name.toLowerCase().includes(q)));
      
    // Sort: recent first, then alphabetical
    filtered.sort((a, b) => {
      const idxA = recentLabels.indexOf(a.name);
      const idxB = recentLabels.indexOf(b.name);
      if (idxA !== -1 && idxB !== -1) return idxA - idxB;
      if (idxA !== -1) return -1;
      if (idxB !== -1) return 1;
      return a.name.localeCompare(b.name);
    });

    return filtered.slice(0, 30);
  }, [query, labels, selected]);

  const add = (name: string) => {
    const n = name.trim();
    if (n && !selected.includes(n)) {
      onChange([...selected, n]);
      
      // Update recently used in localStorage
      try {
        const stored = localStorage.getItem("pocketcare:recent-labels");
        let recent: string[] = stored ? JSON.parse(stored) : [];
        recent = [n, ...recent.filter(l => l !== n)].slice(0, 10); // keep last 10
        localStorage.setItem("pocketcare:recent-labels", JSON.stringify(recent));
      } catch (e) {}
    }
    setQuery("");
  };
  const remove = (name: string) => onChange(selected.filter((s) => s !== name));
  const exact = labels.some((l) => l.name.toLowerCase() === query.trim().toLowerCase());

  return (
    <div style={{ display: "grid", gap: 8 }}>
      {selected.length > 0 && (
        <div style={{ display: "flex", flexWrap: "wrap", gap: 6 }}>
          {selected.map((name) => {
            const c = colorOf(name);
            return (
              <span key={name} style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "5px 10px", borderRadius: 999, border: `1px solid ${c}`, background: `${c}22`, fontSize: 13 }}>
                <span style={{ width: 8, height: 8, borderRadius: 999, background: c }} />
                {name}
                <button type="button" onClick={() => remove(name)} aria-label={`Remove ${name}`}
                  style={{ border: "none", background: "transparent", cursor: "pointer", color: "var(--text-2)", lineHeight: 1, fontSize: 15, padding: 0 }}>×</button>
              </span>
            );
          })}
        </div>
      )}
      <div ref={boxRef} style={{ position: "relative" }} onBlur={(e) => { if (!boxRef.current?.contains(e.relatedTarget as Node)) setOpen(false); }}>
        <input className="input" value={query} placeholder="Search or add a label…"
          onFocus={() => setOpen(true)}
          onChange={(e) => { setQuery(e.target.value); setOpen(true); }}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(matches[0]?.name ?? query); } }} />
        {open && (query || matches.length > 0) && (
          <div style={{ position: "absolute", zIndex: 20, top: "calc(100% + 4px)", left: 0, right: 0, maxHeight: 220, overflowY: "auto", background: "var(--surface)", border: "1px solid var(--border)", borderRadius: 10, boxShadow: "var(--shadow)" }}>
            {matches.map((l) => {
              const c = l.color || "#b06a4f";
              return (
                <button key={l.id} type="button" onMouseDown={(e) => { e.preventDefault(); add(l.name); }}
                  style={{ display: "flex", alignItems: "center", gap: 8, width: "100%", textAlign: "left", padding: "8px 12px", border: "none", background: "transparent", cursor: "pointer", fontSize: 14 }}>
                  <span style={{ width: 8, height: 8, borderRadius: 999, background: c }} /> {l.name}
                </button>
              );
            })}
            {query.trim() && !exact && (
              <button type="button" onMouseDown={(e) => { e.preventDefault(); add(query); }}
                style={{ display: "block", width: "100%", textAlign: "left", padding: "8px 12px", border: "none", borderTop: matches.length ? "1px solid var(--border)" : "none", background: "transparent", cursor: "pointer", fontSize: 14, color: "var(--accent)" }}>
                + Add “{query.trim()}”
              </button>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
