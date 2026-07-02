"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { insertRow, updateRow, softDelete } from "../../../src/write";
import { FloatingInput } from "../../../src/ui/FloatingInput";

interface Label { id: string; name: string; color: string | null }

export default function ManageLabelsPage() {
  const { data: labels = [] } = useQuery<Label>("SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name");
  const [search, setSearch] = useState("");
  const [name, setName] = useState("");
  const [color, setColor] = useState("#b06a4f");

  const shown = labels.filter((l) => !search || l.name.toLowerCase().includes(search.toLowerCase()));

  async function add() {
    if (!name.trim()) return;
    await insertRow("labels", { name: name.trim(), color });
    setName("");
  }

  return (
    <div style={{ display: "grid", gap: 18, maxWidth: 720 }} className="fade-up">
      <Link href="/settings" className="muted" style={{ fontSize: 13 }}>← Settings</Link>
      <h1>Labels</h1>

      <div className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <FloatingInput label="Search labels…" value={search} onChange={setSearch} />
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          {shown.map((l) => <LabelItem key={l.id} label={l} />)}
          {shown.length === 0 && <span className="muted" style={{ fontSize: 13 }}>No labels found.</span>}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
          <FloatingInput label="New label" value={name} onChange={setName} style={{ maxWidth: 220, flex: 1 }} />
          <input type="color" value={color} onChange={(e) => setColor(e.target.value)} style={{ width: 44, height: 44, border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface)" }} />
          <button className="btn" onClick={add} disabled={!name.trim()}>Add label</button>
        </div>
      </div>
    </div>
  );
}

function LabelItem({ label }: { label: Label }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(label.name);
  const [color, setColor] = useState(label.color || "#b06a4f");
  async function save() { await updateRow("labels", label.id, { name: name.trim() || label.name, color }); setEditing(false); }
  const c = label.color || "#b06a4f";

  if (editing) {
    return (
      <span style={{ display: "inline-flex", gap: 6, alignItems: "center" }}>
        <input className="input" value={name} onChange={(e) => setName(e.target.value)} style={{ maxWidth: 130 }} />
        <input type="color" value={color} onChange={(e) => setColor(e.target.value)} style={{ width: 36, height: 34, border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface)" }} />
        <button className="chip" onClick={save}>Save</button>
        <button className="chip" onClick={() => setEditing(false)}>×</button>
      </span>
    );
  }
  return (
    <span style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "4px 10px", borderRadius: 999, background: c + "22", border: `1px solid ${c}` }}>
      <span style={{ width: 8, height: 8, borderRadius: 999, background: c }} />
      {label.name}
      <button className="chip" style={{ padding: "0 8px", fontSize: 11 }} onClick={() => { setName(label.name); setColor(label.color || "#b06a4f"); setEditing(true); }}>Edit</button>
      <button className="chip" style={{ padding: "0 6px" }} onClick={() => softDelete("labels", label.id)}>×</button>
    </span>
  );
}
