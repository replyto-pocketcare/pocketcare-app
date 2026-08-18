"use client";

import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTranslation } from "react-i18next";
import { applySavedTheme, setTheme, useTheme } from "../src/theme";
import { useSession, useAuthStatus } from "../src/account";
import { useSyncStatus, syncMessage } from "../src/sync";
import { Spinner } from "../src/ui/Spinner";
import { Logo } from "../src/ui/Logo";
import { PlusIcon, DownloadIcon, BellIcon, ReceiptIcon, CloseIcon } from "../src/ui/icons";
import { MaterialIcon, type MaterialIconName } from "../src/ui/MaterialIcon";
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
import { AddActionProvider, type AddAction } from "../src/ui/AddAction";
import { BottomNavCustomizer } from "../src/ui/BottomNavCustomizer";
import { useBottomNavIds, navItemsFor } from "../src/navPrefs";

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

/** Notification bell, with unread badge. Lives in the in-flow utility row (or,
 *  on the dashboard, its own row under the header controls) — never fixed, so
 *  it can never overlap a page's own content, at any width. */
export function NotifBell() {
  const unread = useUnreadCount();
  return (
    <Link href="/notifications" aria-label={`Notifications${unread ? ` (${unread} unread)` : ""}`} className="press util-btn" style={{ position: "relative" }}>
      <BellIcon size={19} />
      {unread > 0 && (
        <span style={{
          position: "absolute", top: 3, right: 3, minWidth: 15, height: 15, padding: "0 3px",
          borderRadius: 999, background: "var(--negative)", color: "#fff", fontSize: 9.5, fontWeight: 700,
          display: "grid", placeItems: "center", lineHeight: 1,
        }}>{unread > 9 ? "9+" : unread}</span>
      )}
    </Link>
  );
}

/** Desktop top bar: global search on the left, utilities on the right.
 *  CSS hides this entirely below the desktop breakpoint, where the same
 *  destinations are reached from the bottom bar and the in-page utility row. */
function TopBar() {
  const { t } = useTranslation();
  const theme = useTheme();
  const unread = useUnreadCount();
  const session = useSession();
  const dark = theme === "dark";
  const initial = (session?.username || session?.email || "?").trim().charAt(0).toUpperCase();

  return (
    <div className="top-bar">
      <Link href="/search" className="top-search">
        <MaterialIcon name="search" size={17} />
        <span>{t("nav.searchAnything", "Search anything…")}</span>
        <kbd>⌘K</kbd>
      </Link>
      <div className="top-actions">
        <button
          type="button"
          className="top-icon press"
          onClick={() => setTheme(dark ? "light" : "dark")}
          aria-label={dark ? t("theme.light", "Switch to light theme") : t("theme.dark", "Switch to dark theme")}
        >
          {dark ? (
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z" /></svg>
          ) : (
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><circle cx="12" cy="12" r="4.2" /><path d="M12 2v2.2M12 19.8V22M4.2 4.2l1.6 1.6M18.2 18.2l1.6 1.6M2 12h2.2M19.8 12H22M4.2 19.8l1.6-1.6M18.2 5.8l1.6-1.6" /></svg>
          )}
        </button>
        <Link href="/notifications" className="top-icon press" aria-label={`Notifications${unread ? ` (${unread} unread)` : ""}`}>
          <BellIcon size={17} />
          {unread > 0 && <span className="top-dot" />}
        </Link>
        <Link href="/settings" className="top-avatar" aria-label={t("nav.settings", "Settings")}>{initial}</Link>
      </div>
    </div>
  );
}

