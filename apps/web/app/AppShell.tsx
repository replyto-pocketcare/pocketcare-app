"use client";

import { useEffect, useState, type ReactNode } from "react";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useTheme, setTheme, applySavedTheme } from "../src/theme";
import { useSession } from "../src/account";
import { Spinner } from "../src/ui/Spinner";
import { Logo } from "../src/ui/Logo";

const NAV = [
  { href: "/", label: "Dashboard", icon: "◧" },
  { href: "/accounts", label: "Accounts", icon: "▤" },
  { href: "/transactions", label: "Transactions", icon: "⇅" },
  { href: "/cards", label: "Cards", icon: "▭" },
  { href: "/budgets", label: "Budgets", icon: "◔" },
  { href: "/insights", label: "Insights", icon: "📈" },
  { href: "/statements", label: "Statements", icon: "▦" },
  { href: "/goals", label: "Goals", icon: "◎" },
  { href: "/subscriptions", label: "Subscriptions", icon: "↻" },
  { href: "/loans", label: "Loans & Recurring", icon: "≈" },
  { href: "/investments", label: "Investments", icon: "▲" },
  { href: "/settings", label: "Settings", icon: "⚙" },
];

export function AppShell({ children }: { children: ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const [installEvt, setInstallEvt] = useState<Event | null>(null);
  const theme = useTheme();
  const session = useSession();

  // Full-screen routes with no app chrome.
  const bare = pathname === "/onboarding" || pathname === "/login";
  const [gateChecked, setGateChecked] = useState(false);
  const [redirecting, setRedirecting] = useState(false);

  useEffect(() => {
    applySavedTheme();
    if ("serviceWorker" in navigator) {
      navigator.serviceWorker.register("/sw.js").catch(() => {});
    }
    const onPrompt = (e: Event) => { e.preventDefault(); setInstallEvt(e); };
    window.addEventListener("beforeinstallprompt", onPrompt);
    return () => window.removeEventListener("beforeinstallprompt", onPrompt);
  }, []);

  // First-run: show onboarding before anything inside the app.
  useEffect(() => {
    const seen = localStorage.getItem("onboardingSeen");
    if (!seen && !bare) {
      setRedirecting(true);
      router.replace("/onboarding");
    } else {
      setRedirecting(false);
    }
    setGateChecked(true);
  }, [pathname, bare, router]);

  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname.startsWith(href));
  const toggleTheme = () => setTheme(theme === "light" ? "dark" : "light");

  // Onboarding / login render full-screen without the sidebar.
  if (bare) return <div style={{ minHeight: "100vh" }}>{children}</div>;

  // While deciding / redirecting to onboarding, show a spinner (no flash of app).
  if (!gateChecked || redirecting) {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  return (
    <div style={{ display: "grid", gridTemplateColumns: "248px 1fr", minHeight: "100vh" }}>
      <aside style={aside}>
        <div style={{ padding: "4px 12px 20px" }}>
          <Logo size={30} />
        </div>
        <nav style={{ display: "grid", gap: 2 }}>
          {NAV.map((n) => (
            <Link key={n.href} href={n.href} style={navItem(isActive(n.href))}>
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
          <button className="btn ghost" onClick={toggleTheme} style={{ justifyContent: "center" }}>
            {theme === "light" ? "☾ Dark mode" : "☀ Light mode"}
          </button>
          {installEvt && (
            <button
              className="btn"
              onClick={async () => {
                await (installEvt as unknown as { prompt: () => Promise<void> }).prompt();
                setInstallEvt(null);
              }}
            >
              ⤓ Install app
            </button>
          )}
          <Link href="/transactions/new" className="btn" style={{ justifyContent: "center" }}>
            ＋ Add transaction
          </Link>
        </div>
      </aside>

      <main style={{ padding: "32px 40px", maxWidth: 1180, width: "100%" }}>{children}</main>
    </div>
  );
}

const aside: React.CSSProperties = {
  position: "sticky",
  top: 0,
  height: "100vh",
  display: "flex",
  flexDirection: "column",
  padding: 16,
  borderRight: "1px solid var(--border)",
  background: "var(--surface)",
};

const logo: React.CSSProperties = {
  width: 32,
  height: 32,
  borderRadius: 9,
  background: "var(--accent)",
  color: "#fff",
  display: "grid",
  placeItems: "center",
  fontWeight: 800,
};

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
