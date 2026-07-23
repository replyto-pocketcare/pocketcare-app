"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { insertRow, updateRow, softDelete } from "../../../src/write";
import { FloatingInput } from "../../../src/ui/FloatingInput";
import { useConfirm } from "../../../src/ui/Confirm";

interface Label { id: string; name: string; color: string | null }

export default function ManageLabelsPage() {
  const { t } = useTranslation("labels");
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
      <Link href="/settings" className="muted" style={{ fontSize: 13 }}>{t("backToSettings")}</Link>
      <h1>{t("title")}</h1>

      <div className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <FloatingInput label={t("searchPlaceholder")} value={search} onChange={setSearch} />
        <div style={{ display: "grid", gap: 8, marginTop: 8 }}>
          {shown.map((l) => <LabelItem key={l.id} label={l} />)}
          {shown.length === 0 && <span className="muted" style={{ fontSize: 13 }}>{t("noLabels")}</span>}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 16 }}>
          <FloatingInput label={t("newLabel")} value={name} onChange={setName} style={{ maxWidth: 220, flex: 1 }} />
          <input type="color" value={color} onChange={(e) => setColor(e.target.value)} style={{ width: 44, height: 44, border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface)" }} />
          <button className="btn" onClick={add} disabled={!name.trim()}>{t("addLabel")}</button>
        </div>
      </div>
    </div>
  );
}

const EditIcon = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7" /><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" /></svg>
);
const TrashIcon = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 6 5 6 21 6" /><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2" /></svg>
);

function LabelItem({ label }: { label: Label }) {
  const { t } = useTranslation("labels");
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(label.name);
  const [color, setColor] = useState(label.color || "#b06a4f");
  async function save() { await updateRow("labels", label.id, { name: name.trim() || label.name, color }); setEditing(false); }
  const c = label.color || "#b06a4f";

  if (editing) {
    return (
      <div style={{ display: "flex", gap: 10, alignItems: "center", padding: "12px", border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface-1)" }}>
        <input className="input" value={name} onChange={(e) => setName(e.target.value)} style={{ flex: 1, minWidth: 0 }} />
        <input type="color" value={color} onChange={(e) => setColor(e.target.value)} style={{ width: 36, height: 34, border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface)" }} />
        <button className="chip" onClick={save}>{t("save")}</button>
        <button className="chip" onClick={() => setEditing(false)}>{t("cancel")}</button>
      </div>
    );
  }
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 10, padding: "12px", border: "1px solid var(--border)", borderRadius: 8 }}>
      <div style={{ display: "flex", alignItems: "center", gap: 10, minWidth: 0 }}>
        <span style={{ width: 14, height: 14, borderRadius: 999, background: c }} />
        <span style={{ fontWeight: 500, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{label.name}</span>
      </div>
      <div style={{ display: "flex", gap: 6, flexShrink: 0 }}>
        <button className="chip" style={{ padding: "8px" }} onClick={() => { setName(label.name); setColor(label.color || "#b06a4f"); setEditing(true); }} aria-label={t("edit")}>
          <EditIcon />
        </button>
        <button className="chip" style={{ padding: "8px", color: "var(--negative)" }} onClick={async () => { if (await confirm({ title: t("deleteTitle"), message: t("deleteMsg", { name: label.name }) })) softDelete("labels", label.id); }} aria-label={t("delete")}>
          <TrashIcon />
        </button>
      </div>
    </div>
  );
}
