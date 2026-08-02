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
import { MenuIcon, PlusIcon, DownloadIcon, BellIcon, ReceiptIcon } from "../src/ui/icons";
import { MaterialIcon, type MaterialIconName } from "../src/ui/MaterialIcon";
import { AddSpeedDial } from "../src/ui/AddSpeedDial";
import { GlobalLoader } from "../src/ui/GlobalLoader";
import { TrialNotice } from "../src/ui/TrialNotice";
import { runRecurring } from "../src/templates/write";
import { useInstallPrompt } from "../src/pwa";
import { InstallGuide } from "../src/ui/InstallGuide";
import { Modal } from "../src/ui/Modal";
import { BugReportModal } from "../src/ui/BugReport";
import { useUnreadCount } from "../src/notifications/hooks";
import { installDiagnostics, setDiagnosticsRoute } from "../src/diagnostics/log";
import { startErrorReporting } from "../src/diagnostics/report";
import { listFailedWrites } from "../src/sync/deadletter";

/** Persistent banner shown whenever the device is offline. */
function OfflineBanner() {
  const [offline, setOffline] = useState(false);
  useEffect(() => {
    const sync = () => setOffline(typeof navigator !== "undefined" && navigator.onLine === false);
    sync();
    window.addEventListener("online", sync);
    window.addEventListener("offline", sync);
    return () => { window.removeEventListener("online", sync); window.removeEventListener("offline", sync); };
  }, []);
  if (!offline) return null;
  return (
    <div role="status" style={{
      position: "sticky", top: 0, zIndex: 60, display: "flex", alignItems: "center", justifyContent: "center",
      gap: 8, padding: "7px 14px", fontSize: 12.5, fontWeight: 600, textAlign: "center",
      background: "var(--warning, #c08a3e)", color: "#fff",
    }}>
      <span style={{ width: 7, height: 7, borderRadius: 999, background: "#fff", opacity: 0.9 }} />
      You’re offline — changes are saved on this device and will sync when you’re back online.
    </div>
  );
}

/**
 * Banner shown when writes have been quarantined.
 *
 * Discoverability is the whole point. A recovery screen buried in Settings is
 * only found by someone who already suspects something is wrong — but the
 * failure this handles is silent by design: the queue unblocks, everything
 * else syncs, and the app looks perfectly healthy while a few of the user's
 * expenses sit in limbo. That is precisely the situation that lost data
 * before. So the app says so, unprompted, until it's dealt with.
 *
 * Polled rather than reactive: `failed_writes` is local-only, so there's no
 * sync event to hang off, and quarantining is rare enough that a 30s poll
 * costs nothing.
 */
function SyncProblemsBanner() {
  const [count, setCount] = useState(0);
  const router = useRouter();

  useEffect(() => {
    let alive = true;
    const check = async () => {
      const items = await listFailedWrites(50);
      if (alive) setCount(items.length);
    };
    void check();
    const t = setInterval(() => void check(), 30_000);
    return () => { alive = false; clearInterval(t); };
  }, []);

  if (count === 0) return null;
  return (
    <button
      type="button"
      onClick={() => router.push("/settings#problems")}
      style={{
        position: "sticky", top: 0, zIndex: 61, width: "100%", border: "none", cursor: "pointer",
        display: "flex", alignItems: "center", justifyContent: "center", gap: 8,
        padding: "7px 14px", fontSize: 12.5, fontWeight: 600, textAlign: "center",
        background: "var(--negative)", color: "#fff",
      }}
    >
      {count} change{count === 1 ? "" : "s"} couldn’t be saved — tap to review
    </button>
  );
}

/** Bell + unread badge (top-bar icon button), links to the notification inbox. */
function NotifBell({ onNavigate = () => {} }: { onNavigate?: () => void }) {
  const unread = useUnreadCount();
  return (
    <Link href="/notifications" aria-label={`Notifications${unread ? ` (${unread} unread)` : ""}`} onClick={onNavigate}
      style={{ position: "relative", width: 40, height: 40, display: "grid", placeItems: "center", color: "inherit" }}>
      <BellIcon size={20} />
      {unread > 0 && (
        <span style={{
          position: "absolute", top: 5, right: 5, minWidth: 15, height: 15, padding: "0 3px",
          borderRadius: 999, background: "var(--negative)", color: "#fff", fontSize: 9.5, fontWeight: 700,
          display: "grid", placeItems: "center", lineHeight: 1,
        }}>{unread > 9 ? "9+" : unread}</span>
      )}
    </Link>
  );
}

