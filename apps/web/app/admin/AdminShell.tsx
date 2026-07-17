"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getSupabase } from "../../src/powersync";
import { Spinner } from "../../src/ui/Spinner";
import { Logo } from "../../src/ui/Logo";

type Denied =
  | { kind: "no-session" }
  | { kind: "not-admin"; userId: string }
  | { kind: "query-error"; message: string; details: string };

export function AdminShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);
  const [denied, setDenied] = useState<Denied | null>(null);

  useEffect(() => {
    let active = true;
    const checkAdmin = async () => {
      const { data: { session } } = await getSupabase().auth.getSession();
      if (!session) {
        if (active) { setDenied({ kind: "no-session" }); setIsAdmin(false); }
        return;
      }

      // Check if the signed-in user is an admin. The admins table lives in the
      // pocketcare_admin schema (not exposed to PostgREST on this project), so
      // we read it through the security_invoker view pocketcare.admins, which
      // IS exposed. RLS on the base table still restricts rows to the caller.
      // NOTE: use limit(1)+array rather than .maybeSingle() — the object+json
      // Accept header used by single/maybeSingle returns HTTP 406 on zero rows
      // in some PostgREST versions, which is exactly the non-admin case.
      const { data: adminRows, error } = await getSupabase()
        .schema("pocketcare")
        .from("admins")
        .select("id")
        .eq("user_id", session.user.id)
        .limit(1);

      if (!active) return;
      if (error) {
        setDenied({ kind: "query-error", message: error.message, details: JSON.stringify(error, null, 2) });
        setIsAdmin(false);
      } else if (adminRows && adminRows.length > 0) {
        setIsAdmin(true);
      } else {
        setDenied({ kind: "not-admin", userId: session.user.id });
        setIsAdmin(false);
      }
    };
    void checkAdmin();
    return () => { active = false; };
  }, [router]);

  if (isAdmin === null) {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  if (!isAdmin) {
    return <AdminDenied denied={denied} onSignIn={() => router.replace("/login")} onHome={() => router.replace("/")} />;
  }

  return (
    <div className="admin-shell">
      <aside className="admin-aside">
        <div className="admin-brand">
          <Logo size={24} />
          <strong style={{ fontSize: 18 }}>Admin Console</strong>
        </div>
        <nav className="admin-nav">
          <Link href="/admin">Dashboard</Link>
          <Link href="/admin/users">Users &amp; Support</Link>
          <Link href="/admin/feedback">Feedback</Link>
          <Link href="/admin/notifications">Notifications</Link>
          <Link href="/admin/jobs">Jobs</Link>
          <Link href="/" className="admin-nav-back">← Back to App</Link>
        </nav>
      </aside>
      <main className="admin-main">
        {children}
      </main>
    </div>
  );
}

function AdminDenied({ denied, onSignIn, onHome }: { denied: Denied | null; onSignIn: () => void; onHome: () => void }) {
  const box = { minHeight: "100vh", display: "grid", placeItems: "center", background: "#111", color: "#eee", padding: 24 } as const;
  const card = { maxWidth: 560, width: "100%", background: "#1a1a1a", border: "1px solid #333", borderRadius: 14, padding: 28, display: "grid", gap: 14 } as const;

  let title = "Access denied";
  let body: ReactNode = null;

  if (denied?.kind === "no-session") {
    title = "Not signed in";
    body = <p style={{ color: "#bbb", lineHeight: 1.6 }}>You need to sign in before opening the admin console.</p>;
  } else if (denied?.kind === "not-admin") {
    title = "You’re not an admin";
    body = (
      <>
        <p style={{ color: "#bbb", lineHeight: 1.6 }}>
          Your account is signed in, but there’s no matching row in <code>pocketcare_admin.admins</code>.
          If you just added yourself, confirm the <code>user_id</code> matches exactly.
        </p>
        <pre style={{ background: "#000", padding: 12, borderRadius: 8, fontSize: 12, overflowX: "auto", color: "#8fd" }}>
{`insert into pocketcare_admin.admins (user_id, email)
values ('${denied.userId}', '<your-email>');`}
        </pre>
      </>
    );
  } else if (denied?.kind === "query-error") {
    title = "Admin check failed";
    body = (
      <>
        <p style={{ color: "#bbb", lineHeight: 1.6 }}>
          The lookup against <code>pocketcare_admin.admins</code> returned an error. Common causes: the
          <code> pocketcare_admin</code> schema isn’t in the Data API “Exposed schemas”, or the
          <code> authenticated</code> role lacks <code>SELECT</code>/RLS access.
        </p>
        <div style={{ color: "#f88", fontWeight: 600 }}>{denied.message}</div>
        <pre style={{ background: "#000", padding: 12, borderRadius: 8, fontSize: 11, overflowX: "auto", color: "#f99" }}>{denied.details}</pre>
      </>
    );
  }

  return (
    <div style={box}>
      <div style={card}>
        <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
          <Logo size={22} />
          <strong style={{ fontSize: 18 }}>{title}</strong>
        </div>
        {body}
        <div style={{ display: "flex", gap: 10, marginTop: 6 }}>
          {denied?.kind === "no-session"
            ? <button onClick={onSignIn} style={{ padding: "10px 16px", borderRadius: 8, background: "#2b6", color: "#000", border: "none", fontWeight: 600, cursor: "pointer" }}>Sign in</button>
            : <button onClick={onHome} style={{ padding: "10px 16px", borderRadius: 8, background: "#333", color: "#eee", border: "none", cursor: "pointer" }}>← Back to app</button>}
        </div>
      </div>
    </div>
  );
}
