"use client";

import { useEffect, useState } from "react";
import Link from "next/link";
import i18n, { SUPPORTED_LANGUAGES } from "@pocketcare/i18n";
import { useTranslation } from "react-i18next";
import { FloatingInput } from "../../src/ui/FloatingInput";
import { Billing } from "../../src/ui/Billing";
import { useTheme, setTheme } from "../../src/theme";
import { useBaseCurrency } from "../../src/hooks";
import { setBaseCurrency, useAmountsHidden, setAmountsHidden } from "../../src/prefs";
import { useSession, updateUsername, signOut } from "../../src/account";
import { useConfirm } from "../../src/ui/Confirm";
import { useSyncStatus, syncMessage } from "../../src/sync";
import { Modal } from "../../src/ui/Modal";
import { SunIcon, MoonIcon, EyeIcon, EyeOffIcon } from "../../src/ui/icons";
import { SecurityPanel } from "../../src/crypto/SecurityPanel";
import { ProfileTraits } from "../../src/ui/ProfileTraits";

const CURRENCIES = ["INR", "USD", "EUR", "GBP", "JPY", "AUD", "CAD", "SGD", "AED"];

export default function SettingsPage() {
  const base = useBaseCurrency();
  const [lang, setLang] = useState(typeof window !== "undefined" ? localStorage.getItem("lang") || "en" : "en");
  const theme = useTheme();
  const session = useSession();
  const sync = useSyncStatus();
  const amountsHidden = useAmountsHidden();
  const { t } = useTranslation();

  const [username, setUsername] = useState("");
  const [savedName, setSavedName] = useState(false);
  const [confirmSignout, setConfirmSignout] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [deleteErr, setDeleteErr] = useState<string | null>(null);
  const confirm = useConfirm();

  async function replayIntro() {
    if (!(await confirm({
      title: "Replay the intro?",
      message: "You’ll be signed out and taken back to the welcome screens. You’ll need to sign in again afterwards.",
      confirmLabel: "Replay intro",
      danger: false,
    }))) return;
    if (typeof window !== "undefined") localStorage.removeItem("onboardingSeen");
    await signOut(); // routes to /onboarding
  }

  useEffect(() => { if (session) setUsername(session.username); }, [session]);

  async function deleteAccount() {
    setDeleting(true);
    setDeleteErr(null);
    try {
      const { getSupabase } = await import("../../src/powersync");
      const supabase = getSupabase();
      // The RPC lives in the `pocketcare` schema (same as every table), so it
      // must be called schema-qualified — a plain supabase.rpc() hits `public`
      // and 404s, which is why deletes silently did nothing before.
      const { error } = await supabase.schema("pocketcare").rpc("delete_user_account", { orphan_records: false });
      if (error) {
        // Wipe the local mirror so the just-deleted data can't linger / re-upload,
        // then sign out to a clean slate.
        setDeleteErr(error.message || "Couldn’t delete your account. Please try again.");
        setDeleting(false);
        return;
      }
      try {
        const { getDb } = await import("../../src/powersync");
        await getDb()?.disconnectAndClear();
      } catch { /* best-effort local clear; signOut reloads regardless */ }
      await signOut(); // reloads to /onboarding with a fresh, empty session
    } catch (e) {
      setDeleteErr(e instanceof Error ? e.message : "Couldn’t delete your account. Please try again.");
      setDeleting(false);
    }
  }

  async function saveUsername() {
    await updateUsername(username.trim());
    setSavedName(true);
    setTimeout(() => setSavedName(false), 1500);
  }

  function saveBase(c: string) { setBaseCurrency(c); }
  function saveLang(l: string) {
    setLang(l);
    localStorage.setItem("lang", l);
    void i18n.changeLanguage(l);
    if (typeof document !== "undefined") document.documentElement.lang = l;
  }

  return (
    <div style={{ display: "grid", gap: 24, maxWidth: 700 }} className="fade-up">
      <h1>{t("pages.settings", "Settings")}</h1>

      {/* Account */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 12 }}>
        <h2>{t("settings.account", "Account")}</h2>
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

        <div className="muted" style={{ fontSize: 13, display: "flex", alignItems: "center", gap: 6 }}>
          {(() => {
            const m = syncMessage(sync);
            let dot = "var(--positive)";
            let text: string;
            if (m) {
              dot = m.tone === "warn" ? "var(--warning)" : "var(--text-2)";
              text = m.text;
            } else if (sync.uploading || sync.downloading) {
              text = "Syncing…";
            } else if (sync.lastSyncedAt) {
              text = `Synced · ${sync.lastSyncedAt.toLocaleTimeString()}`;
            } else if (sync.hasSynced) {
              text = "All changes synced";
            } else {
              dot = "var(--warning)";
              text = "Connecting…";
            }
            return (<><span style={{ width: 8, height: 8, borderRadius: 999, background: dot }} />{text}</>);
          })()}
        </div>

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
        <h2>{t("settings.appearance", "Appearance")}</h2>
        <div style={{ display: "flex", gap: 6 }}>
          <button className="chip" data-active={theme === "light"} onClick={() => setTheme("light")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><SunIcon size={15} /> Light</button>
          <button className="chip" data-active={theme === "dark"} onClick={() => setTheme("dark")} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}><MoonIcon size={15} /> Dark</button>
        </div>
      </section>

      {/* Privacy */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>{t("settings.privacy", "Privacy")}</h2>
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", gap: 12, flexWrap: "wrap" }}>
          <span style={{ fontSize: 14 }}>
            {t("settings.hideAmounts", "Hide amounts everywhere")}
            <div className="muted" style={{ fontSize: 12 }}>Masks balances and amounts across the app. You can flip it anytime.</div>
          </span>
          <button className="chip" data-active={amountsHidden} onClick={() => setAmountsHidden(!amountsHidden)} style={{ display: "inline-flex", alignItems: "center", gap: 6 }}>
            {amountsHidden ? <EyeOffIcon size={15} /> : <EyeIcon size={15} />} {amountsHidden ? "Hidden" : "Visible"}
          </button>
        </div>
      </section>

      <ProfileTraits />

      <SecurityPanel />

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>{t("settings.baseCurrency", "Base currency")}</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -4 }}>Net worth and roll-ups convert to this currency.</p>
        <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
          {CURRENCIES.map((c) => <button key={c} className="chip" data-active={c === base} onClick={() => saveBase(c)}>{c}</button>)}
        </div>
      </section>

      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>{t("settings.language", "Language")}</h2>
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

      <section className="card" style={{ padding: 20, display: "grid", gap: 8 }}>
        <h2>Import & export</h2>
        <p className="muted" style={{ fontSize: 13, marginTop: -2 }}>Back up your transactions to CSV, or bring data in from a CSV (incl. Wallet by BudgetBakers — beta).</p>
        <div style={{ marginTop: 4 }}>
          <Link href="/data" className="btn ghost">Import / export data</Link>
        </div>
      </section>

      <Billing />

      {/* Help & Support */}
      <section className="card" style={{ padding: 20, display: "grid", gap: 10 }}>
        <h2>{t("settings.help", "Help & Support")}</h2>
        <div style={{ display: "grid", gap: 6 }}>
          <a href="mailto:support@pocketcare.app" className="chip" style={{ justifySelf: "start" }}>Contact support</a>
          <button className="chip" style={{ justifySelf: "start" }} onClick={() => void replayIntro()}>Replay the intro</button>
          <span className="muted" style={{ fontSize: 12 }}>PocketCare · your data is stored on your device and synced securely. Guest data is removed after 3 days if you don’t register.</span>
        </div>
      </section>

      {/* Sign out and Delete */}
      <section style={{ display: "flex", justifyContent: "center", gap: 16, paddingTop: 4, paddingBottom: 24, flexWrap: "wrap" }}>
        <button className="btn ghost" onClick={() => setConfirmSignout(true)}>Sign out</button>
        <button className="btn ghost" style={{ color: "var(--negative)", borderColor: "var(--negative)" }} onClick={() => setConfirmDelete(true)}>Delete account</button>
      </section>

      <Modal open={confirmDelete} onClose={() => !deleting && setConfirmDelete(false)}>
        <h2 style={{ marginBottom: 8, color: "var(--negative)" }}>Delete account?</h2>
        <p className="muted" style={{ fontSize: 14, lineHeight: 1.6, marginBottom: 12 }}>
          This permanently deletes your account and <strong>all</strong> your data — accounts, transactions, budgets, goals, planned cashflow and more. Your email will be freed so you can register again from scratch. This cannot be undone.
        </p>
        {deleteErr && (
          <div style={{ padding: "9px 12px", borderRadius: 10, marginBottom: 12, fontSize: 13, background: "var(--surface-2)", border: "1px solid var(--negative)", color: "var(--negative)" }}>
            {deleteErr}
          </div>
        )}
        <div style={{ display: "flex", justifyContent: "flex-end", gap: 8, marginTop: 4 }}>
          <button className="chip" disabled={deleting} onClick={() => { setConfirmDelete(false); setDeleteErr(null); }}>Cancel</button>
          <button className="btn" style={{ background: "var(--negative)" }} disabled={deleting} onClick={() => deleteAccount()}>
            {deleting ? "Deleting…" : "Delete everything"}
          </button>
        </div>
      </Modal>
    </div>
  );
}
