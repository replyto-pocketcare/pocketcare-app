"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import i18n, { SUPPORTED_LANGUAGES } from "@pocketcare/i18n";
import { Feature, canUse } from "@pocketcare/entitlements";
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

  function saveBase(c: string) { setBaseCurrency(c); }
  function saveLang(l: string) { setLang(l); localStorage.setItem("lang", l); void i18n.changeLanguage(l); }

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

      <section className="card" style={{ padding: 20, display: "grid", gap: 8 }}>
        <h2>Categories & labels</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -2 }}>Organise how you tag and group your transactions.</p>
        <div style={{ display: "flex", gap: 10, flexWrap: "wrap", marginTop: 4 }}>
          <Link href="/settings/categories" className="btn ghost">Manage categories</Link>
          <Link href="/settings/labels" className="btn ghost">Manage labels</Link>
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
