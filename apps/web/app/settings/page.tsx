"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import { useQuery } from "@powersync/react";
import i18n, { SUPPORTED_LANGUAGES } from "@pocketcare/i18n";
import { Feature, canUse } from "@pocketcare/entitlements";
import { insertRow, softDelete } from "../../src/write";
import { useTier } from "../../src/hooks";
import { setTier } from "../../src/tier";
import { useTheme, setTheme } from "../../src/theme";
import { useSession, updateUsername, signOut } from "../../src/account";
import { Modal } from "../../src/ui/Modal";

const CURRENCIES = ["USD", "EUR", "GBP", "INR", "JPY", "AUD", "CAD"];

export default function SettingsPage() {
  const [base, setBase] = useState(typeof window !== "undefined" ? localStorage.getItem("baseCurrency") || "USD" : "USD");
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
  const topCats = categories.filter((c) => !c.parent_id && c.kind === newKind);
  const childrenOf = (id: string) => categories.filter((c) => c.parent_id === id);

  function saveBase(c: string) { setBase(c); localStorage.setItem("baseCurrency", c); }
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
          <input className="input" placeholder="Your name" value={username} onChange={(e) => setUsername(e.target.value)} />
          <button className="btn ghost" onClick={saveUsername}>{savedName ? "Saved ✓" : "Save"}</button>
        </div>

        <div>
          <button className="chip" style={{ color: "var(--negative)" }} onClick={() => setConfirmSignout(true)}>Sign out</button>
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
          <button className="chip" data-active={theme === "light"} onClick={() => setTheme("light")}>☀ Light</button>
          <button className="chip" data-active={theme === "dark"} onClick={() => setTheme("dark")}>☾ Dark</button>
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
        <div style={{ display: "grid", gap: 4 }}>
          {categories.filter((c) => !c.parent_id).map((c) => (
            <div key={c.id} style={{ display: "grid", gap: 2 }}>
              <div style={{ display: "flex", justifyContent: "space-between", padding: "6px 10px", border: "1px solid var(--border)", borderRadius: 8 }}>
                <span>{c.name} <span className="muted" style={{ fontSize: 11 }}>{c.kind}</span></span>
                <button className="chip" style={{ padding: "2px 8px" }} onClick={() => softDelete("categories", c.id)}>×</button>
              </div>
              {childrenOf(c.id).map((sub) => (
                <div key={sub.id} style={{ display: "flex", justifyContent: "space-between", padding: "5px 10px 5px 26px", fontSize: 13 }} className="muted">
                  <span>↳ {sub.name}</span>
                  <button className="chip" style={{ padding: "2px 8px" }} onClick={() => softDelete("categories", sub.id)}>×</button>
                </div>
              ))}
            </div>
          ))}
        </div>
        <div style={{ display: "flex", gap: 8, marginTop: 8, flexWrap: "wrap" }}>
          <input className="input" placeholder="New category" value={newCat} onChange={(e) => setNewCat(e.target.value)} style={{ maxWidth: 180 }} />
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
          {labels.map((l) => (
            <span key={l.id} style={{ display: "inline-flex", alignItems: "center", gap: 6, padding: "4px 10px", borderRadius: 999, background: (l.color || "#b06a4f") + "22", border: `1px solid ${l.color || "#b06a4f"}` }}>
              <span style={{ width: 8, height: 8, borderRadius: 999, background: l.color || "#b06a4f" }} />
              {l.name}
              <button className="chip" style={{ padding: "0 6px" }} onClick={() => softDelete("labels", l.id)}>×</button>
            </span>
          ))}
          {labels.length === 0 && <span className="muted" style={{ fontSize: 13 }}>No labels yet.</span>}
        </div>
        <div style={{ display: "flex", gap: 8 }}>
          <input className="input" placeholder="Label name" value={labelName} onChange={(e) => setLabelName(e.target.value)} style={{ maxWidth: 200 }} />
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
          Toggle to preview both tiers. Advanced insights {canUse(Feature.AdvancedAnalytics, tier) ? "✓" : "🔒"} ·
          Statements {canUse(Feature.Statements, tier) ? "✓" : "🔒"} ·
          Subscription simulator {canUse(Feature.SubscriptionSimulator, tier) ? "✓" : "🔒"}
        </p>
      </section>

      {/* Help & Support */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>Help & Support</h2>
        <div style={{ display: "grid", gap: 6 }}>
          <a href="mailto:support@pocketcare.app" className="chip" style={{ justifySelf: "start" }}>✉ Contact support</a>
          <Link href="/onboarding" className="chip" style={{ justifySelf: "start" }}>↻ Replay the intro</Link>
          <span className="muted" style={{ fontSize: 12 }}>PocketCare · your data is stored on your device and synced securely. Guest data is removed after 3 days if you don’t register.</span>
        </div>
      </section>
    </div>
  );
}
