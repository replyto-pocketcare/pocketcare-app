"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import i18n, { SUPPORTED_LANGUAGES } from "@pocketcare/i18n";
import { Feature, canUse } from "@pocketcare/entitlements";
import { insertRow, updateRow, softDelete } from "../../src/write";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { useTier } from "../../src/hooks";
import { setTier } from "../../src/tier";
import { useTheme, setTheme } from "../../src/theme";
import { useBaseCurrency } from "../../src/hooks";
import { setBaseCurrency } from "../../src/prefs";
import { useSession, updateUsername, signOut } from "../../src/account";
import { Modal } from "../../src/ui/Modal";
import { SunIcon, MoonIcon } from "../../src/ui/icons";

const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];

export default function SettingsPage() {
  const base = useBaseCurrency();
  const [lang, setLang] = useState(typeof window !== "undefined" ? localStorage.getItem("lang") || "en" : "en");

  const { data: categories = [] } = useQuery<{ id: string; name: string; kind: string; parent_id: string | null }>(
    "SELECT id, name, kind, parent_id FROM categories WHERE deleted_at IS NULL ORDER BY kind, name",
  );
  const { data: labels = [] } = useQuery<{ id: string; name: string; color: string | null }>(
    "SELECT id, name, color FROM labels WHERE deleted_at IS NULL ORDER BY name",
  );
  const tier = useTier();
  const theme = useTheme();
  const session = useSession();

  const [username, setUsername] = useState("");
  const [savedName, setSavedName] = useState(false);
  const [confirmSignout, setConfirmSignout] = useState(false);
  useEffect(() => { if (session) setUsername(session.username); }, [session]);

  async function saveUsername() {
    await updateUsername(username.trim());
    setSavedName(true);
    setTimeout(() => setSavedName(false), 1500);
  }

  const [newCat, setNewCat] = useState(""); const [newKind, setNewKind] = useState<"expense" | "income">("expense");
  const [parentId, setParentId] = useState<string>("");
  const [labelName, setLabelName] = useState(""); const [labelColor, setLabelColor] = useState("#b06a4f");
  const [catSearch, setCatSearch] = useState("");
  const [openCats, setOpenCats] = useState<Set<string>>(new Set());
  const toggleCat = (id: string) => setOpenCats((s) => { const n = new Set(s); n.has(id) ? n.delete(id) : n.add(id); return n; });
  const matchesQ = (name: string) => !catSearch || name.toLowerCase().includes(catSearch.toLowerCase());
  const topCats = categories.filter((c) => !c.parent_id && c.kind === newKind);
  const childrenOf = (id: string) => categories.filter((c) => c.parent_id === id);

  function saveBase(c: string) { setBaseCurrency(c); }
  function saveLang(l: string) { setLang(l); localStorage.setItem("lang", l); void i18n.changeLanguage(l); }
  async function addCat() {
    if (!newCat.trim()) return;
    await insertRow("categories", { name: newCat.trim(), kind: newKind, is_system: 0, parent_id: parentId || null });
    setNewCat(""); setParentId("");
  }
  async function addLabel() {
    if (!labelName.trim()) return;
    await insertRow("labels", { name: labelName.trim(), color: labelColor });
    setLabelName("");
  }

  return (
    <div style={{ display: "grid", gap: 24, maxWidth: 700 }} className="fade-up">
      <h1>Settings</h1>

      {/* Account */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <h2>Account</h2>
        {session?.isGuest ? (
          <div style={{ padding: 12, borderRadius: 10, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", fontSize: 14 }}>
            You’re exploring as a <strong>guest</strong>.{" "}
            {session.daysLeft !== null && (
              <>Your data will be deleted in <strong>{session.daysLeft} day{session.daysLeft === 1 ? "" : "s"}</strong> unless you create an account.</>
            )}
            <div style={{ marginTop: 8 }}>
              <Link href="/login" className="btn" style={{ padding: "8px 14px" }}>Create account to keep my data</Link>
            </div>
          </div>
        ) : (
          <div className="muted" style={{ fontSize: 14 }}>Signed in as <strong style={{ color: "var(--text)" }}>{session?.email}</strong></div>
        )}

        <span className="muted" style={{ fontSize: 13 }}>Display name</span>
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label="Your name" value={username} onChange={setUsername} style={{ flex: 1 }} />
          <button className="btn ghost" onClick={saveUsername}>{savedName ? "Saved" : "Save"}</button>
        </div>
      </section>

      <Modal open={confirmSignout} onClose={() => setConfirmSignout(false)}>
        <h2 style={{ marginBottom: 8 }}>Sign out?</h2>
        {session?.isGuest ? (
          <p className="muted" style={{ fontSize: 14, lineHeight: 1.6 }}>
            You’re signed in as a <strong style={{ color: "var(--negative)" }}>guest</strong>. Signing out will
            <strong> permanently delete your data</strong> — your accounts, transactions, budgets and goals. You’ll start
            from scratch and have to enter everything again next time. Create an account first to keep it.
          </p>
        ) : (
          <p className="muted" style={{ fontSize: 14, lineHeight: 1.6 }}>You can sign back in any time to restore your data on this device.</p>
        )}
        <div style={{ display: "flex", gap: 10, marginTop: 18, justifyContent: "flex-end" }}>
          <button className="btn ghost" onClick={() => setConfirmSignout(false)}>Cancel</button>
          {session?.isGuest && <Link href="/login" className="btn" onClick={() => setConfirmSignout(false)}>Create account</Link>}
          <button className="chip" style={{ color: "var(--negative)", borderColor: "var(--negative)" }} onClick={() => signOut()}>Sign out anyway</button>
        </div>
      </Modal>

      {/* Theme */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Appearance</h2>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="chip" data-active={theme === "light"} onClick={() => setTheme("light")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><SunIcon size={15} /> Light</button>
          <button className="chip" data-active={theme === "dark"} onClick={() => setTheme("dark")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><MoonIcon size={15} /> Dark</button>
        </div>
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Base currency</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>Net worth and roll-ups convert to this currency.</p>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {CURRENCIES.map((c) => <button key={c} className="chip" data-active={c === base} onClick={() => saveBase(c)}>{c}</button>)}
        </div>
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Language</h2>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {SUPPORTED_LANGUAGES.map((l) => <button key={l.code} className="chip" data-active={l.code === lang} onClick={() => saveLang(l.code)}>{l.label}</button>)}
        </div>
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Categories & sub-categories</h2>
        <FloatingInput label="Search categories…" value={catSearch} onChange={setCatSearch} />
        <div style={{ display: "grid", gap: 4 }}>
          {categories.filter((c) => !c.parent_id).map((parent) => {
            const kids = childrenOf(parent.id);
            const parentMatch = matchesQ(parent.name);
            const matchingKids = kids.filter((k) => matchesQ(k.name));
            if (catSearch && !parentMatch && matchingKids.length === 0) return null;
            const open = catSearch ? true : openCats.has(parent.id);
            const shownKids = catSearch && !parentMatch ? matchingKids : kids;
            return (
              <div key={parent.id} style={{ display: "grid", gap: 2 }}>
                <div style={{ display: "flex", alignItems: "center", gap: 6 }}>
                  <button onClick={() => toggleCat(parent.id)} aria-label={open ? "Collapse" : "Expand"}
                    style={{ width: 24, height: 24, border: "1px solid var(--border)", borderRadius: 7, background: "var(--surface)", cursor: "pointer", color: "var(--text-2)", flexShrink: 0 }}>
                    {open ? "−" : "+"}
                  </button>
                  <div style={{ flex: 1 }}><CatItem cat={parent} childCount={kids.length} /></div>
                </div>
                {open && shownKids.map((sub) => <CatItem key={sub.id} cat={sub} indent />)}
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
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Labels</h2>
        <div style={{ display: "flex", flexWrap: "wrap", gap: 8 }}>
          {labels.map((l) => <LabelItem key={l.id} label={l} />)}
          {labels.length === 0 && <span className="muted" style={{ fontSize: 13 }}>No labels yet.</span>}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <FloatingInput label="Label name" value={labelName} onChange={setLabelName} style={{ maxWidth: 200, flex: 1 }} />
          <input type="color" value={labelColor} onChange={(e) => setLabelColor(e.target.value)} style={{ width: 44, height: 40, border: "1px solid var(--border)", borderRadius: 8, background: "var(--surface)" }} />
          <button className="btn" onClick={addLabel} disabled={!labelName.trim()}>Add label</button>
        </div>
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Plan</h2>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
          <span>You are on the <strong style={{ textTransform: "capitalize" }}>{tier}</strong> plan.</span>
          <div style={{ display: "flex", gap: 6 }}>
            <button className="chip" data-active={tier === "free"} onClick={() => setTier("free")}>Free</button>
            <button className="chip" data-active={tier === "premium"} onClick={() => setTier("premium")}>Premium</button>
          </div>
        </div>
        <p className="muted" style={{ fontSize: 13 }}>
          Toggle to preview both tiers. Advanced insights {canUse(Feature.AdvancedAnalytics, tier) ? "included" : "Premium"} ·
          Statements {canUse(Feature.Statements, tier) ? "included" : "Premium"} ·
          Subscription simulator {canUse(Feature.SubscriptionSimulator, tier) ? "included" : "Premium"}
        </p>
      </section>

      {/* Help & Support */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Help & Support</h2>
        <div style={{ display: "grid", gap: 6 }}>
          <a href="mailto:support@pocketcare.app" className="chip" style={{ justifySelf: "start" }}>Contact support</a>
          <Link href="/onboarding" className="chip" style={{ justifySelf: "start" }}>Replay the intro</Link>
          <span className="muted" style={{ fontSize: 12 }}>PocketCare · your data is stored on your device and synced securely. Guest data is removed after 3 days if you don’t register.</span>
        </div>
      </section>

      {/* Sign out (kept at the very end) */}
      <section style={{ display: "flex", justifyContent: "center", paddingTop: 4, paddingBottom: 24 }}>
        <button className="btn ghost" style={{ color: "var(--negative)", borderColor: "var(--negative)" }} onClick={() => setConfirmSignout(true)}>Sign out</button>
      </section>
    </div>
  );
}

function CatItem({ cat, indent, childCount }: { cat: { id: string; name: string; kind: string }; indent?: boolean; childCount?: number }) {
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

function LabelItem({ label }: { label: { id: string; name: string; color: string | null } }) {
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
