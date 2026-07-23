"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import Link from "next/link";
import { useTranslation } from "react-i18next";
import { useAuthStatus } from "../../src/account";
import { acceptInvite } from "../../src/splits/write";

export default function JoinPage() {
  const { t } = useTranslation("join");
  const router = useRouter();
  const auth = useAuthStatus();
  const [msg, setMsg] = useState(t("opening"));
  const [needsAuth, setNeedsAuth] = useState(false);

  useEffect(() => {
    const token = typeof window !== "undefined" ? new URLSearchParams(window.location.search).get("token") : null;
    if (!token) { setMsg(t("missingToken")); return; }
    if (auth === "loading") return;
    if (auth === "none") {
      // Remember the invite so we can finish joining right after they sign in /
      // create an account (survives the OAuth full-page redirect). AppShell
      // routes back to /join once a session exists.
      try { localStorage.setItem("pendingInvite", token); } catch { /* ignore */ }
      setNeedsAuth(true); setMsg(t("needAuth"));
      return;
    }
    let active = true;
    (async () => {
      // Clear the stash up front: we now have a session and are consuming the
      // token, so it must not trigger another /join redirect on the next load.
      try { localStorage.removeItem("pendingInvite"); } catch { /* ignore */ }
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
        <h1 style={{ margin: 0 }}>{t("title")}</h1>
        <p className="muted" style={{ margin: 0 }}>{msg}</p>
        {needsAuth && <Link href="/onboarding" className="btn" style={{ justifySelf: "center" }}>{t("signInCreate")}</Link>}
      </div>
    </div>
  );
}
