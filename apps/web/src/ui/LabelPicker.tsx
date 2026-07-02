"use client";

import { useState } from "react";

export interface LabelOption { id: string; name: string; color: string | null }

/** Multi-select labels: removable colored pills + a dropdown to add + custom entry. */
export function LabelPicker({ labels, selected, onChange }: {
  labels: LabelOption[];
  selected: string[];
  onChange: (next: string[]) => void;
}) {
  const [custom, setCustom] = useState("");
  const colorOf = (name: string) => labels.find((l) => l.name === name)?.color || "#b06a4f";
  const available = labels.filter((l) => !selected.includes(l.name));

  const add = (name: string) => {
    const n = name.trim();
    if (n && !selected.includes(n)) onChange([...selected, n]);
  };
  const remove = (name: string) => onChange(selected.filter((s) => s !== name));

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
      <div style={{ display: "flex", gap: 8 }}>
        <select className="input" value="" onChange={(e) => { add(e.target.value); e.currentTarget.value = ""; }} disabled={available.length === 0}>
          <option value="">{available.length ? "Add a label…" : "All labels added"}</option>
          {available.map((l) => <option key={l.id} value={l.name}>{l.name}</option>)}
        </select>
        <input className="input" style={{ maxWidth: 160 }} placeholder="Custom…" value={custom}
          onChange={(e) => setCustom(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter") { e.preventDefault(); add(custom); setCustom(""); } }} />
        <button type="button" className="chip" onClick={() => { add(custom); setCustom(""); }} disabled={!custom.trim()}>Add</button>
      </div>
    </div>
  );
}
