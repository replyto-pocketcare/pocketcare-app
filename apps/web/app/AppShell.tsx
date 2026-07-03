"use client";

import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTheme, setTheme, applySavedTheme } from "../src/theme";
import { useSession, useAuthStatus } from "../src/account";
import { useSyncStatus } from "../src/sync";
import { Spinner } from "../src/ui/Spinner";
import { Logo } from "../src/ui/Logo";
import { MenuIcon, PlusIcon, SunIcon, MoonIcon, DownloadIcon } from "../src/ui/icons";

const NAV = [
  { href: "/", label: "Dashboard", icon: "◧" },
  { href: "/accounts", label: "Accounts", icon: "▤" },
  { href: "/transactions", label: "Transactions", icon: "⇅" },
  { href: "/search", label: "Search", icon: "⌕" },
  { href: "/cards", label: "Cards", icon: "▭" },
  { href: "/budgets", label: "Budgets", icon: "◔" },
  { href: "/insights", label: "Insights", icon: "◱" },
  { href: "/statements", label: "Statements", icon: "▦" },
  { href: "/goals", label: "Goals", icon: "◎" },
  { href: "/subscriptions", label: "Subscriptions", icon: "↻" },
  { href: "/loans", label: "Loans & Recurring", icon: "≈" },
  { href: "/investments", label: "Investments", icon: "▲" },
  { href: "/settings", label: "Settings", icon: "◇" },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [installEvt, setInstallEvt] = useState<Event | null>(null);
  const [menuOpen, setMenuOpen] = useState(false);
  const theme = useTheme();
  const session = useSession();
  const authStatus = useAuthStatus();
  const sync = useSyncStatus();

  // Full-screen routes with no app chrome.
  const bare = pathname === "/onboarding" || pathname === "/login";

  useEffect(() => {
    applySavedTheme();
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
    const onPrompt = (e: Event) => { e.preventDefault(); setInstallEvt(e); };
    window.addEventListener("beforeinstallprompt", onPrompt);
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  // Gate on the session, not a "seen" flag: an unauthenticated visitor must
  // pick a path on onboarding (create account / sign in / try as guest).
  useEffect(() => {
    if (authStatus === "none" && !bare) router.replace("/onboarding");
  }, [authStatus, bare, router]);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  const toggleTheme = () => setTheme(theme === "light" ? "dark" : "light");

  // Onboarding / login render full-screen without the sidebar.
  if (bare) return <div style={{ minHeight: "100vh" }}>{children}</div>;

  // While resolving auth / redirecting to onboarding, show a spinner (no app flash).
  if (authStatus === "loading" || authStatus === "none") {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  return (
    <div className="shell">
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
        <nav style={{ display: "grid", gap: 2 }}>
          {NAV.map((n) => (
            <Link key={n.href} href={n.href} style={navItem(isActive(n.href))} onClick={() => setMenuOpen(false)}>
              <span style={{ width: 20, textAlign: "center", opacity: 0.75 }}>{n.icon}</span>
              {n.label}
            </Link>
          ))}
        </nav>
        <div style={{ marginTop: "auto", display: "grid", gap: 8 }}>
          {session?.isGuest && (
            <Link href="/login" style={{ padding: "10px 12px", borderRadius: 10, background: "var(--accent-ghost)", border: "1px solid var(--accent-soft)", fontSize: 12.5 }}>
              <strong>Guest</strong>{session.daysLeft !== null ? ` · ${session.daysLeft}d until data is deleted` : ""}
              <div style={{ color: "var(--accent)", marginTop: 2 }}>Create account →</div>
            </Link>
          )}
          <button className="btn ghost" onClick={toggleTheme} style={{ justifyContent: "center", gap: 8 }}>
            {theme === "light" ? <MoonIcon size={16} /> : <SunIcon size={16} />}
            {theme === "light" ? "Dark mode" : "Light mode"}
          </button>
          {installEvt && (
            <button
              className="btn"
              style={{ justifyContent: "center", gap: 8 }}
              onClick={async () => {
                await (installEvt as unknown as { prompt: () => Promise<void> }).prompt();
                setInstallEvt(null);
              }}
            >
              <DownloadIcon size={16} /> Install app
            </button>
          )}
        </div>
      </aside>

      <main className="shell-main" style={{ padding: "32px 40px", maxWidth: 1180, width: "100%" }}>
        {sync.error && (
          <div className="card" style={{ padding: "10px 14px", marginBottom: 16, borderColor: "var(--warning)", background: "var(--accent-ghost)", fontSize: 13, display: "flex", gap: 8, alignItems: "flex-start" }}>
            <span aria-hidden>⚠️</span>
            <span>
              <strong>Not syncing to the cloud.</strong> Your data is safe on this device but isn’t reaching the server, so it won’t appear on other devices.
              <span className="muted"> ({sync.error})</span>
            </span>
          </div>
        )}
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