/** Full-width sidebar row (desktop nav): bell + label + unread pill. */
function NotifNavItem({ active, onNavigate }: { active: boolean; onNavigate: () => void }) {
  const unread = useUnreadCount();
  const { t } = useTranslation();
  return (
    <Link href="/notifications" onClick={onNavigate} style={navItem(active)}>
      <MaterialIcon name="notifications" size={20} />
      {t("nav.notifications", "Notifications")}
      {unread > 0 && (
        <span style={{
          marginLeft: "auto", minWidth: 18, height: 18, padding: "0 5px", borderRadius: 999,
          background: "var(--negative)", color: "#fff", fontSize: 10.5, fontWeight: 700,
          display: "grid", placeItems: "center", lineHeight: 1,
        }}>{unread > 9 ? "9+" : unread}</span>
      )}
    </Link>
  );
}

const APP_VERSION = "0.1.0";

const NAV_GROUPS: { title: string; items: { href: string; tkey: string; label: string; icon: MaterialIconName; beta?: boolean }[] }[] = [
  { title: "", items: [
    { href: "/", tkey: "nav.home", label: "Dashboard", icon: "space_dashboard" },
    { href: "/assistant", tkey: "nav.assistant", label: "Ask Sanvya", icon: "auto_awesome" },
  ] },
  { title: "Money", items: [
    { href: "/accounts", tkey: "nav.accounts", label: "Accounts", icon: "account_balance" },
    { href: "/transactions", tkey: "nav.transactions", label: "Transactions", icon: "swap_horiz" },
    { href: "/templates", tkey: "nav.templates", label: "Templates", icon: "bookmarks" },
    { href: "/cards", tkey: "nav.cards", label: "Cards", icon: "credit_card" },
    // Splits and Groups & trips were one screen's worth of information split
    // across two; /groups now redirects to /friends, so the nav has one entry.
    { href: "/friends", tkey: "nav.friends", label: "Splits & groups", icon: "groups" },
    { href: "/search", tkey: "nav.search", label: "Search", icon: "search" },
  ] },
  { title: "Planning", items: [
    { href: "/budgets", tkey: "nav.budgets", label: "Budgets", icon: "donut_small" },
    { href: "/goals", tkey: "nav.goals", label: "Goals", icon: "flag" },
    { href: "/cashflow", tkey: "nav.cashflow", label: "Planned Cashflow", icon: "waterfall_chart", beta: true },
    { href: "/recurring", tkey: "nav.recurring", label: "Recurring", icon: "autorenew" },
    { href: "/loans", tkey: "nav.loans", label: "Loans", icon: "request_quote" },
  ] },
  { title: "Growth", items: [
    { href: "/investments", tkey: "nav.investments", label: "Investments", icon: "trending_up" },
    { href: "/insights", tkey: "nav.insights", label: "Insights", icon: "insights" },
    { href: "/statements", tkey: "nav.statements", label: "Statements", icon: "description" },
  ] },
  { title: "", items: [
    { href: "/settings", tkey: "nav.settings", label: "Settings", icon: "settings" },
    { href: "/help", tkey: "nav.help", label: "Help & FAQ", icon: "help" },
  ] },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { standalone } = useInstallPrompt();
  const [showInstall, setShowInstall] = useState(false);
  const [showBug, setShowBug] = useState(false);
  const [menuOpen, setMenuOpen] = useState(false);
  const session = useSession();
  const authStatus = useAuthStatus();
  const sync = useSyncStatus();
  const { t } = useTranslation();

  // Full-screen routes with no app chrome.
  const bare = pathname === "/onboarding" || pathname === "/login" || pathname === "/join" || pathname.startsWith("/admin");

  useEffect(() => {
    applySavedTheme();
    // Start capturing errors immediately — the failures worth diagnosing often
    // happen during boot, before anyone thinks to open Diagnostics.
    installDiagnostics();
    // Errors report themselves to the admin panel — most users never file a
    // bug report, they just stop using the app.
    startErrorReporting();
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
  }, []);

  // Tag each captured entry with the page it happened on.
  useEffect(() => { setDiagnosticsRoute(pathname); }, [pathname]);

  // Gate on the session, not a "seen" flag: an unauthenticated visitor must
  // pick a path on onboarding (create account / sign in / try as guest).
  useEffect(() => {
    if (authStatus === "none" && !bare) router.replace("/onboarding");
  }, [authStatus, bare, router]);

  // Resume a pending group invite: if someone opened an invite link while logged
  // out, we stashed the token. The moment they have a session (email, Google, or
  // guest), send them back to /join to finish joining and land on the group.
  useEffect(() => {
    if (authStatus !== "user" && authStatus !== "guest") return;
    if (pathname === "/join") return;
    let token: string | null = null;
    try { token = localStorage.getItem("pendingInvite"); } catch { /* ignore */ }
    if (token) router.replace(`/join?token=${encodeURIComponent(token)}`);
  }, [authStatus, pathname, router]);

  // Materialise any due auto-post recurring transactions, once, on app open.
  const recurringRan = useRef(false);
  useEffect(() => {
    if (recurringRan.current || (authStatus !== "user" && authStatus !== "guest")) return;
    recurringRan.current = true;
    const t = setTimeout(() => {
      void runRecurring().catch(() => {});
      // Auto-marked EMIs post their ledger entry too, so an EMI charged to a
      // credit card actually shows against that card. Runs after sync has
      // settled: the dedupe check reads the synced ledger, and firing it too
      // early could miss a row another device already posted.
      void import("../src/loans/autoPost").then((m) => m.runLoanAutoPost()).catch(() => {});
    }, 2500);
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
  if (bare) return <div style={{ minHeight: "100vh" }}><OfflineBanner />{children}</div>;

  // While resolving auth / redirecting to onboarding, show a spinner (no app flash).
  if (authStatus === "loading" || authStatus === "none") {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  return (
    <>
      {/* App-wide banners must NOT be children of `.shell`.
          `.shell` is `display: grid; grid-template-columns: 248px 1fr`, and both
          banners are `position: sticky` — which, unlike `fixed`, still
          participates in grid flow. So a rendered banner claimed the first grid
          cell and pushed the sidebar into column 2 and `<main>` off-screen
          entirely. It only reproduced when a banner was actually visible (a
          sync problem, or simply going offline), which is why it survived this
          long. Rendering them above the grid also reads better: a global
          message should span the full width, not sit beside the nav. */}
      <OfflineBanner />
      <SyncProblemsBanner />
      <div className="shell">
        {/* Safe inside the grid: `position: fixed` children are taken out of
            flow and never form a grid area. */}
        <GlobalLoader />
      {/* Mobile top bar */}
      <div className="topbar">
        <button className="hamburger" aria-label="Menu" onClick={() => setMenuOpen(true)}><MenuIcon /></button>
        <Logo size={26} />
        <NotifBell />
      </div>

      {menuOpen && <div className="scrim" onClick={() => setMenuOpen(false)} />}

      <aside className={`sidebar${menuOpen ? " open" : ""}`}>
        <div style={{ padding: "4px 12px 20px" }}>
          <Logo size={30} />
        </div>
        <nav style={{ display: "grid", gap: 4 }}>
          <NotifNavItem active={isActive("/notifications")} onNavigate={() => setMenuOpen(false)} />
          {NAV_GROUPS.map((g, gi) => (
            <div key={gi} style={{ display: "grid", gap: 2, marginTop: gi ? 10 : 0 }}>
              {g.title && (
                <div style={{ padding: "2px 12px", fontSize: 10.5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.07em", color: "var(--text-2)", opacity: 0.65 }}>{g.title}</div>
              )}
              {g.items.map((n) => (
                <Link key={n.href} href={n.href} style={navItem(isActive(n.href))} onClick={() => setMenuOpen(false)}>
                  <MaterialIcon name={n.icon} size={20} />
                  {t(n.tkey, n.label)}
                  {n.beta && <span className="beta-badge sm" style={{ marginLeft: "auto" }}>BETA</span>}
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
          <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => { setShowBug(true); setMenuOpen(false); }}>
            <MaterialIcon name="chat_bubble" size={16} /> Feedback
          </button>
          {!standalone && (
            <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => setShowInstall(true)}>
              <DownloadIcon size={16} /> Install app
            </button>
          )}
          <div style={{ textAlign: "center", fontSize: 11, color: "var(--text-2)", opacity: 0.7, paddingTop: 2 }}>
            Sanvya v{APP_VERSION}
          </div>
        </div>
      </aside>

      <Modal open={showInstall} onClose={() => setShowInstall(false)}>
        <h2 style={{ margin: "0 0 12px" }}>Install Sanvya</h2>
        <InstallGuide />
      </Modal>

      <BugReportModal open={showBug} onClose={() => setShowBug(false)} />

      <main className="shell-main" style={{ padding: "32px 40px", maxWidth: 1180, overflowX: "hidden" }}>
        {showBack && (
          <button
            onClick={() => router.back()}
            className="chip"
            style={{ display: "inline-flex", alignItems: "center", gap: 6, marginBottom: 16 }}
          >
            <MaterialIcon name="arrow_back" size={16} /> Back
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
                  <a href="mailto:support@sanvya.app?subject=Sync%20Issue" className="btn ghost" style={{ padding: "4px 10px", fontSize: 12, minHeight: 0, height: 28 }}>
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

      {/* Quick add — only on the dashboard (other pages have their own
          contextual add buttons). A speed dial: tapping the pill reveals
          "Add transaction" and "Scan bill / receipt" stacked above it. */}
      {pathname === "/" && (
        <AddSpeedDial
          label={t("fab.add", "Add")}
          closeLabel={t("fab.close", "Close")}
          actions={[
            {
              key: "transaction",
              label: t("fab.addTransaction", "Add transaction"),
              href: "/transactions/new",
              icon: <PlusIcon size={18} />,
            },
            {
              key: "receipt",
              label: t("fab.scanReceipt", "Scan bill / receipt"),
              href: "/receipts/new",
              icon: <ReceiptIcon size={18} />,
            },
          ]}
        />
      )}
      </div>
    </>
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
