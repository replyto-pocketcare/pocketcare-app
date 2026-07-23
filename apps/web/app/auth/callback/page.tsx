"use client";

/**
 * OAuth return handler. Google (via Supabase) redirects here after consent.
 * The Supabase client is created with detectSessionInUrl:true (see packages/db
 * auth.ts), so by the time this page mounts the session is already being
 * established from the URL. We wait for it, copy the Google profile (name +
 * avatar) into the app's user metadata / local cache, then route home.
 */
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import type { User } from "@supabase/supabase-js";
import { getSupabase } from "../../../src/powersync";
import { Logo } from "../../../src/ui/Logo";
import { Spinner } from "../../../src/ui/Spinner";

export default function AuthCallbackPage() {
  const router = useRouter();
  const [err, setErr] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    const cleanups: Array<() => void> = [];

    // Google/Supabase surface failures as query or hash params.
    const params = new URLSearchParams(
      window.location.search.slice(1) || window.location.hash.slice(1),
    );
    const oauthErr = params.get("error_description") || params.get("error");
    if (oauthErr) { setErr(decodeURIComponent(oauthErr.replace(/\+/g, " "))); return; }

    const finish = (user: User) => {
      const meta = (user.user_metadata ?? {}) as Record<string, unknown>;
      // Prefer a display name the user already set (e.g. a guest who linked
      // Google) over Google's profile name; adopt Google's only if none exists.
      const googleName = (meta.full_name as string | undefined) || (meta.name as string | undefined) || "";
      const name = (meta.username as string | undefined) || googleName || "";
      const avatar = (meta.avatar_url as string | undefined) || (meta.picture as string | undefined);
      try {
        if (name) localStorage.setItem("username", name);
        // Backfill the app's canonical display-name field only when it's empty.
        if (!meta.username && googleName) void getSupabase().auth.updateUser({ data: { username: googleName } }).catch(() => {});
        if (avatar) localStorage.setItem("avatarUrl", avatar);
        localStorage.setItem("onboardingSeen", "1");
      } catch { /* storage unavailable — non-fatal */ }
      router.replace("/");
    };

    const isReal = (u: User | null | undefined): u is User =>
      Boolean(u) && !(u as { is_anonymous?: boolean }).is_anonymous;

    // Fast path: session already present.
    void getSupabase().auth.getSession().then(({ data }) => {
      if (!active) return;
      if (isReal(data.session?.user)) { finish(data.session!.user); return; }

      // Otherwise wait for the client to finish exchanging the code/token.
      const { data: sub } = getSupabase().auth.onAuthStateChange((_e, sess) => {
        if (active && isReal(sess?.user)) { sub.subscription.unsubscribe(); finish(sess!.user); }
      });
      const timer = setTimeout(() => {
        if (active && !err) setErr("Sign-in is taking longer than expected. Please try again.");
      }, 15_000);
      cleanups.push(() => { sub.subscription.unsubscribe(); clearTimeout(timer); });
    });

    return () => { active = false; cleanups.forEach((c) => c()); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div style={{ maxWidth: 420, margin: "12vh auto", display: "grid", gap: 18, padding: 24, placeItems: "center", textAlign: "center" }} className="fade-up">
      <Logo size={34} />
      {err ? (
        <>
          <div className="card" style={{ padding: 14, fontSize: 14, borderColor: "var(--negative)", color: "var(--negative)" }}>{err}</div>
          <button className="btn" onClick={() => router.replace("/login?mode=signin")}>Back to sign in</button>
        </>
      ) : (
        <>
          <Spinner size={34} />
          <span className="muted">Finishing sign-in with Google…</span>
        </>
      )}
    </div>
  );
}
