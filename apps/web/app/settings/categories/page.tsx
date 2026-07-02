"use client";

import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import { insertRow, updateRow, softDelete } from "../../../src/write";
import { FloatingInput } from "../../../src/ui/FloatingInput";

interface Cat { id: string; name: string; kind: string; parent_id: string | null }

export default function ManageCategoriesPage() {
  const { data: categories = [] } = useQuery<Cat>(
    "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY kind, name",
  );
  const childrenOf = (id: string) => categories.filter((c) => c.parent_id === id);

  const [newCat, setNewCat] = useState("");
  const [newKind, setNewKind] = useState<"expense" | "income">("expense");
  const [parentId, setParentId] = useState("");
  const [search, setSearch] = useState("");
  const [open, setOpen] = useState<Set<string>>(new Set());
  const toggle = (id: string) => setOpen((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const matches = (name: string) => !search || name.toLowerCase().includes(search.toLowerCase());
  const topCats = categories.filter((c) => !c.parent_id && c.kind === newKind);

  async function addCat() {
    if (!newCat.trim()) return;
    await insertRow("categories", { name: newCat.trim(), kind: newKind, is_system: 0, parent_id: parentId || null });
    setNewCat(""); setParentId("");
  }

  return (
    <div style={{ display: "grid", gap: 18, maxWidth: 720 }} className="fade-up">
      <Link href="/settings" className="muted" style={{ fontSize: 13 }}>← Settings</Link>
      <h1>Categories</h1>

      <div className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <FloatingInput label="Search categories…" value={search} onChange={setSearch} />
        <div style={{ display: "grid", gap: 4 }}>
          {categories.filter((c) => !c.parent_id).map((parent) => {
            const kids = childrenOf(parent.id);
            const parentMatch = matches(parent.name);
            const matchingKids = kids.filter((k) => matches(k.name));
            if (search && !parentMatch && matchingKids.length === 0) return null;
            const isOpen = search ? true : open.has(parent.id);
            const shownKids = search && !parentMatch ? matchingKids : kids;
            return (
              <div key={parent.id} style={{ display: "grid", gap: 2 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <button onClick={() => toggle(parent.id)} aria-label={isOpen ? "Collapse" : "Expand"}
                    style={{ width: 24, height: 24, border: "1px solid var(--border)", borderRadius: 7, background: "var(--surface)", cursor: "pointer", color: "var(--text-2)", flexShrink: 0 }}>
                    {isOpen ? "−" : "+"}
                  </button>
                  <div style={{ flex: 1 }}><CatItem cat={parent} childCount={kids.length} /></div>
                </div>
                {isOpen && shownKids.map((sub) => <CatItem key={sub.id} cat={sub} indent />)}
              </div>
            );
          })}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 8, flexWrap: "wrap" }}>
          <FloatingInput label="New category" value={newCat} onChange={setNewCat} style={{ maxWidth: 180, flex: 1 }} />
          <button className="chip" data-active={newKind === "expense"} onClick={() => setNewKind("expense")}>Expense</button>
          <button className="chip" data-active={newKind === "income"} onClick={() => setNewKind("income")}>Income</button>
          <select className="input" style={{ maxWidth: 200 }} value={parentId} onChange={(e) => setParentId(e.target.value)}>
            <option value="">— top level —</option>
            {topCats.map((c) => <option key={c.id} value={c.id}>under {c.name}</option>)}
          </select>
          <button className="btn" onClick={addCat} disabled={!newCat.trim()}>Add</button>
        </div>
      </div>
    </div>
  );
}

function CatItem({ cat, indent, childCount }: { cat: Cat; indent?: boolean; childCount?: number }) {
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(cat.name);
  async function save() { await updateRow("categories", cat.id, { name: name.trim() || cat.name }); setEditing(false); }

  if (editing) {
    return (
      <div style={{ display: "flex", gap: 8, padding: indent ? "4px 10px 4px 26px" : "4px 10px", alignItems: "center" }}>
        <FloatingInput label="Name" value={name} onChange={setName} style={{ flex: 1 }} />
        <button className="chip" onClick={save}>Save</button>
        <button className="chip" onClick={() => setEditing(false)}>Cancel</button>
      </div>
    );
  }
  return (
    <div className={indent ? "muted" : ""} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: indent ? "5px 10px 5px 26px" : "6px 10px", border: indent ? "none" : "1px solid var(--border)", borderRadius: 8, fontSize: indent ? 13 : 14 }}>
      <span>{indent ? "↳ " : ""}{cat.name}{!indent && <span className="muted" style={{ fontSize: 11 }}> {cat.kind}{childCount ? ` · ${childCount}` : ""}</span>}</span>
      <span style={{ display: "flex", gap: 6 }}>
        <button className="chip" style={{ padding: "2px 8px", fontSize: 12 }} onClick={() => { setName(cat.name); setEditing(true); }}>Edit</button>
        <button className="chip" style={{ padding: "2px 8px" }} onClick={() => softDelete("categories", cat.id)}>×</button>
      </span>
    </div>
  );
}
