"use client";

import { useEffect, useState, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { getSupabase } from "../../src/powersync";
import { Spinner } from "../../src/ui/Spinner";
import { Logo } from "../../src/ui/Logo";

export function AdminShell({ children }: { children: ReactNode }) {
  const router = useRouter();
  const [isAdmin, setIsAdmin] = useState<boolean | null>(null);

  useEffect(() => {
    let active = true;
    const checkAdmin = async () => {
      const { data: { session } } = await getSupabase().auth.getSession();
      if (!session) {
        if (active) router.replace("/login");
        return;
      }

      // Check if user is in pocketcare_admin.admins
      const { data, error } = await getSupabase()
        .from("admins")
        .select("id")
        .eq("user_id", session.user.id)
        .maybeSingle(); // This will query public.admins unless we specify schema, wait!
      // Supabase JS defaults to the 'public' schema.
      // We need to specify the schema.
      // We can do this in getSupabase() or pass a custom header. 
      // Actually, since we created pocketcare_admin schema and enabled RLS but allowed users to select their own row.
      
      const { data: adminData } = await getSupabase()
        .schema("pocketcare_admin")
        .from("admins")
        .select("id")
        .eq("user_id", session.user.id)
        .maybeSingle();

      if (active) {
        if (adminData) setIsAdmin(true);
        else router.replace("/"); // Not an admin, kick to dashboard
      }
    };
    void checkAdmin();
    return () => { active = false; };
  }, [router]);

  if (isAdmin === null) {
    return <div style={{ minHeight: "100vh", display: "grid", placeItems: "center" }}><Spinner size={34} /></div>;
  }

  return (
    <div className="shell admin-shell" style={{ display: "flex", minHeight: "100vh", background: "#111", color: "#eee" }}>
      <aside style={{ width: 260, borderRight: "1px solid #333", padding: 20, display: "flex", flexDirection: "column", gap: 20 }}>
        <div style={{ display: "flex", alignItems: "center", gap: 10, marginBottom: 20 }}>
          <Logo size={24} />
          <strong style={{ fontSize: 18 }}>Admin Console</strong>
        </div>
        <nav style={{ display: "grid", gap: 10 }}>
          <Link href="/admin" style={{ padding: 10, borderRadius: 8, background: "#222" }}>Dashboard</Link>
          <Link href="/admin/users" style={{ padding: 10, borderRadius: 8, background: "#222" }}>Users & Support</Link>
          <Link href="/admin/feedback" style={{ padding: 10, borderRadius: 8, background: "#222" }}>Feedback</Link>
          <Link href="/admin/notifications" style={{ padding: 10, borderRadius: 8, background: "#222" }}>Notifications</Link>
          <Link href="/" style={{ padding: 10, borderRadius: 8, color: "#aaa", marginTop: "auto" }}>← Back to App</Link>
        </nav>
      </aside>
      <main style={{ flex: 1, padding: 40, overflowY: "auto" }}>
        {children}
      </main>
    </div>
  );
}