/** Row inside the "More" sheet: icon + label + optional unread pill. */
function MoreNavItem({ href, icon, label, active, badge, onNavigate }: {
  href: string; icon: MaterialIconName; label: string; active: boolean; badge?: number; onNavigate: () => void;
}) {
  return (
    <Link href={href} onClick={onNavigate} style={navItem(active)}>
      <MaterialIcon name={icon} size={20} />
      {label}
      {!!badge && (
        <span style={{
          marginLeft: "auto", minWidth: 18, height: 18, padding: "0 5px", borderRadius: 999,
          background: "var(--negative)", color: "#fff", fontSize: 10.5, fontWeight: 700,
          display: "grid", placeItems: "center", lineHeight: 1,
        }}>{badge > 9 ? "9+" : badge}</span>
      )}
    </Link>
  );
}

const APP_VERSION = "0.1.0";

const NAV_GROUPS: { title: string; items: { href: string; tkey: string; label: string; icon: MaterialIconName; beta?: boolean }[] }[] = [
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
    { href: "/reflect", tkey: "nav.reflect", label: "Reflect", icon: "volunteer_activism" },
    { href: "/insights", tkey: "nav.insights", label: "Insights", icon: "insights" },
    { href: "/statements", tkey: "nav.statements", label: "Statements", icon: "description" },
  ] },
  { title: "", items: [
    { href: "/assistant", tkey: "nav.assistant", label: "Ask Sanvya", icon: "auto_awesome" },
    { href: "/settings", tkey: "nav.settings", label: "Settings", icon: "settings" },
    { href: "/help", tkey: "nav.help", label: "Help & FAQ", icon: "help" },
  ] },
];

