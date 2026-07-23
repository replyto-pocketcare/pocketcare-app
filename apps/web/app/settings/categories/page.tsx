"use client";

import { useState } from "react";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useQuery } from "@powersync/react";
import { insertRow, updateRow, softDelete } from "../../../src/write";
import { FloatingInput } from "../../../src/ui/FloatingInput";
import { useConfirm } from "../../../src/ui/Confirm";
import { autoCategorize, type AutoCatResult } from "../../../src/categorize/autoJob";

interface Cat { id: string; name: string; kind: string; parent_id: string | null }

export default function ManageCategoriesPage() {
  const { t } = useTranslation("categories");
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
      <Link href="/settings" className="muted" style={{ fontSize: 13 }}>{t("backToSettings")}</Link>
      <h1>{t("title")}</h1>

      <AutoCategorizeCard categories={categories} />


      <div className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <FloatingInput label={t("searchPlaceholder")} value={search} onChange={setSearch} />
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
                  <button onClick={() => toggle(parent.id)} aria-label={isOpen ? t("collapse") : t("expand")}
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
          <FloatingInput label={t("newCategory")} value={newCat} onChange={setNewCat} style={{ maxWidth: 180, flex: 1 }} />
          <button className="chip" data-active={newKind === "expense"} onClick={() => setNewKind("expense")}>{t("expense")}</button>
          <button className="chip" data-active={newKind === "income"} onClick={() => setNewKind("income")}>{t("income")}</button>
          <select className="input" style={{ maxWidth: 200 }} value={parentId} onChange={(e) => setParentId(e.target.value)}>
            <option value="">{t("topLevel")}</option>
            {topCats.map((c) => <option key={c.id} value={c.id}>{t("under", { name: c.name })}</option>)}
          </select>
          <button className="btn" onClick={addCat} disabled={!newCat.trim()}>{t("add")}</button>
        </div>
      </div>
    </div>
  );
}

function CatItem({ cat, indent, childCount }: { cat: Cat; indent?: boolean; childCount?: number }) {
  const { t } = useTranslation("categories");
  const confirm = useConfirm();
  const [editing, setEditing] = useState(false);
  const [name, setName] = useState(cat.name);
  async function save() { await updateRow("categories", cat.id, { name: name.trim() || cat.name }); setEditing(false); }

  if (editing) {
    return (
      <div style={{ display: "flex", gap: 8, padding: indent ? "4px 10px 4px 26px" : "4px 10px", alignItems: "center" }}>
        <FloatingInput label={t("name")} value={name} onChange={setName} style={{ flex: 1 }} />
        <button className="chip" onClick={save}>{t("save")}</button>
        <button className="chip" onClick={() => setEditing(false)}>{t("cancel")}</button>
      </div>
    );
  }
  return (
    <div className={indent ? "muted" : ""} style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: indent ? "5px 10px 5px 26px" : "6px 10px", border: indent ? "none" : "1px solid var(--border)", borderRadius: 8, fontSize: indent ? 13 : 14 }}>
      <span>{indent ? "↳ " : ""}{cat.name}{!indent && <span className="muted" style={{ fontSize: 11 }}> {t(`kind.${cat.kind}`, cat.kind)}{childCount ? ` · ${childCount}` : ""}</span>}</span>
      <span style={{ display: "flex", gap: 6 }}>
        <button className="chip" style={{ padding: "2px 8px", fontSize: 12 }} onClick={() => { setName(cat.name); setEditing(true); }}>{t("edit")}</button>
        <button className="chip" style={{ padding: "2px 8px" }} onClick={async () => { if (await confirm({ title: t("deleteTitle"), message: t("deleteMsg", { name: cat.name }) })) softDelete("categories", cat.id); }}>×</button>
      </span>
    </div>
  );
}

/**
 * One-tap bulk auto-categorization of existing uncategorized expenses. Previews
 * how many would be tagged, then applies them all in a single batched write.
 */
function AutoCategorizeCard({ categories }: { categories: Cat[] }) {
  const { t } = useTranslation("categories");
  const [busy, setBusy] = useState(false);
  const [preview, setPreview] = useState<AutoCatResult | null>(null);
  const [done, setDone] = useState<number | null>(null);

  const cats = categories.map((c) => ({ id: c.id, name: c.name }));

  async function runPreview() {
    setBusy(true); setDone(null);
    try { setPreview(await autoCategorize(cats, { apply: false })); }
    finally { setBusy(false); }
  }
  async function apply() {
    setBusy(true);
    try {
      const r = await autoCategorize(cats, { apply: true });
      setDone(r.categorized); setPreview(null);
    } finally { setBusy(false); }
  }

  return (
    <div className="card" style={{ padding: 18, display: "grid", gap: 10 }}>
      <div style={{ display: "grid", gap: 2 }}>
        <strong style={{ fontSize: 15 }}>{t("autoCatTitle", "Auto-categorize")}</strong>
        <span className="muted" style={{ fontSize: 12.5 }}>{t("autoCatBlurb", "Scan your uncategorized expenses and tag them automatically using merchant names. Runs on-device.")}</span>
      </div>
      {preview && (
        <div style={{ fontSize: 13 }}>
          {preview.categorized > 0
            ? t("autoCatPreview", { count: preview.categorized, scanned: preview.scanned, defaultValue: "{{count}} of {{scanned}} uncategorized expenses can be tagged." })
            : t("autoCatNone", { scanned: preview.scanned, defaultValue: "No matches found across {{scanned}} uncategorized expenses." })}
        </div>
      )}
      {done != null && <div style={{ fontSize: 13, color: "var(--positive)" }}>{t("autoCatDone", { count: done, defaultValue: "Categorized {{count}} transactions." })}</div>}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
        {!preview || preview.categorized === 0
          ? <button className="btn ghost" disabled={busy} onClick={() => void runPreview()}>{busy ? t("autoCatWorking", "Scanning…") : t("autoCatScan", "Scan uncategorized")}</button>
          : <>
              <button className="btn" disabled={busy} onClick={() => void apply()}>{busy ? t("autoCatWorking", "Working…") : t("autoCatApply", { count: preview.categorized, defaultValue: "Categorize {{count}}" })}</button>
              <button className="btn ghost" disabled={busy} onClick={() => setPreview(null)}>{t("cancel")}</button>
            </>}
      </div>
    </div>
  );
}
