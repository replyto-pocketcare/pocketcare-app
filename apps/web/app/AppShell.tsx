"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { applySavedTheme } from "../src/theme";
import { useSession, useAuthStatus } from "../src/account";
import { useSyncStatus, syncMessage } from "../src/sync";
import { Spinner } from "../src/ui/Spinner";
import { Logo } from "../src/ui/Logo";
import { MenuIcon, PlusIcon, DownloadIcon } from "../src/ui/icons";
import { GlobalLoader } from "../src/ui/GlobalLoader";
import { TrialNotice } from "../src/ui/TrialNotice";
import { runRecurring } from "../src/templates/write";
import { useInstallPrompt } from "../src/pwa";
import { InstallGuide } from "../src/ui/InstallGuide";
import { Modal } from "../src/ui/Modal";

const APP_VERSION = "0.1.0";

const NAV_GROUPS: { title: string; items: { href: string; tkey: string; label: string; icon: string }[] }[] = [
  { title: "", items: [
    { href: "/", tkey: "nav.home", label: "Dashboard", icon: "◧" },
    { href: "/assistant", tkey: "nav.assistant", label: "Ask PocketCare", icon: "✦" },
  ] },
  { title: "Money", items: [
    { href: "/accounts", tkey: "nav.accounts", label: "Accounts", icon: "▤" },
    { href: "/transactions", tkey: "nav.transactions", label: "Transactions", icon: "⇅" },
    { href: "/templates", tkey: "nav.templates", label: "Templates", icon: "▧" },
    { href: "/cards", tkey: "nav.cards", label: "Cards", icon: "▭" },
    { href: "/friends", tkey: "nav.friends", label: "Friends", icon: "◑" },
    { href: "/groups", tkey: "nav.groups", label: "Groups & trips", icon: "◇" },
    { href: "/search", tkey: "nav.search", label: "Search", icon: "⌕" },
  ] },
  { title: "Planning", items: [
    { href: "/budgets", tkey: "nav.budgets", label: "Budgets", icon: "◔" },
    { href: "/goals", tkey: "nav.goals", label: "Goals", icon: "◎" },
    { href: "/subscriptions", tkey: "nav.subscriptions", label: "Subscriptions", icon: "↻" },
    { href: "/loans", tkey: "nav.loans", label: "Loans & Recurring", icon: "≈" },
  ] },
  { title: "Growth", items: [
    { href: "/investments", tkey: "nav.investments", label: "Investments", icon: "▲" },
    { href: "/insights", tkey: "nav.insights", label: "Insights", icon: "◱" },
    { href: "/statements", tkey: "nav.statements", label: "Statements", icon: "▦" },
  ] },
  { title: "", items: [
    { href: "/settings", tkey: "nav.settings", label: "Settings", icon: "◇" },
    { href: "/help", tkey: "nav.help", label: "Help & FAQ", icon: "?" },
  ] },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { standalone } = useInstallPrompt();
  const [showInstall, setShowInstall] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const session = useSession();
  const authStatus = useAuthStatus();
  const sync = useSyncStatus();
  const { t } = useTranslation();

  // Full-screen routes with no app chrome.
  const bare = pathname === "/onboarding" || pathname === "/login" || pathname === "/join";

  useEffect(() => {
    applySavedTheme();
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
  }, []);

  // Gate on the session, not a "seen" flag: an unauthenticated visitor must
  // pick a path on onboarding (create account / sign in / try as guest).
  useEffect(() => {
    if (authStatus === "none" && !bare) router.replace("/onboarding");
  }, [authStatus, bare, router]);

  // Materialise any due auto-post recurring transactions, once, on app open.
  const recurringRan = useRef(false);
  useEffect(() => {
    if (recurringRan.current || (authStatus !== "user" && authStatus !== "guest")) return;
    recurringRan.current = true;
    const t = setTimeout(() => { void runRecurring().catch(() => {}); }, 2500); // let sync settle first
    return () => clearTimeout(t);
  }, [authStatus]);

  // Per-route scroll restoration: save window scroll for each path and restore
  // it when the user returns (retrying briefly while async data grows the page).
  useEffect(() => {
    if (typeof window === "undefined") return;
    const key = `pc_scroll:${pathname}`;
    const saved = Number(sessionStorage.getItem(key) || "0");
    if (saved > 0) {
      let attempts = 0;
      const tryRestore = () => {
        window.scrollTo(0, saved);
        if (++attempts < 20 && Math.abs(window.scrollY - saved) > 2) setTimeout(tryRestore, 60);
      };
      requestAnimationFrame(tryRestore);
    }
    let t: number | undefined;
    const onScroll = () => {
      if (t) return;
      t = window.setTimeout(() => { sessionStorage.setItem(key, String(window.scrollY)); t = undefined; }, 150);
    };
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", onScroll);
      if (t) window.clearTimeout(t);
      sessionStorage.setItem(key, String(window.scrollY)); // capture final position on leave
    };
  }, [pathname]);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  // Show a Back affordance on sub-pages (anything nested below a top-level section).
  const showBack = pathname.split("/").filter(Boolean).length >= 2;

  // Onboarding / login render full-screen without the sidebar.
  if (bare) return <div style={{ minHeight: "100vh" }}>{children}</div>;

  // While resolving auth / redirecting to onboarding, show a spinner (no app flash).
  if (authStatus === "loading" || authStatus === "none") {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  return (
    <div className="shell">
      <GlobalLoader />
      {/* Mobile top bar */}
      <div className="topbar">
        <button className="hamburger" aria-label="Menu" onClick={() => setMenuOpen(true)}><MenuIcon /></button>
        <Logo size={26} />
        <span style={{ width: 40 }} />
      </div>

      {menuOpen && <div className="scrim" onClick={() => setMenuOpen(false)} />}

      <aside className={`sidebar${menuOpen ? " open" : ""}`}>
        <div style={{ padding: "4px 12px 20px" }}>
          <Logo size={30} />
        </div>
        <nav style={{ display: "grid", gap: 4 }}>
          {NAV_GROUPS.map((g, gi) => (
            <div key={gi} style={{ display: "grid", gap: 2, marginTop: gi ? 10 : 0 }}>
              {g.title && (
                <div style={{ padding: "2px 12px", fontSize: 10.5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.07em", color: "var(--text-2)", opacity: 0.65 }}>{g.title}</div>
              )}
              {g.items.map((n) => (
                <Link key={n.href} href={n.href} style={navItem(isActive(n.href))} onClick={() => setMenuOpen(false)}>
                  <span style={{ width: 20, textAlign: "center", opacity: 0.75 }}>{n.icon}</span>
                  {t(n.tkey, n.label)}
                </Link>
              ))}
            </div>
          ))}
        </nav>
        <div style={{ marginTop: "auto", display: "grid", gap: 8, paddingTop: 12 }}>
          {session?.isGuest && (
            <Link href="/login" style={{ padding: "10px 12px", borderRadius: 10, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", fontSize: 12.5 }}>
              <strong>Guest</strong>{session.daysLeft !== null ? ` · ${session.daysLeft}d until data is deleted` : ""}
              <div style={{ color: "var(--accent)", marginTop: 2 }}>Create account →</div>
            </Link>
          )}
          {!standalone && (
            <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => setShowInstall(true)}>
              <DownloadIcon size={16} /> Install app
            </button>
          )}
          <div style={{ textAlign: "center", fontSize: 11, color: "var(--text-2)", opacity: 0.7, paddingTop: 2 }}>
            PocketCare v{APP_VERSION}
          </div>
        </div>
      </aside>

      <Modal open={showInstall} onClose={() => setShowInstall(false)}>
        <h2 style={{ margin: "0 0 12px" }}>Install PocketCare</h2>
        <InstallGuide />
      </Modal>

      <main className="shell-main" style={{ padding: "32px 40px", maxWidth: 1180, overflowX: "hidden" }}>
        {showBack && (
          <button
            onClick={() => router.back()}
            className="chip"
            style={{ display: "inline-flex", alignItems: "center", gap: 6, marginBottom: 16 }}
          >
            <span style={{ fontSize: 16, lineHeight: 1 }}>‹</span> Back
          </button>
        )}
        {(() => {
          const m = syncMessage(sync);
          if (!m) return null;
          const warn = m.tone === "warn";
          return (
            <div style={{ padding: "9px 14px", marginBottom: 16, borderRadius: 10, fontSize: 13, display: "flex", flexWrap: "wrap", gap: 12, alignItems: "center",
              border: `1px solid ${warn ? "var(--warning)" : "var(--border)"}`,
              background: warn ? "var(--accent-ghost)" : "var(--surface-2)",
              color: warn ? "var(--text)" : "var(--text-2)" }}>
              <div style={{ display: "flex", gap: 8, alignItems: "center", flex: "1 1 auto" }}>
                <span style={{ width: 8, height: 8, borderRadius: 999, flexShrink: 0, background: warn ? "var(--warning)" : "var(--text-2)" }} />
                <span>{m.text}</span>
              </div>
              {m.action === "force-sync" && (
                <div style={{ display: "flex", gap: 8, flexWrap: "wrap" }}>
                  <button className="btn" style={{ padding: "4px 10px", fontSize: 12, minHeight: 0, height: 28 }} onClick={async () => {
                    const { forceSync } = await import("../src/powersync");
                    await forceSync();
                  }}>
                    Force Sync
                  </button>
                  <a href="mailto:support@pocketcare.app?subject=Sync%20Issue" className="btn ghost" style={{ padding: "4px 10px", fontSize: 12, minHeight: 0, height: 28 }}>
                    Report Issue
                  </a>
                </div>
              )}
            </div>
          );
        })()}
        <TrialNotice />
        {children}
      </main>

      {/* Quick add-transaction — only on the dashboard (other pages have their
          own contextual add buttons). Pill-shaped with a label for clarity. */}
      {pathname === "/" && (
        <Link href="/transactions/new" aria-label="Add transaction"
          style={{ position: "fixed", right: 20, bottom: 20, zIndex: 40, borderRadius: 999,
            padding: "14px 20px", gap: 8, background: "var(--accent)", color: "#fff", fontWeight: 600,
            display: "inline-flex", alignItems: "center",
            boxShadow: "var(--shadow-lg)", transition: "transform 0.15s" }}
          onMouseDown={(e) => (e.currentTarget.style.transform = "scale(0.96)")}
          onMouseUp={(e) => (e.currentTarget.style.transform = "scale(1)")}>
          <PlusIcon size={20} /> Add transaction
        </Link>
      )}
    </div>
  );
}

const navItem = (active: boolean): React.CSSProperties => ({
  display: "flex",
  alignItems: "center",
  gap: 10,
  padding: "10px 12px",
  borderRadius: 10,
  fontSize: 14.5,
  fontWeight: active ? 650 : 500,
  color: active ? "var(--accent)" : "var(--text)",
  background: active ? "var(--accent-ghost)" : "transparent",
  transition: "background 0.15s",
});
