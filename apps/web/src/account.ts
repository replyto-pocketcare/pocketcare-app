"use client";

import { useEffect, useState } from "react";
import { getSupabase } from "./powersync";

export interface SessionInfo {
  email: string | null;
  isGuest: boolean;
  username: string;
  /** Days until a guest's data is deleted (created_at + 3 days). Null if registered. */
  daysLeft: number | null;
}

const GUEST_DAYS = 3;
const CACHE_KEY = "pc_session";

function readCache(): SessionInfo | null {
  if (typeof window === "undefined") return null;
  try { return JSON.parse(localStorage.getItem(CACHE_KEY) || "null") as SessionInfo | null; } catch { return null; }
}
function writeCache(info: SessionInfo | null): void {
  try { info ? localStorage.setItem(CACHE_KEY, JSON.stringify(info)) : localStorage.removeItem(CACHE_KEY); } catch { /* ignore */ }
}

export function useSession(): SessionInfo | null {
  // Hydrate from the cache first so name/email show instantly and survive offline.
  const [info, setInfo] = useState<SessionInfo | null>(() => readCache());

  useEffect(() => {
    let active = true;
    const load = async () => {
      try {
        // getSession() reads the locally-stored session (no network), so this
        // resolves the display name/email even with no connectivity.
        const { data } = await getSupabase().auth.getSession();
        if (!active) return;
        const u = data.session?.user ?? null;
        if (!u) { setInfo(null); writeCache(null); return; } // actually signed out
        const isGuest = Boolean((u as { is_anonymous?: boolean }).is_anonymous);
        const created = u.created_at ? new Date(u.created_at).getTime() : Date.now();
        const remainMs = created + GUEST_DAYS * 86_400_000 - Date.now();
        const daysLeft = isGuest ? Math.max(0, Math.ceil(remainMs / 86_400_000)) : null;
        const username =
          (u.user_metadata?.username as string | undefined) ||
          (typeof window !== "undefined" ? localStorage.getItem("username") || "" : "") ||
          readCache()?.username || "";
        const next: SessionInfo = { email: u.email ?? readCache()?.email ?? null, isGuest, username, daysLeft };
        setInfo(next);
        writeCache(next);
      } catch {
        // Offline / transient error: keep whatever we cached (don't blank it out).
      }
    };
    void load();
    const { data: sub } = getSupabase().auth.onAuthStateChange(() => { void load(); });
    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  return info;
}

/** Auth gate state: still loading, no session, guest (anonymous), or a real user. */
export type AuthStatus = "loading" | "none" | "guest" | "user";

/**
 * Offline-first login marker. Supabase access tokens are short-lived and, when
 * they expire while the device is offline, `getSession()` can't refresh and
 * reports *no session* — which would bounce a logged-in user to onboarding
 * mid-tunnel. We persist a tiny "who is logged in" flag on every real session
 * and, while offline, trust it instead of downgrading to "none". The app runs on
 * local SQLite regardless; the JWT only matters for network sync, which resumes
 * (and refreshes the token) once back online.
 */
const AUTH_FLAG = "pc_auth"; // "user" | "guest"
const readAuthFlag = (): "user" | "guest" | null => {
  try { const v = localStorage.getItem(AUTH_FLAG); return v === "user" || v === "guest" ? v : null; } catch { return null; }
};
const writeAuthFlag = (s: "user" | "guest") => { try { localStorage.setItem(AUTH_FLAG, s); } catch { /* ignore */ } };
export const clearAuthFlag = () => { try { localStorage.removeItem(AUTH_FLAG); } catch { /* ignore */ } };
const isOffline = () => typeof navigator !== "undefined" && navigator.onLine === false;

export function useAuthStatus(): AuthStatus {
  // Seed synchronously from the persisted marker so an offline reload/reopen
  // shows the app immediately instead of flashing the logged-out state.
  const [status, setStatus] = useState<AuthStatus>(() => readAuthFlag() ?? "loading");

  useEffect(() => {
    let active = true;
    const resolve = (user: { is_anonymous?: boolean } | null | undefined): AuthStatus =>
      !user ? "none" : user.is_anonymous ? "guest" : "user";

    const applyLive = (s: AuthStatus, event?: string) => {
      if (!active) return;
      if (s === "none") {
        // No live session. Offline with a saved marker → stay logged in.
        if (isOffline() && readAuthFlag()) return;
        // Otherwise only a genuine sign-out (or a confirmed online null) logs out.
        if (event && event !== "SIGNED_OUT" && readAuthFlag()) return;
        clearAuthFlag();
        setStatus("none");
      } else {
        writeAuthFlag(s as "user" | "guest");
        setStatus(s);
      }
    };

    void getSupabase().auth.getSession()
      .then(({ data }) => applyLive(resolve(data.session?.user)))
      .catch(() => { if (active) setStatus(readAuthFlag() ?? "none"); }); // offline throw → trust marker

    const { data: sub } = getSupabase().auth.onAuthStateChange((event, session) => {
      applyLive(resolve(session?.user), event);
    });
    return () => {
      active = false;
      sub.subscription.unsubscribe();
    };
  }, []);

  return status;
}

export async function updateUsername(name: string): Promise<void> {
  localStorage.setItem("username", name);
  try {
    await getSupabase().auth.updateUser({ data: { username: name } });
  } catch {
    /* offline — kept locally, syncs on next auth call */
  }
}

export async function signOut(): Promise<void> {
  clearAuthFlag(); // explicit sign-out: don't let the offline marker resurrect the session
  try {
    await getSupabase().auth.signOut();
  } finally {
    // Reload so the app re-initialises with a fresh session.
    window.location.href = "/onboarding";
  }
}