// The default "+" action for pages that haven't registered anything more
// specific via useRegisterAddAction — a transaction (or a scanned receipt,
// which becomes one) is the one thing that's always relevant on a money app.
const defaultAddAction = (t: (k: string, d: string) => string): AddAction => ({
  type: "menu",
  label: t("fab.add", "Add"),
  items: [
    { key: "transaction", label: t("fab.addTransaction", "Add transaction"), href: "/transactions/new", icon: <PlusIcon size={17} /> },
    { key: "receipt", label: t("fab.scanReceipt", "Scan bill / receipt"), href: "/receipts/new", icon: <ReceiptIcon size={17} /> },
  ],
});

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { standalone } = useInstallPrompt();
  const [showInstall, setShowInstall] = useState(false);
  const [showBug, setShowBug] = useState(false);
  const [moreOpen, setMoreOpen] = useState(false);
  const [customizeOpen, setCustomizeOpen] = useState(false);
  const [addOpen, setAddOpen] = useState(false);
  const [pageAction, setPageAction] = useState<AddAction | null>(null);
  const session = useSession();
  const authStatus = useAuthStatus();
  const sync = useSyncStatus();
  const unread = useUnreadCount();
  const { t } = useTranslation();
  const navIds = useBottomNavIds();
  const navItems = navItemsFor(navIds);

  const setPageActionStable = useCallback((a: AddAction | null) => setPageAction(a), []);

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

  // Close the "More" sheet / speed-dial automatically on navigation.
  useEffect(() => { setMoreOpen(false); setAddOpen(false); }, [pathname]);

  // ⌘K / Ctrl-K jumps to search. The desktop top bar advertises this shortcut,
  // so it has to actually work — bound app-wide rather than to that bar, since
  // a keyboard shortcut the user has learned should not depend on which
  // breakpoint they happen to be at. Ignored while typing in a field.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "k" && e.key !== "K") return;
      if (!e.metaKey && !e.ctrlKey) return;
      const el = document.activeElement as HTMLElement | null;
      if (el && (el.tagName === "INPUT" || el.tagName === "TEXTAREA" || el.isContentEditable)) return;
      e.preventDefault();
      router.push("/search");
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  // Show a single Back affordance on sub-pages (anything nested below a
  // top-level section) plus a few single-segment routes that are really
  // steps in a flow, not nav destinations, and so have nowhere else to go
  // back from. Pages get at most ONE back button: this button, or (for
  // /assistant's in-page chat view) that view's own "Chats" toggle — never
  // both, and every page-local "back to X" link has been removed in favour
  // of this one, shared, in-flow utility row.
  const FLOW_ROOTS = ["/receipts/new", "/receipts/review", "/receipts/split"];
  const showBack = pathname.split("/").filter(Boolean).length >= 2 || FLOW_ROOTS.includes(pathname);
  // The dashboard has no back button and places its own greeting + bell —
  // skip the shared utility row there entirely so nothing sits above the
  // greeting, which the dashboard now renders as the very first element.
  const isDashboard = pathname === "/";

  // Onboarding / login render full-screen without the app chrome.
  if (bare) return <div style={{ minHeight: "100vh" }}><OfflineBanner />{children}</div>;

  // While resolving auth / redirecting to onboarding, show a spinner (no app flash).
  if (authStatus === "loading" || authStatus === "none") {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  const action = pageAction ?? defaultAddAction(t);
  const menuItems = action.type === "menu" ? action.items : null;

  const runAdd = () => {
    if (action.type === "link") { router.push(action.href); return; }
    if (action.type === "button") { action.onClick(); return; }
    setAddOpen((v) => !v);
  };

  return (
    <>
      {/* App-wide banners sit above everything else — a full-width strip, not
          part of the page content, so they read as system messages. */}
      <OfflineBanner />
      <SyncProblemsBanner />
      <div className="shell">
        <GlobalLoader />

        {/* Desktop-only left sidebar. Hidden below 1024px, where the floating
            bottom bar remains the only nav — so the phone experience is
            completely unchanged. Above it, the bottom bar hides and this takes
            over, which is what makes wide screens read as an analytics console
            rather than a phone layout stretched sideways. */}
        <aside className="side-nav" aria-label={t("nav.primary", "Primary")}>
          <div className="side-nav-brand">
            <Link href="/" aria-label={t("nav.home", "Home")}><Logo size={26} /></Link>
          </div>

          <button type="button" className="side-nav-add press" onClick={runAdd} aria-label={action.label} aria-expanded={action.type === "menu" ? addOpen : undefined}>
            <PlusIcon size={17} />
            <span>{action.label}</span>
          </button>

          <div className="side-nav-scroll hide-scrollbar">
            <Link href="/" className={`side-nav-item${isActive("/") ? " active" : ""}`}>
              <MaterialIcon name="space_dashboard" size={19} />
              <span>{t("nav.home", "Home")}</span>
            </Link>
            <Link href="/notifications" className={`side-nav-item${isActive("/notifications") ? " active" : ""}`}>
              <MaterialIcon name="notifications" size={19} />
              <span>{t("nav.notifications", "Notifications")}</span>
              {unread > 0 && <span className="side-nav-badge">{unread > 9 ? "9+" : unread}</span>}
            </Link>

            {NAV_GROUPS.map((g, gi) => (
              <div key={gi} className="side-nav-group">
                {g.title && <div className="side-nav-title">{g.title}</div>}
                {g.items.map((n) => (
                  <Link key={n.href} href={n.href} className={`side-nav-item${isActive(n.href) ? " active" : ""}`}>
                    <MaterialIcon name={n.icon} size={19} />
                    <span>{t(n.tkey, n.label)}</span>
                    {n.beta && <span className="beta-badge sm" style={{ marginLeft: "auto" }}>BETA</span>}
                  </Link>
                ))}
              </div>
            ))}
          </div>

          <div className="side-nav-foot">
            {session?.isGuest && (
              <Link href="/login" className="side-nav-guest">
                <strong>Guest</strong>{session.daysLeft !== null ? ` · ${session.daysLeft}d left` : ""}
                <div style={{ color: "var(--accent)", marginTop: 2 }}>Create account →</div>
              </Link>
            )}
            <button type="button" className="side-nav-item" onClick={() => setShowBug(true)}>
              <MaterialIcon name="chat_bubble" size={19} />
              <span>Feedback</span>
            </button>
            {!standalone && (
              <button type="button" className="side-nav-item" onClick={() => setShowInstall(true)}>
                <DownloadIcon size={17} />
                <span>Install app</span>
              </button>
            )}
            <div className="side-nav-ver">Sanvya v{APP_VERSION}</div>
          </div>
        </aside>

        <main className="shell-main" style={{ padding: "20px 20px 0", maxWidth: 720, overflowX: "hidden" }}>
          <TopBar />
          {/* One in-flow row for both the (optional) back button and the
              notification bell — always in normal document flow, never a
              `position: fixed` overlay, so it can't collide with a page's
              own header controls at any width. Skipped on the dashboard,
              which has no back button and places its own bell lower down. */}
          {!isDashboard && (
            <div className="util-row">
              {showBack ? (
                <button onClick={() => router.back()} className="press util-btn util-back" aria-label={t("common.back", "Back")}>
                  <MaterialIcon name="arrow_back" size={18} />
                  <span>{t("common.back", "Back")}</span>
                </button>
              ) : <span />}
              <NotifBell />
            </div>
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
          <AddActionProvider value={setPageActionStable}>{children}</AddActionProvider>
        </main>

        {/* Floating bottom nav — replaces the old sidebar/topbar entirely.
            Balanced 3-and-3 around the center "+": Home + 2 customizable
            slots on the left, 2 more + More on the right. Labels show on
            wider screens; on phones (see globals.css) it's icons only, like
            a native tab bar. Widths are flexible so it never overflows a
            narrow phone, and it centers within whatever room there is. */}
        <nav className="bottom-nav" aria-label="Primary">
          <Link href="/" className={`bottom-nav-item${isActive("/") ? " active" : ""}`} aria-label={t("nav.home", "Home")}>
            <MaterialIcon name="space_dashboard" size={22} />
            <span className="bottom-nav-label">{t("nav.home", "Home")}</span>
          </Link>

          {navItems.slice(0, 2).map((n) => (
            <Link key={n.id} href={n.href} className={`bottom-nav-item${isActive(n.href) ? " active" : ""}`} aria-label={t(n.tkey, n.label)}>
              <MaterialIcon name={n.icon} size={22} />
              <span className="bottom-nav-label">{t(n.tkey, n.label)}</span>
            </Link>
          ))}

          <button
            type="button"
            className="bottom-nav-add press"
            aria-label={action.label}
            aria-expanded={action.type === "menu" ? addOpen : undefined}
            onClick={runAdd}
          >
            <PlusIcon size={24} />
          </button>

          {navItems.slice(2, 4).map((n) => (
            <Link key={n.id} href={n.href} className={`bottom-nav-item${isActive(n.href) ? " active" : ""}`} aria-label={t(n.tkey, n.label)}>
              <MaterialIcon name={n.icon} size={22} />
              <span className="bottom-nav-label">{t(n.tkey, n.label)}</span>
            </Link>
          ))}

          <button
            type="button"
            className={`bottom-nav-item${moreOpen ? " active" : ""}`}
            aria-label={t("nav.more", "More")}
            aria-expanded={moreOpen}
            onClick={() => setMoreOpen(true)}
          >
            <MaterialIcon name="more_horiz" size={22} />
            <span className="bottom-nav-label">{t("nav.more", "More")}</span>
            {unread > 0 && (
              <span style={{
                position: "absolute", top: 2, right: "22%", minWidth: 8, height: 8, borderRadius: 999,
                background: "var(--negative)",
              }} />
            )}
          </button>
        </nav>

        {/* Contextual quick-add popover — only for pages with more than one
            reasonable "+" action (dashboard's transaction/receipt choice, or
            a page that registered its own `type: "menu"`). A single-action
            page (link or button) just fires immediately, no popover. */}
        {addOpen && menuItems && (
          <>
            <div className="scrim-clear" onClick={() => setAddOpen(false)} />
            <div className="add-popover" role="menu" aria-label={action.label}>
              {menuItems.map((item) =>
                item.href ? (
                  <Link key={item.key} href={item.href} className="add-popover-item" role="menuitem" onClick={() => setAddOpen(false)}>
                    {item.icon} {item.label}
                  </Link>
                ) : (
                  <button key={item.key} type="button" className="add-popover-item" role="menuitem" onClick={() => { item.onClick?.(); setAddOpen(false); }}>
                    {item.icon} {item.label}
                  </button>
                ),
              )}
            </div>
          </>
        )}

        {/* "More" — every other destination, grouped, opened from the bottom bar. */}
        <Modal open={moreOpen} onClose={() => setMoreOpen(false)} label={t("nav.more", "More")}>
          <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", marginBottom: 14 }}>
            <Logo size={26} />
            <div style={{ display: "flex", gap: 8 }}>
              <button className="press" aria-label={t("nav.customize", "Customize bottom bar")} title={t("nav.customize", "Customize bottom bar")} onClick={() => { setMoreOpen(false); setCustomizeOpen(true); }} style={{ width: 34, height: 34, borderRadius: 999, display: "grid", placeItems: "center", border: "1px solid var(--border)", background: "var(--surface-2)" }}>
                <MaterialIcon name="edit" size={15} />
              </button>
              <button className="press" aria-label={t("common.close", "Close")} onClick={() => setMoreOpen(false)} style={{ width: 34, height: 34, borderRadius: 999, display: "grid", placeItems: "center", border: "1px solid var(--border)", background: "var(--surface-2)" }}>
                <CloseIcon size={16} />
              </button>
            </div>
          </div>
          <div style={{ display: "grid", gap: 4, maxHeight: "60vh", overflowY: "auto" }}>
            <MoreNavItem href="/notifications" icon="notifications" label={t("nav.notifications", "Notifications")} active={isActive("/notifications")} badge={unread} onNavigate={() => setMoreOpen(false)} />
            {NAV_GROUPS.map((g, gi) => (
              <div key={gi} style={{ display: "grid", gap: 2, marginTop: 10 }}>
                {g.title && (
                  <div style={{ padding: "2px 12px", fontSize: 10.5, fontWeight: 600, textTransform: "uppercase", letterSpacing: "0.07em", color: "var(--text-2)", opacity: 0.65 }}>{g.title}</div>
                )}
                {g.items.map((n) => (
                  <Link key={n.href} href={n.href} style={navItem(isActive(n.href))} onClick={() => setMoreOpen(false)}>
                    <MaterialIcon name={n.icon} size={20} />
                    {t(n.tkey, n.label)}
                    {n.beta && <span className="beta-badge sm" style={{ marginLeft: "auto" }}>BETA</span>}
                  </Link>
                ))}
              </div>
            ))}
          </div>
          <div style={{ marginTop: 14, display: "grid", gap: 8, paddingTop: 12, borderTop: "1px solid var(--border)" }}>
            {session?.isGuest && (
              <Link href="/login" onClick={() => setMoreOpen(false)} style={{ padding: "10px 12px", borderRadius: 10, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", fontSize: 12.5 }}>
                <strong>Guest</strong>{session.daysLeft !== null ? ` · ${session.daysLeft}d until data is deleted` : ""}
                <div style={{ color: "var(--accent)", marginTop: 2 }}>Create account →</div>
              </Link>
            )}
            <button className="btn ghost" style={{ justifyContent: "center", gap: 8 }} onClick={() => { setShowBug(true); setMoreOpen(false); }}>
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
        </Modal>

        <BottomNavCustomizer open={customizeOpen} onClose={() => setCustomizeOpen(false)} current={navIds} />

        <Modal open={showInstall} onClose={() => setShowInstall(false)}>
          <h2 style={{ margin: "0 0 12px" }}>Install Sanvya</h2>
          <InstallGuide />
        </Modal>

        <BugReportModal open={showBug} onClose={() => setShowBug(false)} />
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
