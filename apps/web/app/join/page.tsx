"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useAuthStatus } from "../../src/account";
import { acceptInvite } from "../../src/splits/write";

export default function JoinPage() {
  const router = useRouter();
  const auth = useAuthStatus();
  const [msg, setMsg] = useState("Opening your invite…");
  const [needsAuth, setNeedsAuth] = useState(false);

  useEffect(() => {
    const token = typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("token") : null;
    if (!token) { setMsg("This invite link is missing its token."); return; }
    if (auth === "loading") return;
    if (auth === "none") { setNeedsAuth(true); setMsg("Sign in or create an account, then open this link again to join."); return; }
    let active = true;
    (async () => {
      try {
        const gid = await acceptInvite(token);
        if (active) router.replace(`/groups/${gid}`);
      } catch (e) { if (active) setMsg((e as Error).message); }
    })();
    return () => { active = false; };
  }, [auth, router]);

  return (
    <div className="fade-up" style={{ minHeight: "70vh", display: "grid", placeItems: "center" }}>
      <div className="card" style={{ maxWidth: 420, padding: 32, textAlign: "center", display: "grid", gap: 12 }}>
        <div style={{ fontSize: 28 }}>◑</div>
        <h1 style={{ margin: 0 }}>Join a split group</h1>
        <p className="muted" style={{ margin: 0 }}>{msg}</p>
        {needsAuth && <Link href="/onboarding" className="btn" style={{ justifySelf: "center" }}>Sign in / Create account</Link>}
      </div>
    </div>
  );
}
